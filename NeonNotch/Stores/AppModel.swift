import AppKit
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
    @Published var onboardingStep = OnboardingStep(
        rawValue: UserDefaults.standard.integer(forKey: "onboardingStep")
    ) ?? .installation {
        didSet { UserDefaults.standard.set(onboardingStep.rawValue, forKey: "onboardingStep") }
    }
    @Published private(set) var providerReadiness: [AgentSource: ProviderReadiness] = [:]
    @Published var requestedControlCenterSection: ControlCenterSection = .agents
    @Published var selectedAgentID: String?
    @Published var selectedClipboardID: UUID?
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
    let globalHotKey: GlobalHotKeyService
    let permissionDiagnostics: PermissionDiagnosticsService

    private let agentService: AgentMonitorService
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
    private var agentRefreshTick = 0
    private var didBootstrapAgents = false
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
    var onboardingCompleted: Bool { UserDefaults.standard.bool(forKey: "onboardingCompleted") }

    init(
        mediaProvider: any MediaProvider = SpotifyService(),
        clipboardService: ClipboardService = ClipboardService(),
        agentService: AgentMonitorService = AgentMonitorService(),
        globalHotKey: GlobalHotKeyService = GlobalHotKeyService(),
        permissionDiagnostics: PermissionDiagnosticsService = PermissionDiagnosticsService()
    ) {
        self.mediaProvider = mediaProvider
        self.clipboardService = clipboardService
        self.agentService = agentService
        self.globalHotKey = globalHotKey
        self.permissionDiagnostics = permissionDiagnostics
        media = mediaProvider.snapshot
        clipboardService.$entries
            .receive(on: RunLoop.main)
            .sink { [weak self] entries in self?.clipboardEntries = entries }
            .store(in: &cancellables)
        integrations.$lastMessage
            .compactMap { $0 }
            .sink { [weak self] message in self?.integrationMessage = message }
            .store(in: &cancellables)
        globalHotKey.onTrigger = { [weak self] in self?.toggleExpandedFromShortcut() }
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
        NotificationService.shared.configure { [weak self] target in
            self?.openNotificationTarget(target)
        }
        clipboardService.start()
        globalHotKey.start()
        NSApp.dockTile.badgeLabel = onboardingCompleted ? nil : "!"
        bootstrapAgents()
        refreshMedia()
        sampleMetrics()
        refreshDiagnostics()

        schedule(every: 0.5) { [weak self] in self?.consumeHookEvents() }
        schedule(every: 2.0) { [weak self] in self?.refreshMediaIfNeeded() }
        schedule(every: 1.0) { [weak self] in self?.sampleMetricsIfNeeded() }
        schedule(every: 10.0) { [weak self] in self?.refreshAgentsIfNeeded() }
        schedule(every: 300.0) { [weak self] in
            self?.agentService.compactEventLog()
            self?.refreshDiagnostics()
        }
    }

    func hoverChanged(_ hovering: Bool) {
        guard !locksPreviewState else { return }
        hoverTask?.cancel()
        if hovering, panelState == .collapsed {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled, panelState == .collapsed else { return }
                panelState = .hoverPreview
                refreshVisibleData()
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
        if panelState == .expanded { refreshVisibleData() }
    }

    func toggleExpandedFromShortcut() {
        guard !locksPreviewState else { return }
        if panelState == .expanded {
            collapsePanel()
            return
        }
        switch globalHotKey.configuration.target {
        case .lastSection:
            break
        case .agents:
            expandedPanelSection = .agents
        case .clipboard:
            expandedPanelSection = .clipboard
        }
        ensureKeyboardSelection()
        panelState = .expanded
        refreshVisibleData()
        NotificationCenter.default.post(name: .globalShortcutTriggered, object: nil)
    }

    func collapsePanel() {
        guard !locksPreviewState else { return }
        guard panelState != .collapsed else { return }
        panelState = .collapsed
    }

    func handleWake() {
        globalHotKey.restoreAfterWake()
        agentService.compactEventLog()
        refreshAgents()
        refreshDiagnostics()
    }

    func open(_ agent: AgentSnapshot) {
        agentService.open(agent)
    }

    func handlePanelKeyEvent(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
        if command, event.charactersIgnoringModifiers == "1" {
            expandedPanelSection = .agents
            ensureKeyboardSelection()
            return true
        }
        if command, event.charactersIgnoringModifiers == "2" {
            expandedPanelSection = .clipboard
            ensureKeyboardSelection()
            return true
        }

        switch event.keyCode {
        case 125:
            moveKeyboardSelection(by: 1)
            return true
        case 126:
            moveKeyboardSelection(by: -1)
            return true
        case 36, 76:
            activateKeyboardSelection()
            return true
        case 51, 117:
            guard expandedPanelSection == .clipboard else { return false }
            confirmDeleteSelectedClipboard()
            return true
        default:
            if expandedPanelSection == .clipboard,
               event.charactersIgnoringModifiers?.lowercased() == "p",
               !command {
                if let entry = selectedClipboardEntry { toggleClipboardPin(entry) }
                return true
            }
            return false
        }
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
            integrationMessage = "Integrações instaladas. No Codex, revise o helper explicitamente pelo comando /hooks."
            refreshDiagnostics()
        } catch {
            integrationMessage = error.localizedDescription
        }
    }

    func installHelper() {
        do {
            try integrations.installHelperOnly()
            integrationMessage = "Helper v2 instalado e pronto para teste."
            refreshDiagnostics()
        } catch {
            integrationMessage = error.localizedDescription
        }
    }

    func installIntegration(_ source: AgentSource) {
        do {
            try integrations.installOrRepair(source)
            integrationMessage = source == .codex
                ? "Codex configurado. Use /hooks para revisar e confiar explicitamente no helper."
                : "Claude Code configurado. Inicie uma nova sessão para validar os eventos."
            refreshDiagnostics()
        } catch {
            integrationMessage = error.localizedDescription
        }
    }

    func removeIntegrations() {
        do {
            try integrations.remove()
            integrationMessage = "Hooks removidos. Os backups permanecem em Application Support."
            refreshDiagnostics()
        } catch {
            integrationMessage = error.localizedDescription
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLogin.setEnabled(enabled)
            integrationMessage = enabled ? "Neon Notch will start at login." : "Launch at login disabled."
            refreshDiagnostics()
        } catch {
            integrationMessage = error.localizedDescription
        }
    }

    func completeOnboarding() {
        guard onboardingStep == .summary else { return }
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        showsOnboarding = false
        NSApp.dockTile.badgeLabel = nil
    }

    func continueOnboardingLater() {
        showsOnboarding = false
    }

    func resumeOnboarding() {
        showsOnboarding = true
        NotificationCenter.default.post(name: .openControlCenter, object: nil)
    }

    func advanceOnboarding() {
        guard let next = OnboardingStep(rawValue: onboardingStep.rawValue + 1) else { return }
        onboardingStep = next
    }

    func goBackOnboarding() {
        guard let previous = OnboardingStep(rawValue: onboardingStep.rawValue - 1) else { return }
        onboardingStep = previous
    }

    func testHelper() {
        Task {
            _ = await integrations.testHelper()
            refreshDiagnostics()
        }
    }

    func requestNotifications() {
        Task {
            _ = await permissionDiagnostics.requestNotifications()
            refreshDiagnostics()
        }
    }

    func testAutomation(_ kind: PermissionDiagnosticKind) {
        Task {
            _ = await permissionDiagnostics.testAutomation(kind)
            refreshDiagnostics()
        }
    }

    func refreshDiagnostics() {
        integrations.refreshHealth()
        providerReadiness = mergedProviderReadiness()
        Task {
            await permissionDiagnostics.refresh(
                integrations: integrations,
                providerReadiness: providerReadiness,
                launchAtLogin: launchAtLogin
            )
        }
    }

    private func schedule(every interval: TimeInterval, action: @escaping @MainActor () -> Void) {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { action() }
        }
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)
    }

    private var selectedClipboardEntry: ClipboardEntry? {
        guard let selectedClipboardID else { return clipboardEntries.first }
        return clipboardEntries.first { $0.id == selectedClipboardID }
    }

    private func ensureKeyboardSelection() {
        switch expandedPanelSection {
        case .agents:
            if !panelAgents.contains(where: { $0.id == selectedAgentID }) {
                selectedAgentID = panelAgents.first?.id
            }
        case .clipboard:
            if !clipboardEntries.contains(where: { $0.id == selectedClipboardID }) {
                selectedClipboardID = clipboardEntries.first?.id
            }
        }
    }

    private func moveKeyboardSelection(by offset: Int) {
        switch expandedPanelSection {
        case .agents:
            let values = panelAgents
            guard !values.isEmpty else { return }
            let current = values.firstIndex { $0.id == selectedAgentID } ?? (offset > 0 ? -1 : 0)
            selectedAgentID = values[min(max(0, current + offset), values.count - 1)].id
        case .clipboard:
            let values = clipboardEntries
            guard !values.isEmpty else { return }
            let current = values.firstIndex { $0.id == selectedClipboardID } ?? (offset > 0 ? -1 : 0)
            selectedClipboardID = values[min(max(0, current + offset), values.count - 1)].id
        }
    }

    private func activateKeyboardSelection() {
        switch expandedPanelSection {
        case .agents:
            guard let agent = panelAgents.first(where: { $0.id == selectedAgentID }) ?? panelAgents.first else { return }
            open(agent)
        case .clipboard:
            guard let entry = selectedClipboardEntry else { return }
            copyClipboard(entry)
        }
    }

    private func confirmDeleteSelectedClipboard() {
        guard let entry = selectedClipboardEntry else { return }
        let alert = NSAlert()
        alert.messageText = "Excluir este item do Clipboard?"
        alert.informativeText = entry.preview
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Excluir")
        alert.addButton(withTitle: "Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        deleteClipboard(entry)
        selectedClipboardID = clipboardEntries.first?.id
    }

    private func openNotificationTarget(_ target: AgentNotificationTarget) {
        if let agent = agents.first(where: { $0.sessionID == target.sessionID && $0.source == target.source }) {
            open(agent)
            return
        }
        integrationMessage = "A sessão não existe mais. Revise os agentes recentes e repare a integração se necessário."
        requestedControlCenterSection = .agents
        NotificationCenter.default.post(name: .openControlCenter, object: nil)
    }

    private func mergedProviderReadiness() -> [AgentSource: ProviderReadiness] {
        var result = agentService.readiness
        for (source, integration) in [
            (AgentSource.codex, integrations.codexReadiness),
            (AgentSource.claudeCode, integrations.claudeReadiness)
        ] {
            var combined = integration
            if let provider = result[source] {
                combined.isAvailable = provider.isAvailable
                combined.detectedVersion = provider.detectedVersion
                combined.lastActivity = [integration.lastActivity, provider.lastActivity].compactMap { $0 }.max()
                if combined.state == .ready, !provider.isAvailable { combined.state = .degraded }
            }
            result[source] = combined
        }
        return result
    }

    private func bootstrapAgents() {
        Task {
            let initial = await agentService.bootstrapSnapshots()
            agents = initial
            didBootstrapAgents = true
            providerReadiness = mergedProviderReadiness()
            refreshDiagnostics()
        }
    }

    private func refreshAgents() {
        guard didBootstrapAgents else { return }
        Task {
            let incoming = await agentService.snapshots()
            let stabilized = stabilize(incoming)
            if stabilized != agents { agents = stabilized }
            let readiness = mergedProviderReadiness()
            if readiness != providerReadiness { providerReadiness = readiness }
        }
    }

    private func refreshAgentsIfNeeded() {
        agentRefreshTick += 1
        guard panelState != .collapsed || agentRefreshTick.isMultiple(of: 3) else { return }
        refreshAgents()
    }

    private func stabilize(_ incoming: [AgentSnapshot]) -> [AgentSnapshot] {
        let current = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        return incoming.map { candidate in
            guard let previous = current[candidate.id],
                  previous.sessionID == candidate.sessionID,
                  previous.agentID == candidate.agentID,
                  previous.parentID == candidate.parentID,
                  previous.source == candidate.source,
                  previous.task == candidate.task,
                  previous.project == candidate.project,
                  previous.workingDirectory == candidate.workingDirectory,
                  previous.status == candidate.status,
                  previous.reason == candidate.reason else { return candidate }
            var stable = candidate
            stable.startedAt = previous.startedAt
            stable.updatedAt = previous.updatedAt
            return stable
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
        agentService.persist(agents)
        ensureKeyboardSelection()
    }

    private func consumeHookEvents() {
        let events = agentService.readNewHookEvents()
        guard !events.isEmpty else { return }
        for event in events {
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
        integrations.refreshHealth()
        providerReadiness = mergedProviderReadiness()
    }

    private func refreshMedia() {
        Task {
            await mediaProvider.refresh()
            let next = mediaProvider.snapshot
            if next != media { media = next }
        }
    }

    private func refreshMediaIfNeeded() {
        guard mediaCommandInFlight == nil else { return }
        mediaTick += 1
        if panelState == .collapsed {
            if mediaTick.isMultiple(of: 3) { refreshMedia() }
            return
        }
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

    private func refreshVisibleData() {
        refreshMedia()
        sampleMetrics()
        refreshAgents()
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
