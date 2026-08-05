import AppKit
import CryptoKit
import Foundation

enum AppPaths {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("NeonNotch", isDirectory: true)
    }

    static var eventLog: URL { supportDirectory.appendingPathComponent("agent-events.jsonl") }
    static var agentSnapshots: URL { supportDirectory.appendingPathComponent("agent-snapshots.json") }
    static var agentEventReceipts: URL { supportDirectory.appendingPathComponent("agent-event-receipts.json") }
    static var clipboardStore: URL { supportDirectory.appendingPathComponent("clipboard.json") }
    static var helperDirectory: URL { supportDirectory.appendingPathComponent("bin", isDirectory: true) }
    static var helperURL: URL { helperDirectory.appendingPathComponent("NeonNotchHook") }
    static var artworkCache: URL { supportDirectory.appendingPathComponent("artwork-cache", isDirectory: true) }

    static func prepare() throws {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: helperDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: artworkCache, withIntermediateDirectories: true)
    }
}

struct ProcessResult: Sendable {
    let stdout: String
    let stderr: String
    let status: Int32
}

enum ProcessRunner {
    static func run(_ executable: String, arguments: [String]) async -> ProcessResult {
        await Task.detached(priority: .utility) {
            let process = Process()
            let out = Pipe()
            let error = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = out
            process.standardError = error
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = [
                "/opt/homebrew/bin",
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path,
                "/usr/local/bin",
                "/usr/bin",
                "/bin"
            ].joined(separator: ":")
            process.environment = environment
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return ProcessResult(stdout: "", stderr: error.localizedDescription, status: -1)
            }
            let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return ProcessResult(stdout: stdout, stderr: stderr, status: process.terminationStatus)
        }.value
    }
}

enum Formatters {
    static func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0 ? String(format: "%dh %02dm", hours, minutes) : String(format: "%02dm %02ds", minutes, seconds)
    }

    static func bytes(_ value: UInt64, perSecond: Bool = false) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .memory
        let formatted = formatter.string(fromByteCount: Int64(value))
        return perSecond ? "\(formatted)/s" : formatted
    }

    static func compactPercent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }
}

extension String {
    var sanitizedSummary: String {
        let redacted = replacingOccurrences(
            of: #"(?i)(sk-[a-z0-9_-]{12,}|bearer\s+[a-z0-9._-]+|api[_-]?key\s*[:=]\s*\S+)"#,
            with: "[redacted]",
            options: .regularExpression
        )
        let collapsed = redacted.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return String(collapsed.prefix(240))
    }

    var contentHash: String {
        SHA256.hash(data: Data(utf8)).map { String(format: "%02x", $0) }.joined()
    }

    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
