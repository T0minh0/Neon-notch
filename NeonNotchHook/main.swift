import Darwin
import Foundation

private struct EventEnvelope: Codable {
    let schemaVersion: Int
    let source: String
    let event: String
    let sessionID: String
    let agentID: String?
    let parentAgentID: String?
    let workingDirectory: String
    let timestamp: Date
    let summary: String
}

private let arguments = CommandLine.arguments
private let source = arguments.dropFirst().first == "claudeCode" ? "claudeCode" : "codex"

private func readPayload() -> [String: Any] {
    var data = FileHandle.standardInput.readDataToEndOfFile()
    if data.isEmpty,
       let inline = arguments.dropFirst(2).first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("{") }) {
        data = Data(inline.utf8)
    }
    guard !data.isEmpty,
          let value = try? JSONSerialization.jsonObject(with: data),
          let object = value as? [String: Any] else {
        return [:]
    }
    return object
}

private func firstString(_ keys: [String], in object: [String: Any]) -> String? {
    for key in keys {
        if let value = object[key] as? String, !value.isEmpty { return value }
    }
    return nil
}

private func sanitize(_ value: String) -> String {
    value
        .replacingOccurrences(of: #"(?i)(sk-[a-z0-9_-]{12,}|bearer\s+[a-z0-9._-]+|api[_-]?key\s*[:=]\s*\S+)"#,
                              with: "[redacted]",
                              options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .prefix(180)
        .description
}

private func eventSummary(event: String, payload: [String: Any]) -> String {
    let normalized = event.lowercased()
    if normalized.contains("permission") || normalized.contains("approval") {
        let tool = firstString(["tool_name", "toolName"], in: payload) ?? "ação"
        return "Aprovação necessária para \(tool)"
    }
    if normalized.contains("subagentstart") || normalized.contains("subagent_start") {
        return sanitize(firstString(["agent_type", "agentType", "name"], in: payload) ?? "Subagente iniciado")
    }
    if normalized.contains("subagentstop") || normalized.contains("subagent_stop") {
        return "Subagente concluiu o trabalho"
    }
    if normalized == "stop" || normalized.contains("sessionend") || normalized.contains("session_end") {
        return "Trabalho concluído"
    }
    if normalized.contains("notification") || normalized.contains("input") {
        return sanitize(firstString(["title", "message", "reason"], in: payload) ?? "Interação necessária")
    }
    if normalized.contains("prompt") {
        return "Nova tarefa em andamento"
    }
    return sanitize(firstString(["summary", "title", "reason"], in: payload) ?? event)
}

private func append(_ event: EventEnvelope) {
    let root = ProcessInfo.processInfo.environment["NEON_NOTCH_SUPPORT_DIR"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
    } ?? FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/NeonNotch", isDirectory: true)
    let file = root.appendingPathComponent("agent-events.jsonl")

    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    if !FileManager.default.fileExists(atPath: file.path) {
        FileManager.default.createFile(atPath: file.path, contents: nil)
    }

    guard let handle = try? FileHandle(forWritingTo: file) else { return }
    defer { try? handle.close() }

    flock(handle.fileDescriptor, LOCK_EX)
    defer { flock(handle.fileDescriptor, LOCK_UN) }

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    guard var data = try? encoder.encode(event) else { return }
    data.append(0x0A)
    _ = try? handle.seekToEnd()
    try? handle.write(contentsOf: data)
}

let payload = readPayload()
let eventName = firstString(["hook_event_name", "event", "event_name", "type"], in: payload) ?? "unknown"
let sessionID = firstString(["session_id", "sessionId", "thread_id", "threadId"], in: payload) ?? UUID().uuidString
let agentID = firstString(["agent_id", "agentId", "subagent_id", "subagentId"], in: payload)
let parentAgentID = firstString(["parent_agent_id", "parentAgentId"], in: payload)
let directory = firstString(["cwd", "working_directory", "workingDirectory"], in: payload)
    ?? FileManager.default.currentDirectoryPath

append(EventEnvelope(
    schemaVersion: 1,
    source: source,
    event: eventName,
    sessionID: sessionID,
    agentID: agentID,
    parentAgentID: parentAgentID,
    workingDirectory: directory,
    timestamp: Date(),
    summary: eventSummary(event: eventName, payload: payload)
))
