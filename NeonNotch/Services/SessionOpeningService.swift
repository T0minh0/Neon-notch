import AppKit
import Foundation

enum SessionOpeningService {
    @MainActor
    static func open(_ snapshot: AgentSnapshot) {
        switch snapshot.source {
        case .codex:
            guard let url = URL(string: "codex://threads/\(snapshot.sessionID)") else { return }
            NSWorkspace.shared.open(url)
        case .claudeCode:
            openClaude(snapshot)
        }
    }

    @MainActor
    private static func openClaude(_ snapshot: AgentSnapshot) {
        let directory = snapshot.workingDirectory.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser.path
            : snapshot.workingDirectory
        let command = "cd \(directory.shellQuoted) && claude --resume \(snapshot.sessionID.shellQuoted)"
        let source = """
        tell application "Terminal"
            activate
            do script \(appleScriptLiteral(command))
        end tell
        """
        var error: NSDictionary?
        if NSAppleScript(source: source)?.executeAndReturnError(&error) == nil || error != nil {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            NSWorkspace.shared.open(URL(fileURLWithPath: directory))
        }
    }

    private static func appleScriptLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}

