import AppKit
import Foundation

enum PanelPresentationState: String, Codable, CaseIterable, Sendable {
    case collapsed
    case hoverPreview
    case expanded
}

enum ExpandedPanelSection: String, CaseIterable, Identifiable, Sendable {
    case agents
    case clipboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .agents: "Agentes"
        case .clipboard: "Clipboard"
        }
    }

    var symbol: String {
        switch self {
        case .agents: "point.3.connected.trianglepath.dotted"
        case .clipboard: "clipboard"
        }
    }
}

enum NotchAlertKind: String, Codable, Sendable {
    case attention
    case completion
}

enum AgentStatus: String, Codable, CaseIterable, Sendable {
    case working
    case needsAttention
    case completed
    case unknown

    var priority: Int {
        switch self {
        case .needsAttention: 0
        case .working: 1
        case .completed: 2
        case .unknown: 3
        }
    }

    var title: String {
        switch self {
        case .working: "WORKING"
        case .needsAttention: "NEEDS YOU"
        case .completed: "DONE"
        case .unknown: "OFFLINE"
        }
    }

    var symbol: String {
        switch self {
        case .working: "waveform.path.ecg"
        case .needsAttention: "exclamationmark.circle"
        case .completed: "checkmark"
        case .unknown: "questionmark"
        }
    }
}

enum AgentSource: String, Codable, CaseIterable, Sendable {
    case codex
    case claudeCode

    var title: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude"
        }
    }

    var symbol: String {
        switch self {
        case .codex: "cube.transparent"
        case .claudeCode: "sparkles"
        }
    }
}

struct AgentSnapshot: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var sessionID: String
    var agentID: String?
    var parentID: String?
    var source: AgentSource
    var task: String
    var project: String
    var workingDirectory: String
    var startedAt: Date
    var updatedAt: Date
    var status: AgentStatus
    var reason: String?

    var elapsed: TimeInterval { max(0, Date().timeIntervalSince(startedAt)) }
    var title: String { task }
    var summary: String { reason ?? project }
    var duration: TimeInterval { elapsed }
}

enum ProviderReadinessState: String, Codable, CaseIterable, Sendable {
    case setupRequired
    case awaitingTrust
    case ready
    case degraded
    case unavailable
}

struct ProviderReadiness: Codable, Equatable, Sendable {
    var state: ProviderReadinessState
    var isAvailable: Bool
    var detectedVersion: String?
    var isConfigured: Bool
    var isTrusted: Bool?
    var lastActivity: Date?
    var detail: String

    static func unavailable(_ detail: String) -> ProviderReadiness {
        ProviderReadiness(
            state: .unavailable,
            isAvailable: false,
            detectedVersion: nil,
            isConfigured: false,
            isTrusted: nil,
            lastActivity: nil,
            detail: detail
        )
    }
}

struct AgentHookEvent: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var eventID: String
    var source: AgentSource
    var event: String
    var notificationSubtype: String?
    var sessionID: String
    var agentID: String?
    var parentAgentID: String?
    var workingDirectory: String?
    var timestamp: Date
    var title: String?
    var summary: String?

    init(
        schemaVersion: Int = 2,
        eventID: String = UUID().uuidString,
        source: AgentSource,
        event: String,
        notificationSubtype: String? = nil,
        sessionID: String,
        agentID: String? = nil,
        parentAgentID: String? = nil,
        workingDirectory: String? = nil,
        timestamp: Date,
        title: String? = nil,
        summary: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.eventID = eventID
        self.source = source
        self.event = event
        self.notificationSubtype = notificationSubtype
        self.sessionID = sessionID
        self.agentID = agentID
        self.parentAgentID = parentAgentID
        self.workingDirectory = workingDirectory
        self.timestamp = timestamp
        self.title = title?.sanitizedSummary
        self.summary = summary?.sanitizedSummary
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        source = try values.decode(AgentSource.self, forKey: .source)
        event = try values.decode(String.self, forKey: .event)
        notificationSubtype = try values.decodeIfPresent(String.self, forKey: .notificationSubtype)
        sessionID = try values.decode(String.self, forKey: .sessionID)
        agentID = try values.decodeIfPresent(String.self, forKey: .agentID)
        parentAgentID = try values.decodeIfPresent(String.self, forKey: .parentAgentID)
        workingDirectory = try values.decodeIfPresent(String.self, forKey: .workingDirectory)
        timestamp = try values.decode(Date.self, forKey: .timestamp)
        title = try values.decodeIfPresent(String.self, forKey: .title)?.sanitizedSummary
        summary = try values.decodeIfPresent(String.self, forKey: .summary)?.sanitizedSummary
        eventID = try values.decodeIfPresent(String.self, forKey: .eventID)
            ?? Self.legacyIdentifier(
                source: source,
                event: event,
                sessionID: sessionID,
                agentID: agentID,
                timestamp: timestamp
            )
    }

    private static func legacyIdentifier(
        source: AgentSource,
        event: String,
        sessionID: String,
        agentID: String?,
        timestamp: Date
    ) -> String {
        let seed = [
            source.rawValue,
            event,
            sessionID,
            agentID ?? "",
            String(timestamp.timeIntervalSince1970)
        ].joined(separator: "|")
        return "legacy-\(seed.contentHash)"
    }
}

enum AgentStateReducer {
    private static let attentionSubtypes: Set<String> = [
        "permission_prompt", "idle_prompt", "input_needed", "approval_requested",
        "elicitation", "user_input_required"
    ]

    static func status(for event: AgentHookEvent) -> AgentStatus {
        switch event.event.lowercased() {
        case "permissionrequest", "inputneeded", "approval-requested":
            return .needsAttention
        case "notification":
            guard let subtype = event.notificationSubtype?.lowercased() else { return .unknown }
            return attentionSubtypes.contains(subtype) ? .needsAttention : .unknown
        case "stop", "subagentstop", "sessionend", "agent-turn-complete":
            return .completed
        case "sessionstart", "subagentstart", "userpromptsubmit", "task_started":
            return .working
        default:
            return .unknown
        }
    }
}

enum GlobalShortcutTarget: String, Codable, CaseIterable, Identifiable, Sendable {
    case lastSection
    case agents
    case clipboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lastSection: "Última seção"
        case .agents: "Agentes"
        case .clipboard: "Clipboard"
        }
    }
}

struct GlobalShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt32

    static let control = GlobalShortcutModifiers(rawValue: 1 << 0)
    static let option = GlobalShortcutModifiers(rawValue: 1 << 1)
    static let shift = GlobalShortcutModifiers(rawValue: 1 << 2)
    static let command = GlobalShortcutModifiers(rawValue: 1 << 3)
}

struct GlobalShortcutConfiguration: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: GlobalShortcutModifiers
    var label: String
    var target: GlobalShortcutTarget

    static let `default` = GlobalShortcutConfiguration(
        keyCode: 49,
        modifiers: [.control, .option],
        label: "⌃⌥Space",
        target: .lastSection
    )
}

enum OnboardingStep: Int, Codable, CaseIterable, Identifiable, Sendable {
    case installation
    case helper
    case providers
    case notifications
    case automation
    case launchAtLogin
    case summary

    var id: Int { rawValue }
}

enum PlaybackState: String, Codable, Sendable {
    case playing
    case paused
    case stopped
}

struct MediaSnapshot: Equatable, Sendable {
    var title = "Nothing playing"
    var artist = "Spotify"
    var album = ""
    var artworkURL: URL?
    var duration: TimeInterval = 0
    var position: TimeInterval = 0
    var state: PlaybackState = .stopped

    static let empty = MediaSnapshot()
}

enum MediaCommand: Equatable, Sendable {
    case togglePlayback
    case previousOrRestart
    case next
}

enum MediaProviderError: LocalizedError, Equatable, Sendable {
    case spotifyNotRunning
    case automationDenied
    case commandFailed

    var errorDescription: String? {
        switch self {
        case .spotifyNotRunning:
            "Abra o Spotify para usar os controles."
        case .automationDenied:
            "Permita que o Neon Notch controle o Spotify nos Ajustes do Sistema."
        case .commandFailed:
            "O Spotify não respondeu. Tente novamente."
        }
    }
}

struct SystemMetricsSnapshot: Equatable, Sendable {
    var cpuPercent: Double = 0
    var memoryUsed: UInt64 = 0
    var memoryTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    var diskUsed: UInt64 = 0
    var diskTotal: UInt64 = 0
    var networkDownPerSecond: UInt64 = 0
    var networkUpPerSecond: UInt64 = 0
    var timestamp = Date()

    static let zero = SystemMetricsSnapshot()

    var memoryPercent: Double {
        guard memoryTotal > 0 else { return 0 }
        return Double(memoryUsed) / Double(memoryTotal) * 100
    }

    var storagePercent: Double {
        guard diskTotal > 0 else { return 0 }
        return Double(diskUsed) / Double(diskTotal) * 100
    }

    var downloadBytesPerSecond: UInt64 { networkDownPerSecond }
    var uploadBytesPerSecond: UInt64 { networkUpPerSecond }
}

enum ClipboardContentKind: String, Codable, CaseIterable, Sendable {
    case text
    case url
    case image
    case files

    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .url: "link"
        case .image: "photo"
        case .files: "doc.on.doc"
        }
    }
}

struct ClipboardEntry: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var kind: ClipboardContentKind
    var preview: String
    var payload: String
    var sourceBundleID: String?
    var sourceName: String
    var createdAt: Date
    var isPinned: Bool
    var contentHash: String
}

enum ClipboardRetentionPolicy {
    static let maximumAge: TimeInterval = 18_000

    static func isExpired(_ entry: ClipboardEntry, at date: Date = Date()) -> Bool {
        !entry.isPinned && entry.createdAt.addingTimeInterval(maximumAge) <= date
    }

    static func retainedEntries(from entries: [ClipboardEntry], at date: Date = Date()) -> [ClipboardEntry] {
        entries.filter { !isExpired($0, at: date) }
    }
}

enum ControlCenterSection: String, CaseIterable, Identifiable {
    case agents
    case clipboard
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .agents: "Agents"
        case .clipboard: "Clipboard"
        case .system: "System"
        }
    }

    var symbol: String {
        switch self {
        case .agents: "point.3.connected.trianglepath.dotted"
        case .clipboard: "clipboard"
        case .system: "waveform.path.ecg.rectangle"
        }
    }
}

@MainActor
protocol AgentProvider: AnyObject {
    var readiness: [AgentSource: ProviderReadiness] { get }
    func snapshots() async -> [AgentSnapshot]
    func open(_ snapshot: AgentSnapshot)
}

@MainActor
protocol MediaProvider: AnyObject {
    var snapshot: MediaSnapshot { get }
    func refresh() async
    func perform(_ command: MediaCommand) async throws -> MediaSnapshot
}

@MainActor
protocol MetricsProvider: AnyObject {
    func sample() async -> SystemMetricsSnapshot
}

@MainActor
protocol ClipboardProvider: AnyObject {
    var entries: [ClipboardEntry] { get }
    func copy(_ entry: ClipboardEntry)
}
