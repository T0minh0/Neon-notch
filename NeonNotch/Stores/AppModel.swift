import Combine
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var panelState: PanelPresentationState = .collapsed {
        didSet {
            if panelState == .expanded, expandedPanelSection == .agents { unreadAttention = false }
        }
    }
    @Published private(set) var agents: [AgentSnapshot] = []
    @Published private(set) var media: MediaSnapshot = .empty
    @Published private(set) var metrics: SystemMetricsSnapshot = .zero
    @Published private(set) var metricsHistory: [SystemMetricsSnapshot] = []
    @Published private(set) var clipboardEntries: [ClipboardEntry] = []
    @Published private(set) var unreadAttention = false
    @Published private(set) var alertPulse = 0
    @Published private(set) var latestNotchAlert: NotchAlertKind = .attention
    @Published var expandedPanelSection: ExpandedPanelSection = .agents {
        didSet {
            if expandedPanelSection == .agents, panelState == .expanded { unreadAttention = false }
        }
    }
    @Published private(set) var mediaCommandInFlight: MediaCommand?
    @Published private(set) var mediaControlError: String?
    @Published var integrationMessage: String?
    @Published var showsOnboarding = !UserDefaults.standard.bool(forKey: "onboardingCompleted")
    @Published var reducedMotion = UserDefaults.standard.bool(forKey: "reducedMotion") {
        didSet { UserDefaults.standard.set(reducedMotion, forKey: "reducedMotion") }
    }
    @Published var agentNotificationsEnabled = UserDefaults.standard.object(forKey: "agentNotificationsEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(agentNotificationsEnabled, forKey: "agentNotificationsEnabled") }
    }
    @Published var alertSoundsEnabled = UserDefaults.standard.bool(forKey: "alertSoundsEnabled") {
        didSet { UserDefaults.standard.set(alertSoundsEnabled, forKey: "alertSoundsEnabled") }
    }

    let integrations = HookIntegrationManager()
    let launchAtLogin = LaunchAtLoginService()

    private let agentService = AgentMonitorService()
    private let mediaProvider: any MediaProvider
    private let metricsService = SystemMetricsService()
    let clipboardService: ClipboardService
    private var cancellables: Set<AnyCancellable> = []
    private var timers: [Timer] = []
    private var hoverTask: Task<Void, Never>?
    private var mediaErrorTask: Task<Void, Never>?
    private var started = false
    private var metricsTick = 0
    private var mediaTick = 0
    private var isDemoMode: Bool { ProcessInfo.processInfo.environment["NEON_NOTCH_DEMO"] == "1" }
    private var locksPreviewState: Bool {
        isDemoMode && ProcessInfo.processInfo.environment["NEON_NOTCH_PREVIEW_LOCKED"] == "1"
    }

    var sortedAgents: [AgentSnapshot] {
        agents.sorted {
            if $0.status.priority != $1.status.priority { return $0.status.priority < $1.status.priority }
            return $0.updatedAt > $1.updatedAt
        }
    }

    var panelAgents: [AgentSnapshot] { Array(sortedAgents.prefix(3)) }
    var hasClearableClipboardEntries: Bool { clipboardEntries.contains { !$0.isPinned } }
    var mediaControlsEnabled: Bool { media.state != .stopped && mediaCommandInFlight == nil }

    init(
        mediaProvider: any MediaProvider = SpotifyService(),
        clipboardService: ClipboardService = ClipboardService()
    ) {
        self.mediaProvider = mediaProvider
        self.clipboardService = clipboardService
        media = mediaProvider.snapshot
        clipboardService.$entries
            .receive(on: RunLoop.main)
            .sink { [weak self] entries in self?.clipboardEntries = entries }
            .store(in: &cancellables)
    }

    func start() {
        guard !started else { return }
        started = true
        try? AppPaths.prepare()
        if isDemoMode {
            applyDemoData()
            return
        }
        integrations.refreshHealth()
        NotificationService.shared.configure()
        clipboardService.start()
        refreshAgents()
        refreshMedia()
        sampleMetrics()

        schedule(every: 0.5) { [weak self] in self?.consumeHookEvents() }
        schedule(every: 2.0) { [weak self] in self?.refreshMediaIfNeeded() }
        schedule(every: 1.0) { [weak self] in self?.sampleMetricsIfNeeded() }
        schedule(every: 10.0) { [weak self] in self?.refreshAgents() }
    }

    func hoverChanged(_ hovering: Bool) {
        guard !locksPreviewState else { return }
        hoverTask?.cancel()
        if hovering, panelState == .collapsed {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled, panelState == .collapsed else { return }
                panelState = .hoverPreview
            }
        } else if !hovering, panelState == .hoverPreview {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, panelState == .hoverPreview else { return }
                panelState = .collapsed
            }
        }
    }

    func toggleExpanded() {
        guard !locksPreviewState else { return }
        hoverTask?.cancel()
        panelState = panelState == .expanded ? .collapsed : .expanded
    }

    func collapsePanel() {
        guard !locksPreviewState else { return }
        guard panelState != .collapsed else { return }
        panelState = .collapsed
    }

    func open(_ agent: AgentSnapshot) {
        agentService.open(agent)
    }

    func togglePlayback() {
        performMediaCommand(.togglePlayback)
    }

    func nextTrack() {
        performMediaCommand(.next)
    }

    func previousTrack() {
        performMediaCommand(.previousOrRestart)
    }

    func performMediaCommand(_ command: MediaCommand) {
        guard mediaControlsEnabled else { return }
        mediaCommandInFlight = command
        mediaControlError = nil
        mediaErrorTask?.cancel()

        Task {
            defer { mediaCommandInFlight = nil }
            do {
                media = try await mediaProvider.perform(command)
            } catch {
                mediaControlError = error.localizedDescription
                mediaErrorTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(4))
                    guard !Task.isCancelled else { return }
                    mediaControlError = nil
                }
            }
        }
    }

    func copyClipboard(_ entry: ClipboardEntry) { clipboardService.copy(entry) }
    func toggleClipboardPin(_ entry: ClipboardEntry) { clipboardService.togglePinned(entry.id) }
    func deleteClipboard(_ entry: ClipboardEntry) { clipboardService.delete(entry.id) }
    func clearClipboard() { clipboardService.clear() }

    func installIntegrations() {
        do {
            try integrations.installOrRepair()
            integrationMessage = "Codex and Claude Code integrations are ready. Codex may ask you to trust the new hooks."
        } catch {
            integrationMessage = error.localizedDescription
        }
    }

    func removeIntegrations() {
        do {
            try integrations.remove()
            integrationMessage = "Agent hooks removed. Backups remain in Application Support."
        } catch {
            integrationMessage = error.localizedDescription
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLogin.setEnabled(enabled)
            integrationMessage = enabled ? "Neon Notch will start at login." : "Launch at login disabled."
        } catch {
            integrationMessage = error.localizedDescription
        }
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        showsOnboarding = false
    }

    private func schedule(every interval: TimeInterval, action: @escaping @MainActor () -> Void) {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { action() }
        }
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)
    }

    private func refreshAgents() {
        Task {
            let incoming = await agentService.snapshots()
            mergeAgents(incoming)
        }
    }

    private func mergeAgents(_ incoming: [AgentSnapshot]) {
        var byID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        for agent in incoming {
            if let existing = byID[agent.id], existing.updatedAt > agent.updatedAt {
                continue
            }
            byID[agent.id] = agent
        }
        let cutoff = Date().addingTimeInterval(-86_400)
        agents = byID.values
            .filter { $0.status != .completed || $0.updatedAt > cutoff }
            .sorted {
                if $0.status.priority != $1.status.priority { return $0.status.priority < $1.status.priority }
                return $0.updatedAt > $1.updatedAt
            }
    }

    private func consumeHookEvents() {
        for event in agentService.readNewHookEvents() {
            let id = event.agentID ?? event.sessionID
            let previous = agents.first { $0.id == id }
            let snapshot = agentService.snapshot(from: event, previous: previous)
            let becameAttention = snapshot.status == .needsAttention && previous?.status != .needsAttention
            mergeAgents([snapshot])
            if becameAttention {
                latestNotchAlert = .attention
                unreadAttention = !(panelState == .expanded && expandedPanelSection == .agents)
                alertPulse += 1
                if agentNotificationsEnabled {
                    NotificationService.shared.postAttention(for: snapshot, playsSound: alertSoundsEnabled)
                }
            } else if snapshot.status == .completed && previous?.status != .completed {
                latestNotchAlert = unreadAttention ? .attention : .completion
                alertPulse += 1
            }
        }
    }

    private func refreshMedia() {
        Task {
            await mediaProvider.refresh()
            media = mediaProvider.snapshot
        }
    }

    private func refreshMediaIfNeeded() {
        guard mediaCommandInFlight == nil else { return }
        mediaTick += 1
        switch media.state {
        case .playing:
            refreshMedia()
        case .paused:
            if mediaTick.isMultiple(of: 5) { refreshMedia() }
        case .stopped:
            if mediaTick.isMultiple(of: 2) { refreshMedia() }
        }
    }

    private func sampleMetricsIfNeeded() {
        metricsTick += 1
        guard panelState != .collapsed || metricsTick.isMultiple(of: 5) else { return }
        sampleMetrics()
    }

    private func sampleMetrics() {
        Task {
            let next = await metricsService.sample()
            metrics = next
            metricsHistory.append(next)
            if metricsHistory.count > 60 { metricsHistory.removeFirst(metricsHistory.count - 60) }
        }
    }

    private func applyDemoData() {
        let now = Date()
        agents = [
            AgentSnapshot(
                id: "demo-attention",
                sessionID: "demo-attention",
                source: .codex,
                task: "Revisar migração do banco",
                project: "Neon-notch",
                workingDirectory: "/Users/demo/Neon-notch",
                startedAt: now.addingTimeInterval(-1_840),
                updatedAt: now,
                status: .needsAttention,
                reason: "Aprovação necessária para aplicar a migration"
            ),
            AgentSnapshot(
                id: "demo-working",
                sessionID: "demo-working",
                source: .claudeCode,
                task: "Refinar animação do halo",
                project: "Neon-notch",
                workingDirectory: "/Users/demo/Neon-notch",
                startedAt: now.addingTimeInterval(-720),
                updatedAt: now.addingTimeInterval(-12),
                status: .working,
                reason: "Ajustando a curva de movimento"
            ),
            AgentSnapshot(
                id: "demo-completed",
                sessionID: "demo-completed",
                source: .codex,
                task: "Criar testes do clipboard",
                project: "Neon-notch",
                workingDirectory: "/Users/demo/Neon-notch",
                startedAt: now.addingTimeInterval(-2_400),
                updatedAt: now.addingTimeInterval(-85),
                status: .completed,
                reason: "Testes concluídos"
            )
        ]
        media = MediaSnapshot(
            title: "Midnight Protocol",
            artist: "Neon District",
            album: "Ghost Signals",
            artworkURL: Bundle.main.url(forResource: "demo-album-art", withExtension: "png"),
            duration: 245,
            position: 96,
            state: .playing
        )
        metrics = SystemMetricsSnapshot(
            cpuPercent: 23,
            memoryUsed: 13_600_000_000,
            memoryTotal: 16_000_000_000,
            diskUsed: 427_000_000_000,
            diskTotal: 494_000_000_000,
            networkDownPerSecond: 128_000,
            networkUpPerSecond: 42_000,
            timestamp: now
        )
        metricsHistory = (0..<60).map { index in
            var point = metrics
            point.cpuPercent = 18 + sin(Double(index) * 0.42) * 9 + Double(index % 7)
            point.timestamp = now.addingTimeInterval(Double(index - 60))
            return point
        }
        clipboardEntries = [
            ClipboardEntry(
                id: UUID(),
                kind: .text,
                preview: "Revisar o fluxo do painel antes do próximo build",
                payload: "Revisar o fluxo do painel antes do próximo build",
                sourceBundleID: "com.openai.codex",
                sourceName: "Codex",
                createdAt: now.addingTimeInterval(-82),
                isPinned: false,
                contentHash: "demo-clipboard-text"
            ),
            ClipboardEntry(
                id: UUID(),
                kind: .url,
                preview: "https://developer.apple.com/documentation/appkit/nspasteboard",
                payload: "https://developer.apple.com/documentation/appkit/nspasteboard",
                sourceBundleID: "com.apple.Safari",
                sourceName: "Safari",
                createdAt: now.addingTimeInterval(-480),
                isPinned: true,
                contentHash: "demo-clipboard-url"
            ),
            ClipboardEntry(
                id: UUID(),
                kind: .files,
                preview: "PanelRootView.swift, MediaFooterView.swift",
                payload: "/Users/demo/PanelRootView.swift\n/Users/demo/MediaFooterView.swift",
                sourceBundleID: "com.apple.finder",
                sourceName: "Finder",
                createdAt: now.addingTimeInterval(-1_240),
                isPinned: false,
                contentHash: "demo-clipboard-files"
            ),
            ClipboardEntry(
                id: UUID(),
                kind: .image,
                preview: "Image · 1.4 MB",
                payload: "",
                sourceBundleID: "com.apple.Preview",
                sourceName: "Preview",
                createdAt: now.addingTimeInterval(-2_100),
                isPinned: false,
                contentHash: "demo-clipboard-image"
            )
        ]
        expandedPanelSection = ProcessInfo.processInfo.environment["NEON_NOTCH_PREVIEW_SECTION"]
            .flatMap(ExpandedPanelSection.init(rawValue:)) ?? .agents
        unreadAttention = ProcessInfo.processInfo.environment["NEON_NOTCH_PREVIEW_ATTENTION"] != "0"
        latestNotchAlert = .attention
        showsOnboarding = false
        panelState = ProcessInfo.processInfo.environment["NEON_NOTCH_PREVIEW_STATE"]
            .flatMap(PanelPresentationState.init(rawValue:)) ?? .expanded
    }
}
