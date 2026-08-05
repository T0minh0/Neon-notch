import Combine
import Foundation

enum IntegrationHealth: Equatable {
    case notInstalled
    case installed
    case needsRepair(String)
}

@MainActor
final class HookIntegrationManager: ObservableObject {
    @Published private(set) var health: IntegrationHealth = .notInstalled
    @Published private(set) var codexHealth: IntegrationHealth = .notInstalled
    @Published private(set) var claudeHealth: IntegrationHealth = .notInstalled
    @Published private(set) var isWorking = false
    @Published private(set) var lastMessage: String?

    private let codexEvents = ["SessionStart", "UserPromptSubmit", "PermissionRequest", "SubagentStart", "SubagentStop", "Stop", "SessionEnd"]
    private let claudeEvents = ["SessionStart", "UserPromptSubmit", "PermissionRequest", "Notification", "SubagentStart", "SubagentStop", "Stop", "SessionEnd"]
    private let homeDirectory: URL
    private let supportDirectory: URL
    private let helperURL: URL
    private let bundledHelperURL: URL?

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        supportDirectory: URL = AppPaths.supportDirectory,
        helperURL: URL = AppPaths.helperURL,
        bundledHelperURL: URL? = nil
    ) {
        self.homeDirectory = homeDirectory
        self.supportDirectory = supportDirectory
        self.helperURL = helperURL
        self.bundledHelperURL = bundledHelperURL
    }

    func refreshHealth() {
        let helperExists = FileManager.default.isExecutableFile(atPath: helperURL.path)
        let codexConfigured = configurationContainsHelper(at: codexHooksURL)
        let claudeConfigured = configurationContainsHelper(at: claudeSettingsURL)
        codexHealth = integrationHealth(helperExists: helperExists, configured: codexConfigured)
        claudeHealth = integrationHealth(helperExists: helperExists, configured: claudeConfigured)
        health = codexHealth == .installed && claudeHealth == .installed
            ? .installed
            : (helperExists || codexConfigured || claudeConfigured
                ? .needsRepair("One or more integration files are incomplete")
                : .notInstalled)
    }

    func installOrRepair() throws {
        isWorking = true
        defer { isWorking = false }
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: helperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try installHelper()
        try mergeHooks(at: codexHooksURL, events: codexEvents, source: "codex")
        try mergeHooks(at: claudeSettingsURL, events: claudeEvents, source: "claudeCode")
        refreshHealth()
        lastMessage = "Integrações instaladas. Reinicie sessões abertas para ativar os hooks."
    }

    func remove() throws {
        isWorking = true
        defer { isWorking = false }
        try removeHooks(at: codexHooksURL)
        try removeHooks(at: claudeSettingsURL)
        try? FileManager.default.removeItem(at: helperURL)
        refreshHealth()
        lastMessage = "Integrações removidas; os backups foram preservados."
    }

    private func integrationHealth(helperExists: Bool, configured: Bool) -> IntegrationHealth {
        if helperExists && configured { return .installed }
        if helperExists || configured { return .needsRepair("Configuração incompleta") }
        return .notInstalled
    }

    private var codexHooksURL: URL {
        homeDirectory.appendingPathComponent(".codex/hooks.json")
    }

    private var claudeSettingsURL: URL {
        homeDirectory.appendingPathComponent(".claude/settings.json")
    }

    private func installHelper() throws {
        let candidates = [bundledHelperURL].compactMap { $0 } + [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/NeonNotchHook"),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("NeonNotchHook")
        ]
        guard let bundled = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw IntegrationError.helperMissing
        }
        if FileManager.default.fileExists(atPath: helperURL.path) {
            try FileManager.default.removeItem(at: helperURL)
        }
        try FileManager.default.copyItem(at: bundled, to: helperURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperURL.path)
    }

    private func mergeHooks(at url: URL, events: [String], source: String) throws {
        try backup(url)
        var root = try readJSONObject(at: url)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let command = "\(helperURL.path.shellQuoted) \(source)"
        for event in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            let alreadyPresent = groups.contains { group in
                (group["hooks"] as? [[String: Any]])?.contains { ($0["command"] as? String)?.contains(helperURL.path) == true } == true
            }
            if !alreadyPresent {
                groups.append([
                    "hooks": [["type": "command", "command": command, "timeout": 1]]
                ])
            }
            hooks[event] = groups
        }
        root["hooks"] = hooks
        try writeJSONObject(root, to: url)
    }

    private func removeHooks(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try backup(url)
        var root = try readJSONObject(at: url)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for key in Array(hooks.keys) {
            guard var groups = hooks[key] as? [[String: Any]] else { continue }
            groups = groups.compactMap { group in
                var updated = group
                let handlers = (group["hooks"] as? [[String: Any]] ?? []).filter {
                    ($0["command"] as? String)?.contains(helperURL.path) != true
                }
                guard !handlers.isEmpty else { return nil }
                updated["hooks"] = handlers
                return updated
            }
            if groups.isEmpty { hooks.removeValue(forKey: key) } else { hooks[key] = groups }
        }
        root["hooks"] = hooks
        try writeJSONObject(root, to: url)
    }

    private func configurationContainsHelper(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return false }
        return text.contains(helperURL.path)
    }

    private func backup(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let backups = supportDirectory.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let destination = backups.appendingPathComponent("\(url.lastPathComponent).\(stamp).\(UUID().uuidString.prefix(8)).backup")
        try FileManager.default.copyItem(at: url, to: destination)
    }

    private func readJSONObject(at url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}

enum IntegrationError: LocalizedError {
    case helperMissing

    var errorDescription: String? {
        switch self {
        case .helperMissing: "NeonNotchHook is missing from the app bundle. Build through script/build_and_run.sh."
        }
    }
}
