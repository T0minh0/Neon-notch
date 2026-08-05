import AppKit
import Foundation

@MainActor
final class AgentMonitorService: AgentProvider {
    private var eventOffset: UInt64 = 0
    private var eventRemainder = Data()

    func snapshots() async -> [AgentSnapshot] {
        async let codex = codexSnapshots()
        async let claude = claudeSnapshots()
        return await (codex + claude)
            .filter { $0.updatedAt > Date().addingTimeInterval(-86_400) || $0.status != .completed }
            .sorted(by: AgentMonitorService.sortSnapshots)
    }

    func readNewHookEvents() -> [AgentHookEvent] {
        guard FileManager.default.fileExists(atPath: AppPaths.eventLog.path),
              let handle = try? FileHandle(forReadingFrom: AppPaths.eventLog) else { return [] }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        if eventOffset > size {
            eventOffset = 0
            eventRemainder = Data()
        }
        try? handle.seek(toOffset: eventOffset)
        let incoming = (try? handle.readToEnd()) ?? Data()
        eventOffset = size
        guard !incoming.isEmpty else { return [] }

        var buffer = eventRemainder
        buffer.append(incoming)
        var lines = buffer.split(separator: 0x0A, omittingEmptySubsequences: false)
        if buffer.last != 0x0A {
            eventRemainder = Data(lines.removeLast())
        } else {
            eventRemainder = Data()
            if lines.last?.isEmpty == true { lines.removeLast() }
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return lines.compactMap { try? decoder.decode(AgentHookEvent.self, from: Data($0)) }
    }

    func snapshot(from event: AgentHookEvent, previous: AgentSnapshot?) -> AgentSnapshot {
        let status = Self.status(for: event.event)
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

    private func codexSnapshots() async -> [AgentSnapshot] {
        let database = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sqlite/state_5.sqlite")
        guard FileManager.default.fileExists(atPath: database.path) else { return [] }
        let query = """
        SELECT id, title, cwd, updated_at, rollout_path
        FROM threads
        WHERE archived = 0
        ORDER BY updated_at DESC
        LIMIT 12;
        """
        let result = await ProcessRunner.run("/usr/bin/sqlite3", arguments: ["-json", database.path, query])
        guard result.status == 0, let data = result.stdout.data(using: .utf8) else { return [] }
        let rows = (try? JSONDecoder().decode([CodexThreadRow].self, from: data)) ?? []
        let now = Date()
        return rows.compactMap { row in
            let updated = Self.date(fromEpoch: row.updatedAt)
            guard now.timeIntervalSince(updated) < 86_400 else { return nil }
            let status = inferCodexStatus(rolloutPath: row.rolloutPath, updatedAt: updated)
            return AgentSnapshot(
                id: row.id,
                sessionID: row.id,
                source: .codex,
                task: row.title.sanitizedSummary.isEmpty ? "Untitled Codex task" : row.title.sanitizedSummary,
                project: URL(fileURLWithPath: row.cwd).lastPathComponent,
                workingDirectory: row.cwd,
                startedAt: updated.addingTimeInterval(-min(2_400, max(60, now.timeIntervalSince(updated)))),
                updatedAt: updated,
                status: status,
                reason: status == .needsAttention ? "Waiting for your response" : nil
            )
        }
    }

    private func inferCodexStatus(rolloutPath: String, updatedAt: Date) -> AgentStatus {
        let age = Date().timeIntervalSince(updatedAt)
        guard age < 600 else { return .completed }
        guard let tail = tailString(at: URL(fileURLWithPath: rolloutPath), bytes: 131_072) else {
            return age < 180 ? .working : .completed
        }
        let requestCount = tail.components(separatedBy: "\"name\":\"request_user_input\"").count - 1
        let outputCount = tail.components(separatedBy: "\"type\":\"custom_tool_call_output\"").count - 1
        if requestCount > outputCount { return .needsAttention }
        if tail.contains("\"phase\":\"final_answer\"") { return .completed }
        return age < 180 ? .working : .completed
    }

    private func claudeSnapshots() async -> [AgentSnapshot] {
        let result = await ProcessRunner.run("/usr/bin/env", arguments: ["claude", "agents", "--json", "--all"])
        guard result.status == 0,
              let data = result.stdout.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let now = Date()
        return array.prefix(20).compactMap { item in
            guard let sessionID = (item["sessionId"] as? String) ?? (item["id"] as? String) else { return nil }
            let id = (item["id"] as? String) ?? sessionID
            let cwd = item["cwd"] as? String ?? ""
            let rawState = item["state"] as? String
            let status: AgentStatus = switch rawState {
            case "blocked": .needsAttention
            case "completed", "done", "stopped": .completed
            case "running", "active": .working
            default: item["pid"] == nil ? .completed : .working
            }
            let startedAt = Self.flexibleDate(item["startedAt"]) ?? now.addingTimeInterval(-120)
            guard now.timeIntervalSince(startedAt) < 86_400 || status != .completed else { return nil }
            return AgentSnapshot(
                id: id,
                sessionID: sessionID,
                agentID: item["kind"] as? String == "background" ? id : nil,
                source: .claudeCode,
                task: (item["name"] as? String)?.sanitizedSummary ?? "Claude \((item["kind"] as? String) ?? "session")",
                project: URL(fileURLWithPath: cwd).lastPathComponent.isEmpty ? "Local workspace" : URL(fileURLWithPath: cwd).lastPathComponent,
                workingDirectory: cwd,
                startedAt: startedAt,
                updatedAt: now,
                status: status,
                reason: status == .needsAttention ? "Waiting for input or permission" : nil
            )
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

    private static func status(for event: String) -> AgentStatus {
        switch event.lowercased() {
        case "permissionrequest", "notification", "inputneeded", "approval-requested": .needsAttention
        case "stop", "subagentstop", "sessionend", "agent-turn-complete": .completed
        case "sessionstart", "subagentstart", "userpromptsubmit", "task_started": .working
        default: .unknown
        }
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
    let title: String
    let cwd: String
    let updatedAt: Double
    let rolloutPath: String

    enum CodingKeys: String, CodingKey {
        case id, title, cwd
        case updatedAt = "updated_at"
        case rolloutPath = "rollout_path"
    }
}
