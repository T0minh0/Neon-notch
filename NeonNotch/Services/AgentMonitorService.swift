import AppKit
import Darwin
import Foundation

@MainActor
final class AgentMonitorService: AgentProvider {
    private(set) var readiness: [AgentSource: ProviderReadiness] = [
        .codex: .unavailable("Catálogo do Codex não encontrado."),
        .claudeCode: .unavailable("Claude Code não encontrado.")
    ]

    private let eventStore: AgentEventStore
    private let homeDirectory: URL
    private var hookSnapshots: [String: AgentSnapshot] = [:]
    private var detectedVersions: [AgentSource: String] = [:]
    private var didBootstrap = false

    init(
        eventStore: AgentEventStore = AgentEventStore(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.eventStore = eventStore
        self.homeDirectory = homeDirectory
    }

    func bootstrapSnapshots() async -> [AgentSnapshot] {
        guard !didBootstrap else { return await snapshots() }
        didBootstrap = true

        await detectVersions()
        let persisted = eventStore.loadSnapshots()
        let reconstructed = eventStore.prepareLiveCursor()
        for event in reconstructed {
            let id = event.agentID ?? event.sessionID
            hookSnapshots[id] = snapshot(from: event, previous: hookSnapshots[id] ?? persisted.first { $0.id == id })
        }
        let provider = await providerSnapshots()
        let reconciled = Self.reconcile(
            hook: Array(hookSnapshots.values),
            provider: provider,
            persisted: persisted
        )
        eventStore.persistSnapshots(reconciled)
        return reconciled
    }

    func snapshots() async -> [AgentSnapshot] {
        let provider = await providerSnapshots()
        let reconciled = Self.reconcile(
            hook: Array(hookSnapshots.values),
            provider: provider,
            persisted: eventStore.loadSnapshots()
        )
        eventStore.persistSnapshots(reconciled)
        return reconciled
    }

    func readNewHookEvents() -> [AgentHookEvent] {
        let events = eventStore.readNewEvents()
        for event in events {
            let id = event.agentID ?? event.sessionID
            hookSnapshots[id] = snapshot(from: event, previous: hookSnapshots[id])
        }
        return events
    }

    func persist(_ snapshots: [AgentSnapshot]) {
        eventStore.persistSnapshots(snapshots)
    }

    func compactEventLog() {
        eventStore.compactIfNeeded()
    }

    func snapshot(from event: AgentHookEvent, previous: AgentSnapshot?) -> AgentSnapshot {
        let reducedStatus = AgentStateReducer.status(for: event)
        let status = reducedStatus == .unknown && event.event.lowercased() == "notification"
            ? (previous?.status ?? .unknown)
            : reducedStatus
        let fallbackTask = event.agentID.map { "Agent \($0.prefix(8))" } ?? "Agent session"
        let projectURL = URL(fileURLWithPath: event.workingDirectory ?? previous?.workingDirectory ?? "")
        let project = projectURL.lastPathComponent.isEmpty ? (previous?.project ?? "Local workspace") : projectURL.lastPathComponent
        return AgentSnapshot(
            id: event.agentID ?? event.sessionID,
            sessionID: event.sessionID,
            agentID: event.agentID,
            parentID: event.parentAgentID,
            source: event.source,
            task: event.title?.sanitizedSummary ?? previous?.task ?? fallbackTask,
            project: project,
            workingDirectory: event.workingDirectory ?? previous?.workingDirectory ?? "",
            startedAt: previous?.startedAt ?? event.timestamp,
            updatedAt: event.timestamp,
            status: status,
            reason: event.summary?.sanitizedSummary
        )
    }

    func open(_ snapshot: AgentSnapshot) {
        SessionOpeningService.open(snapshot)
    }

    static func reconcile(
        hook: [AgentSnapshot],
        provider: [AgentSnapshot],
        persisted: [AgentSnapshot],
        now: Date = Date()
    ) -> [AgentSnapshot] {
        let hookByID = Dictionary(hook.map { ($0.id, $0) }, uniquingKeysWith: newest)
        let providerByID = Dictionary(provider.map { ($0.id, $0) }, uniquingKeysWith: newest)
        let persistedByID = Dictionary(persisted.map { ($0.id, $0) }, uniquingKeysWith: newest)
        let identifiers = Set(hookByID.keys).union(providerByID.keys).union(persistedByID.keys)
        let terminalBySessionID = Dictionary(
            hookByID.values
                .filter { $0.status == .completed && $0.agentID == nil }
                .map { ($0.sessionID, $0) },
            uniquingKeysWith: newest
        )
        let cutoff = now.addingTimeInterval(-86_400)

        return identifiers.compactMap { id -> AgentSnapshot? in
            let candidate = hookByID[id] ?? providerByID[id] ?? persistedByID[id]
            if let candidate,
               let terminal = terminalBySessionID[candidate.sessionID],
               candidate.id != terminal.id {
                return nil
            }
            if var live = hookByID[id] {
                let providerIsActive = providerByID[id].map {
                    $0.status == .working || $0.status == .needsAttention
                } ?? false
                if live.status != .completed,
                   !providerIsActive,
                   now.timeIntervalSince(live.updatedAt) > 15 {
                    live.status = .unknown
                    live.reason = "Sessão não está mais ativa"
                }
                return live
            }
            if let active = providerByID[id] { return active }
            guard var saved = persistedByID[id], saved.updatedAt >= cutoff else { return nil }
            if saved.status != .completed {
                saved.status = .unknown
                saved.reason = "Sessão não está mais ativa"
            }
            return saved
        }
        .filter { $0.status != .completed || $0.updatedAt >= cutoff }
        .sorted(by: sortSnapshots)
    }

    private func providerSnapshots() async -> [AgentSnapshot] {
        let codex = await codexSnapshots()
        let claude = await claudeSnapshots()
        return (codex + claude).sorted(by: Self.sortSnapshots)
    }

    private func codexSnapshots() async -> [AgentSnapshot] {
        let candidates = codexDatabaseCandidates()
        guard !candidates.isEmpty else {
            readiness[.codex] = .unavailable("Nenhum catálogo state_*.sqlite foi encontrado em ~/.codex.")
            return []
        }

        let query = """
        SELECT id, cwd, updated_at, rollout_path
        FROM threads
        WHERE archived = 0
        ORDER BY updated_at DESC
        LIMIT 20;
        """
        for database in candidates {
            let result = await ProcessRunner.run("/usr/bin/sqlite3", arguments: ["-readonly", "-json", database.path, query])
            guard result.status == 0, let data = result.stdout.data(using: .utf8),
                  let rows = try? JSONDecoder().decode([CodexThreadRow].self, from: data) else { continue }
            let now = Date()
            let snapshots = rows.compactMap { row -> AgentSnapshot? in
                let updated = Self.date(fromEpoch: row.updatedAt)
                guard updated >= now.addingTimeInterval(-86_400) else { return nil }
                let status = inferCodexStatus(rolloutPath: row.rolloutPath, updatedAt: updated)
                let project = URL(fileURLWithPath: row.cwd).lastPathComponent
                return AgentSnapshot(
                    id: row.id,
                    sessionID: row.id,
                    source: .codex,
                    task: project.isEmpty ? "Codex session" : "Codex · \(project)",
                    project: project.isEmpty ? "Local workspace" : project,
                    workingDirectory: row.cwd,
                    startedAt: updated.addingTimeInterval(-min(2_400, max(60, now.timeIntervalSince(updated)))),
                    updatedAt: updated,
                    status: status,
                    reason: status == .needsAttention ? "Aguardando sua interação" : nil
                )
            }
            readiness[.codex] = ProviderReadiness(
                state: .ready,
                isAvailable: true,
                detectedVersion: detectedVersions[.codex] ?? database.deletingPathExtension().lastPathComponent,
                isConfigured: false,
                isTrusted: nil,
                lastActivity: snapshots.map(\.updatedAt).max(),
                detail: "Catálogo somente leitura: \(database.lastPathComponent)"
            )
            return snapshots
        }

        readiness[.codex] = ProviderReadiness(
            state: .degraded,
            isAvailable: true,
            detectedVersion: detectedVersions[.codex],
            isConfigured: false,
            isTrusted: nil,
            lastActivity: nil,
            detail: "Nenhum catálogo do Codex possui um schema compatível."
        )
        return []
    }

    private func inferCodexStatus(rolloutPath: String, updatedAt: Date) -> AgentStatus {
        guard let tail = tailString(at: URL(fileURLWithPath: rolloutPath), bytes: 131_072) else {
            return Date().timeIntervalSince(updatedAt) <= 15 ? .working : .unknown
        }
        let requestCount = tail.components(separatedBy: "\"name\":\"request_user_input\"").count - 1
        let outputCount = tail.components(separatedBy: "\"type\":\"custom_tool_call_output\"").count - 1
        if requestCount > outputCount { return .needsAttention }
        if tail.contains("\"phase\":\"final_answer\"") { return .completed }
        return Date().timeIntervalSince(updatedAt) <= 15 ? .working : .unknown
    }

    private func claudeSnapshots() async -> [AgentSnapshot] {
        let result = await ProcessRunner.run("/usr/bin/env", arguments: ["claude", "agents", "--json", "--all"])
        guard result.status == 0,
              let data = result.stdout.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            readiness[.claudeCode] = ProviderReadiness(
                state: .unavailable,
                isAvailable: false,
                detectedVersion: detectedVersions[.claudeCode],
                isConfigured: false,
                isTrusted: nil,
                lastActivity: nil,
                detail: "claude agents --json --all não respondeu."
            )
            return []
        }

        let now = Date()
        let snapshots = array.prefix(40).compactMap { item -> AgentSnapshot? in
            guard let sessionID = (item["sessionId"] as? String) ?? (item["id"] as? String) else { return nil }
            let id = (item["id"] as? String) ?? sessionID
            let cwd = item["cwd"] as? String ?? ""
            let rawState = (item["state"] as? String)?.lowercased()
            let processIdentifier = (item["pid"] as? Int) ?? (item["pid"] as? String).flatMap(Int.init)
            let processIsRunning = processIdentifier.map(Self.isProcessRunning) ?? false
            let status = Self.claudeStatus(rawState: rawState, processIsRunning: processIsRunning)
            let startedAt = Self.flexibleDate(item["startedAt"]) ?? now.addingTimeInterval(-120)
            guard startedAt >= now.addingTimeInterval(-86_400) || status == .working || status == .needsAttention else { return nil }
            let project = URL(fileURLWithPath: cwd).lastPathComponent
            return AgentSnapshot(
                id: id,
                sessionID: sessionID,
                agentID: item["kind"] as? String == "background" ? id : nil,
                source: .claudeCode,
                task: (item["name"] as? String)?.sanitizedSummary ?? "Claude \((item["kind"] as? String) ?? "session")",
                project: project.isEmpty ? "Local workspace" : project,
                workingDirectory: cwd,
                startedAt: startedAt,
                updatedAt: (status == .working || status == .needsAttention) ? now : startedAt,
                status: status,
                reason: status == .needsAttention ? "Aguardando input ou permissão" : (status == .unknown ? "Processo indisponível ou falhou" : nil)
            )
        }
        readiness[.claudeCode] = ProviderReadiness(
            state: .ready,
            isAvailable: true,
            detectedVersion: detectedVersions[.claudeCode],
            isConfigured: false,
            isTrusted: nil,
            lastActivity: snapshots.map(\.updatedAt).max(),
            detail: "Provider claude agents disponível."
        )
        return snapshots
    }

    static func claudeStatus(rawState: String?, processIsRunning: Bool) -> AgentStatus {
        switch rawState?.lowercased() {
        case "blocked": processIsRunning ? .needsAttention : .unknown
        case "completed", "done", "stopped", "finished": .completed
        case "running", "active": processIsRunning ? .working : .unknown
        case "failed": .unknown
        default: processIsRunning ? .working : .unknown
        }
    }

    private nonisolated static func isProcessRunning(_ identifier: Int) -> Bool {
        guard identifier > 0 else { return false }
        if kill(pid_t(identifier), 0) == 0 { return true }
        return errno == EPERM
    }

    private func detectVersions() async {
        let codex = await ProcessRunner.run("/usr/bin/env", arguments: ["codex", "--version"])
        if codex.status == 0 { detectedVersions[.codex] = codex.stdout.sanitizedSummary }
        let claude = await ProcessRunner.run("/usr/bin/env", arguments: ["claude", "--version"])
        if claude.status == 0 { detectedVersions[.claudeCode] = claude.stdout.sanitizedSummary }
    }

    func codexDatabaseCandidates() -> [URL] {
        let manager = FileManager.default
        let root = homeDirectory.appendingPathComponent(".codex", isDirectory: true)
        let primary = ((try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("state_") && $0.pathExtension == "sqlite" }
        let legacyRoot = root.appendingPathComponent("sqlite", isDirectory: true)
        let legacy = ((try? manager.contentsOfDirectory(at: legacyRoot, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("state_") && $0.pathExtension == "sqlite" }
        return sortDatabaseCandidates(primary) + sortDatabaseCandidates(legacy)
    }

    private func sortDatabaseCandidates(_ urls: [URL]) -> [URL] {
        urls.sorted { lhs, rhs in
            let leftVersion = Int(lhs.deletingPathExtension().lastPathComponent.split(separator: "_").last ?? "0") ?? 0
            let rightVersion = Int(rhs.deletingPathExtension().lastPathComponent.split(separator: "_").last ?? "0") ?? 0
            if leftVersion != rightVersion { return leftVersion > rightVersion }
            let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return leftDate > rightDate
        }
    }

    private func tailString(at url: URL, bytes: UInt64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > bytes ? size - bytes : 0)
        guard let data = try? handle.readToEnd() else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func newest(_ lhs: AgentSnapshot, _ rhs: AgentSnapshot) -> AgentSnapshot {
        lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
    }

    private static func sortSnapshots(_ lhs: AgentSnapshot, _ rhs: AgentSnapshot) -> Bool {
        if lhs.status.priority != rhs.status.priority { return lhs.status.priority < rhs.status.priority }
        return lhs.updatedAt > rhs.updatedAt
    }

    private static func date(fromEpoch value: Double) -> Date {
        Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1_000 : value)
    }

    private static func flexibleDate(_ value: Any?) -> Date? {
        if let number = value as? NSNumber { return date(fromEpoch: number.doubleValue) }
        guard let text = value as? String else { return nil }
        return ISO8601DateFormatter().date(from: text) ?? Double(text).map(date(fromEpoch:))
    }
}

private struct CodexThreadRow: Decodable {
    let id: String
    let cwd: String
    let updatedAt: Double
    let rolloutPath: String

    enum CodingKeys: String, CodingKey {
        case id, cwd
        case updatedAt = "updated_at"
        case rolloutPath = "rollout_path"
    }
}
