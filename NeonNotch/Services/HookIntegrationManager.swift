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
    @Published private(set) var codexReadiness = ProviderReadiness.unavailable("Codex não detectado.")
    @Published private(set) var claudeReadiness = ProviderReadiness.unavailable("Claude Code não detectado.")

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
        let activities = lastActivitiesBySource()
        codexHealth = integrationHealth(helperExists: helperExists, configured: codexConfigured)
        claudeHealth = integrationHealth(helperExists: helperExists, configured: claudeConfigured)
        health = codexHealth == .installed && claudeHealth == .installed
            ? .installed
            : (codexConfigured || claudeConfigured
                ? .needsRepair("One or more integration files are incomplete")
                : .notInstalled)
        codexReadiness = readiness(
            source: .codex,
            available: FileManager.default.fileExists(atPath: homeDirectory.appendingPathComponent(".codex").path),
            helperExists: helperExists,
            configured: codexConfigured,
            lastActivity: activities[.codex],
            requiresTrust: true
        )
        claudeReadiness = readiness(
            source: .claudeCode,
            available: FileManager.default.fileExists(atPath: homeDirectory.appendingPathComponent(".claude").path),
            helperExists: helperExists,
            configured: claudeConfigured,
            lastActivity: activities[.claudeCode],
            requiresTrust: false
        )
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

    func installHelperOnly() throws {
        isWorking = true
        defer { isWorking = false }
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: helperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try installHelper()
        refreshHealth()
        lastMessage = "Helper v2 instalado. Configure Codex e Claude Code na próxima etapa."
    }

    func installOrRepair(_ source: AgentSource) throws {
        isWorking = true
        defer { isWorking = false }
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: helperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.isExecutableFile(atPath: helperURL.path) { try installHelper() }
        switch source {
        case .codex:
            try mergeHooks(at: codexHooksURL, events: codexEvents, source: "codex")
        case .claudeCode:
            try mergeHooks(at: claudeSettingsURL, events: claudeEvents, source: "claudeCode")
        }
        refreshHealth()
        lastMessage = "Integração do \(source.title) instalada. Reinicie sessões abertas para ativar os hooks."
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

    func testHelper() async -> Bool {
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            lastMessage = "O helper ainda não está instalado."
            return false
        }
        isWorking = true
        defer { isWorking = false }
        let result = await ProcessRunner.run(helperURL.path, arguments: ["--self-test"])
        if result.status == 0, result.stdout.contains("schema=2") {
            lastMessage = "Helper v2 respondeu corretamente."
            return true
        }
        lastMessage = result.stderr.sanitizedSummary.isEmpty
            ? "O helper não respondeu ao autoteste."
            : result.stderr.sanitizedSummary
        return false
    }

    private func integrationHealth(helperExists: Bool, configured: Bool) -> IntegrationHealth {
        if helperExists && configured { return .installed }
        if configured { return .needsRepair("Helper ausente") }
        return .notInstalled
    }

    private func readiness(
        source: AgentSource,
        available: Bool,
        helperExists: Bool,
        configured: Bool,
        lastActivity: Date?,
        requiresTrust: Bool
    ) -> ProviderReadiness {
        let state: ProviderReadinessState
        let detail: String
        if !available {
            state = .unavailable
            detail = "\(source.title) não foi detectado neste Mac."
        } else if !configured {
            state = .setupRequired
            detail = helperExists ? "Configure os hooks deste provider." : "Instale o helper e configure os hooks."
        } else if !helperExists {
            state = .degraded
            detail = "A integração está incompleta e precisa de reparo."
        } else if requiresTrust && lastActivity == nil {
            state = .awaitingTrust
            detail = "Revise e aprove o hook pelo comando /hooks no Codex."
        } else {
            state = .ready
            detail = lastActivity == nil ? "Integração configurada; aguardando a primeira sessão." : "Eventos recebidos normalmente."
        }
        return ProviderReadiness(
            state: state,
            isAvailable: available,
            detectedVersion: nil,
            isConfigured: configured,
            isTrusted: requiresTrust ? lastActivity != nil : nil,
            lastActivity: lastActivity,
            detail: detail
        )
    }

    private func lastActivitiesBySource() -> [AgentSource: Date] {
        let eventLog = supportDirectory.appendingPathComponent("agent-events.jsonl")
        guard let data = try? Data(contentsOf: eventLog) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var activities: [AgentSource: Date] = [:]
        for line in data.split(separator: 0x0A).suffix(1_000) {
            guard let event = try? decoder.decode(AgentHookEvent.self, from: Data(line)) else { continue }
            if event.timestamp > (activities[event.source] ?? .distantPast) {
                activities[event.source] = event.timestamp
            }
        }
        return activities
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
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) else { return false }
        return containsHelper(in: object)
    }

    private func containsHelper(in value: Any) -> Bool {
        if let text = value as? String { return text.contains(helperURL.path) }
        if let array = value as? [Any] { return array.contains(where: containsHelper) }
        if let dictionary = value as? [String: Any] {
            return dictionary.values.contains(where: containsHelper)
        }
        return false
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
