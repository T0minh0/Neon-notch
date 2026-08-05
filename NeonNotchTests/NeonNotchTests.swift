import AppKit
import Foundation
import SwiftUI
import Testing
@testable import NeonNotch

@MainActor
private final class DelayedMediaProvider: MediaProvider {
    var snapshot = MediaSnapshot(
        title: "Test Track",
        artist: "Test Artist",
        state: .playing
    )
    var performedCommands: [MediaCommand] = []

    func refresh() async {}

    func perform(_ command: MediaCommand) async throws -> MediaSnapshot {
        performedCommands.append(command)
        try await Task.sleep(for: .milliseconds(90))
        if command == .togglePlayback { snapshot.state = .paused }
        return snapshot
    }
}

@MainActor
private final class MockHotKeyBackend: HotKeyBackend {
    var onTrigger: (() -> Void)?
    var registered: GlobalShortcutConfiguration?
    var conflictingKeyCode: UInt32?

    func register(_ configuration: GlobalShortcutConfiguration) throws {
        if configuration.keyCode == conflictingKeyCode { throw GlobalHotKeyError.registrationConflict }
        registered = configuration
    }

    func unregister() {
        registered = nil
    }
}

@Suite("Neon Notch core")
struct NeonNotchTests {
    @Test("Attention sorts before working and completed")
    func agentPriority() {
        #expect(AgentStatus.needsAttention.priority < AgentStatus.working.priority)
        #expect(AgentStatus.working.priority < AgentStatus.completed.priority)
    }

    @Test("Sanitizer removes API tokens and collapses whitespace")
    func sanitization() {
        let source = "  use api_key=secret-value\n\nthen continue  "
        #expect(source.sanitizedSummary == "use [redacted] then continue")
    }

    @Test("Hook reduction maps interaction and completion")
    @MainActor
    func hookReduction() {
        let service = AgentMonitorService()
        let base = AgentHookEvent(
            schemaVersion: 1,
            source: .codex,
            event: "PermissionRequest",
            sessionID: "thread-1",
            agentID: nil,
            parentAgentID: nil,
            workingDirectory: "/tmp/demo",
            timestamp: Date(),
            title: "Agent session",
            summary: "Aprovação necessária"
        )
        #expect(service.snapshot(from: base, previous: nil).status == .needsAttention)

        let completed = AgentHookEvent(
            schemaVersion: 1,
            source: .claudeCode,
            event: "SessionEnd",
            sessionID: "session-1",
            agentID: nil,
            parentAgentID: nil,
            workingDirectory: "/tmp/demo",
            timestamp: Date(),
            title: "Agent session",
            summary: "Concluído"
        )
        #expect(service.snapshot(from: completed, previous: nil).status == .completed)
    }

    @Test("Hook schema v1 decodes with a stable synthetic event ID")
    func hookSchemaV1Compatibility() throws {
        let json = """
        {"schemaVersion":1,"source":"codex","event":"SessionStart","sessionID":"legacy-session","workingDirectory":"/tmp/demo","timestamp":"2026-08-05T12:00:00Z","summary":"Working"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let first = try decoder.decode(AgentHookEvent.self, from: Data(json.utf8))
        let second = try decoder.decode(AgentHookEvent.self, from: Data(json.utf8))
        #expect(first.schemaVersion == 1)
        #expect(first.eventID.hasPrefix("legacy-"))
        #expect(first.eventID == second.eventID)
    }

    @Test("Only interaction notification subtypes request attention")
    func notificationSubtypeReduction() {
        let now = Date()
        let permission = hookEvent(event: "Notification", subtype: "permission_prompt", timestamp: now)
        let idle = hookEvent(event: "Notification", subtype: "idle_prompt", timestamp: now)
        let informational = hookEvent(event: "Notification", subtype: "progress", timestamp: now)
        #expect(AgentStateReducer.status(for: permission) == .needsAttention)
        #expect(AgentStateReducer.status(for: idle) == .needsAttention)
        #expect(AgentStateReducer.status(for: informational) == .unknown)
    }

    @Test("Agent precedence favors hooks, then providers, and missing active sessions become unknown")
    @MainActor
    func agentStatePrecedence() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let persisted = agentSnapshot(id: "one", status: .needsAttention, updatedAt: now.addingTimeInterval(-60))
        let provider = agentSnapshot(id: "one", status: .working, updatedAt: now.addingTimeInterval(-10))
        let hook = agentSnapshot(id: "one", status: .completed, updatedAt: now.addingTimeInterval(-5))
        #expect(AgentMonitorService.reconcile(hook: [hook], provider: [provider], persisted: [persisted], now: now).first?.status == .completed)
        #expect(AgentMonitorService.reconcile(hook: [], provider: [provider], persisted: [persisted], now: now).first?.status == .working)

        let vanished = AgentMonitorService.reconcile(hook: [], provider: [], persisted: [persisted], now: now).first
        #expect(vanished?.status == .unknown)
        #expect(vanished?.updatedAt == persisted.updatedAt)

        let staleHook = agentSnapshot(id: "stale", status: .working, updatedAt: now.addingTimeInterval(-20))
        let unavailableProvider = agentSnapshot(id: "stale", status: .unknown, updatedAt: now)
        let crashed = AgentMonitorService.reconcile(
            hook: [staleHook],
            provider: [unavailableProvider],
            persisted: [],
            now: now
        ).first
        #expect(crashed?.status == .unknown)
    }

    @Test("Event store starts live at EOF and deduplicates event IDs")
    @MainActor
    func eventStoreCursorAndDeduplication() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let log = root.appendingPathComponent("events.jsonl")
        let snapshots = root.appendingPathComponent("snapshots.json")
        let receipts = root.appendingPathComponent("receipts.json")
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let initial = hookEvent(id: "event-1", timestamp: now.addingTimeInterval(-20))
        try eventLines([initial]).write(to: log)

        let store = AgentEventStore(logURL: log, snapshotsURL: snapshots, receiptsURL: receipts, now: { now })
        #expect(store.prepareLiveCursor().map(\.eventID) == ["event-1"])
        #expect(store.readNewEvents().isEmpty)

        let duplicate = hookEvent(id: "event-2", timestamp: now)
        let handle = try FileHandle(forWritingTo: log)
        try handle.seekToEnd()
        try handle.write(contentsOf: eventLines([duplicate, duplicate]))
        try handle.close()
        #expect(store.readNewEvents().map(\.eventID) == ["event-2"])
    }

    @Test("Event log compaction removes records older than 48 hours")
    @MainActor
    func eventLogCompaction() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let log = root.appendingPathComponent("events.jsonl")
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        try eventLines([
            hookEvent(id: "old", timestamp: now.addingTimeInterval(-AgentEventStore.logMaximumAge - 1)),
            hookEvent(id: "recent", timestamp: now)
        ]).write(to: log)
        let store = AgentEventStore(
            logURL: log,
            snapshotsURL: root.appendingPathComponent("snapshots.json"),
            receiptsURL: root.appendingPathComponent("receipts.json"),
            now: { now }
        )
        store.compactIfNeeded(force: true)
        let text = try String(contentsOf: log, encoding: .utf8)
        #expect(!text.contains("\"old\""))
        #expect(text.contains("\"recent\""))
    }

    @Test("Root Codex state catalogs take precedence over legacy catalogs")
    @MainActor
    func codexCatalogDiscovery() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".codex/sqlite"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent(".codex/state_5.sqlite"))
        try Data().write(to: root.appendingPathComponent(".codex/sqlite/state_9.sqlite"))
        let store = AgentEventStore(
            logURL: root.appendingPathComponent("events"),
            snapshotsURL: root.appendingPathComponent("snapshots"),
            receiptsURL: root.appendingPathComponent("receipts")
        )
        let service = AgentMonitorService(eventStore: store, homeDirectory: root)
        let candidates = service.codexDatabaseCandidates()
        #expect(candidates.map(\.lastPathComponent) == ["state_5.sqlite", "state_9.sqlite"])
    }

    @Test("Shortcut conflicts restore the previous registration")
    @MainActor
    func globalShortcutRollback() throws {
        let suiteName = "NeonNotchTests.\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }
        let backend = MockHotKeyBackend()
        let service = GlobalHotKeyService(backend: backend, defaults: suite)
        service.start()
        #expect(backend.registered == .default)

        backend.conflictingKeyCode = 42
        var conflicting = GlobalShortcutConfiguration.default
        conflicting.keyCode = 42
        conflicting.label = "⌃⌥K"
        #expect(!service.update(conflicting))
        #expect(service.configuration == .default)
        #expect(backend.registered == .default)
    }

    @Test("Shortcut validation rejects missing modifiers and reserved macOS combinations")
    @MainActor
    func globalShortcutValidation() throws {
        var candidate = GlobalShortcutConfiguration.default
        candidate.modifiers = []
        #expect(throws: GlobalHotKeyError.missingModifier) { try GlobalHotKeyService.validate(candidate) }
        candidate.modifiers = [.command]
        #expect(throws: GlobalHotKeyError.reservedShortcut) { try GlobalHotKeyService.validate(candidate) }
        candidate.modifiers = [.control, .option]
        try GlobalHotKeyService.validate(candidate)
    }

    @Test("Clipboard hash is stable")
    func stableHash() {
        #expect("neon".contentHash == "neon".contentHash)
        #expect("neon".contentHash != "notch".contentHash)
    }

    @Test("Clipboard entries expire at exactly five hours and pins remain")
    func clipboardRetentionBoundary() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var regular = clipboardEntry(createdAt: now.addingTimeInterval(-(4 * 3_600 + 59 * 60)))
        #expect(!ClipboardRetentionPolicy.isExpired(regular, at: now))

        regular.createdAt = now.addingTimeInterval(-ClipboardRetentionPolicy.maximumAge)
        #expect(ClipboardRetentionPolicy.isExpired(regular, at: now))

        regular.isPinned = true
        #expect(!ClipboardRetentionPolicy.isExpired(regular, at: now))
        #expect(ClipboardRetentionPolicy.maximumAge == 18_000)
    }

    @Test("Clear preserves pins, leaves NSPasteboard unchanged, and removes an empty cache")
    @MainActor
    func clipboardClearPersistence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = root.appendingPathComponent("clipboard.json")
        let now = Date()
        let pinned = clipboardEntry(createdAt: now.addingTimeInterval(-20_000), isPinned: true)
        let regular = clipboardEntry(createdAt: now.addingTimeInterval(-60))
        try JSONEncoder().encode([pinned, regular]).write(to: store)

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("NeonNotchTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("keep-current-clipboard", forType: .string)
        let service = ClipboardService(pasteboard: pasteboard, storeURL: store)
        defer { service.stop() }

        service.clear()
        #expect(service.entries == [pinned])
        #expect(pasteboard.string(forType: .string) == "keep-current-clipboard")
        let persisted = try JSONDecoder().decode([ClipboardEntry].self, from: Data(contentsOf: store))
        #expect(persisted == [pinned])

        service.delete(pinned.id)
        #expect(service.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.path))
    }

    @Test("Expired items are pruned on load and immediately after unpinning")
    @MainActor
    func clipboardLoadAndUnpinPruning() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = root.appendingPathComponent("clipboard.json")
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let expired = clipboardEntry(createdAt: now.addingTimeInterval(-18_001))
        let oldPin = clipboardEntry(createdAt: now.addingTimeInterval(-25_000), isPinned: true)
        try JSONEncoder().encode([expired, oldPin]).write(to: store)

        let service = ClipboardService(storeURL: store, now: { now })
        defer { service.stop() }
        #expect(service.entries == [oldPin])

        service.togglePinned(oldPin.id)
        #expect(service.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.path))
    }

    @Test("Spotify previous command uses the three-second restart boundary")
    @MainActor
    func spotifyPreviousOrRestartScript() {
        let script = SpotifyService.script(for: .previousOrRestart)
        #expect(script.contains("player position > 3"))
        #expect(script.contains("set player position to 0"))
        #expect(script.contains("previous track"))
    }

    @Test("Rapid media commands do not create concurrent tasks")
    @MainActor
    func mediaCommandSerialization() async throws {
        let provider = DelayedMediaProvider()
        let store = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("clipboard.json")
        let clipboard = ClipboardService(storeURL: store)
        defer { clipboard.stop() }
        let model = AppModel(mediaProvider: provider, clipboardService: clipboard)

        model.performMediaCommand(.togglePlayback)
        model.performMediaCommand(.next)
        #expect(model.mediaCommandInFlight == .togglePlayback)
        try await Task.sleep(for: .milliseconds(140))

        #expect(provider.performedCommands == [.togglePlayback])
        #expect(model.media.state == .paused)
        #expect(model.mediaCommandInFlight == nil)
    }

    @Test("Completed agents expire after 24 hours")
    func retention() {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        let recent = Date().addingTimeInterval(-60)
        #expect(recent > cutoff)
        #expect(Date().addingTimeInterval(-25 * 60 * 60) < cutoff)
    }

    @Test("Notch panel dimensions match the approved visual contract")
    func notchPanelMetrics() {
        #expect(NotchPanelMetrics.expandedHeight == 380)
        #expect(NotchPanelMetrics.footerHeight == 72)
        #expect(NotchPanelMetrics.collapsedHorizontalAllowance == 16)
        #expect(NotchPanelMetrics.collapsedVerticalAllowance == 8)
        #expect(NotchPanelMetrics.taperStartY(in: CGRect(x: 0, y: 0, width: 1_120, height: 380)) == 308)
        #expect(NotchPanelMetrics.bottomInset(for: 1_120) == 300)
        #expect(NotchPanelMetrics.bottomInset(for: 800) == 216)
    }

    @Test("Expanded shape preserves its body and exposes only the lower side cutouts")
    func expandedShapeGeometry() {
        let rect = CGRect(x: 0, y: 0, width: 1_120, height: 380)
        let path = NeonNotchShape(
            topInset: 38,
            notchWidth: 210,
            taperedBottom: true
        ).path(in: rect)

        #expect(path.contains(CGPoint(x: 10, y: 300)))
        #expect(!path.contains(CGPoint(x: 40, y: 374)))
        #expect(path.contains(CGPoint(x: rect.midX, y: 374)))
    }

    @Test("Hook merge is idempotent, backed up, and removable")
    @MainActor
    func hookConfigurationLifecycle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("support", isDirectory: true)
        let bundled = root.appendingPathComponent("BundledHook")
        let destination = support.appendingPathComponent("bin/NeonNotchHook")
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try Data("helper".utf8).write(to: bundled)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundled.path)

        let custom: [String: Any] = [
            "hooks": [
                "Stop": [["hooks": [["type": "command", "command": "/usr/bin/custom-hook"]]]]
            ]
        ]
        let customData = try JSONSerialization.data(withJSONObject: custom)
        try customData.write(to: root.appendingPathComponent(".claude/settings.json"))

        let manager = HookIntegrationManager(
            homeDirectory: root,
            supportDirectory: support,
            helperURL: destination,
            bundledHelperURL: bundled
        )
        try manager.installOrRepair()
        try manager.installOrRepair()

        #expect(manager.codexReadiness.state == .awaitingTrust)
        #expect(manager.codexReadiness.isTrusted == false)
        #expect(manager.claudeReadiness.state == .ready)

        try eventLines([hookEvent(timestamp: Date())])
            .write(to: support.appendingPathComponent("agent-events.jsonl"))
        manager.refreshHealth()
        #expect(manager.codexReadiness.state == .ready)
        #expect(manager.codexReadiness.isTrusted == true)

        let data = try Data(contentsOf: root.appendingPathComponent(".claude/settings.json"))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hooks = try #require(object["hooks"] as? [String: Any])
        let stopGroups = try #require(hooks["Stop"] as? [[String: Any]])
        #expect(stopGroups.count == 2)
        #expect(FileManager.default.fileExists(atPath: support.appendingPathComponent("backups").path))

        try manager.remove()
        let removedData = try Data(contentsOf: root.appendingPathComponent(".claude/settings.json"))
        let removedObject = try #require(JSONSerialization.jsonObject(with: removedData) as? [String: Any])
        let removedHooks = try #require(removedObject["hooks"] as? [String: Any])
        let remainingStop = try #require(removedHooks["Stop"] as? [[String: Any]])
        #expect(remainingStop.count == 1)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test("Helper, Codex, and Claude integrations can be configured independently")
    @MainActor
    func independentIntegrationSetup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("support", isDirectory: true)
        let bundled = root.appendingPathComponent("BundledHook")
        let destination = support.appendingPathComponent("bin/NeonNotchHook")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("helper".utf8).write(to: bundled)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundled.path)

        let manager = HookIntegrationManager(
            homeDirectory: root,
            supportDirectory: support,
            helperURL: destination,
            bundledHelperURL: bundled
        )
        try manager.installHelperOnly()
        #expect(manager.health != .installed)
        #expect(FileManager.default.isExecutableFile(atPath: destination.path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".codex/hooks.json").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".claude/settings.json").path))

        try manager.installOrRepair(.codex)
        #expect(manager.codexHealth == .installed)
        #expect(manager.claudeHealth == .notInstalled)

        try manager.installOrRepair(.claudeCode)
        #expect(manager.health == .installed)
    }
}

private func clipboardEntry(
    createdAt: Date,
    isPinned: Bool = false
) -> ClipboardEntry {
    let payload = UUID().uuidString
    return ClipboardEntry(
        id: UUID(),
        kind: .text,
        preview: payload,
        payload: payload,
        sourceBundleID: "com.example.source",
        sourceName: "Example",
        createdAt: createdAt,
        isPinned: isPinned,
        contentHash: payload.contentHash
    )
}

private func hookEvent(
    id: String = UUID().uuidString,
    event: String = "SessionStart",
    subtype: String? = nil,
    timestamp: Date
) -> AgentHookEvent {
    AgentHookEvent(
        schemaVersion: 2,
        eventID: id,
        source: .codex,
        event: event,
        notificationSubtype: subtype,
        sessionID: "session-\(id)",
        workingDirectory: "/tmp/demo",
        timestamp: timestamp,
        summary: "Metadado seguro"
    )
}

private func eventLines(_ events: [AgentHookEvent]) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try events.reduce(into: Data()) { data, event in
        data.append(try encoder.encode(event))
        data.append(0x0A)
    }
}

private func agentSnapshot(id: String, status: AgentStatus, updatedAt: Date) -> AgentSnapshot {
    AgentSnapshot(
        id: id,
        sessionID: "session-\(id)",
        source: .codex,
        task: "Safe task",
        project: "Project",
        workingDirectory: "/tmp/project",
        startedAt: updatedAt.addingTimeInterval(-60),
        updatedAt: updatedAt,
        status: status,
        reason: nil
    )
}
