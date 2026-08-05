import AppKit
import Combine
import Foundation
import UserNotifications

enum PermissionDiagnosticKind: String, CaseIterable, Identifiable, Sendable {
    case installation
    case helper
    case codex
    case claudeCode
    case notifications
    case spotifyAutomation
    case terminalAutomation
    case launchAtLogin

    var id: String { rawValue }
}

struct PermissionDiagnostic: Identifiable, Equatable, Sendable {
    let kind: PermissionDiagnosticKind
    var state: ProviderReadinessState
    var title: String
    var detail: String

    var id: PermissionDiagnosticKind { kind }
}

@MainActor
final class PermissionDiagnosticsService: ObservableObject {
    @Published private(set) var diagnostics: [PermissionDiagnostic] = []

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func refresh(
        integrations: HookIntegrationManager,
        providerReadiness: [AgentSource: ProviderReadiness],
        launchAtLogin: LaunchAtLoginService
    ) async {
        let installedPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Neon Notch.app").standardizedFileURL
        let isInstalled = Bundle.main.bundleURL.standardizedFileURL == installedPath
        let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()

        var next: [PermissionDiagnostic] = [
            PermissionDiagnostic(
                kind: .installation,
                state: isInstalled ? .ready : .setupRequired,
                title: "Instalação",
                detail: isInstalled ? "Executando de ~/Applications." : "Instale a versão Release em ~/Applications."
            ),
            PermissionDiagnostic(
                kind: .helper,
                state: FileManager.default.isExecutableFile(atPath: AppPaths.helperURL.path) ? .ready : .setupRequired,
                title: "Helper local",
                detail: FileManager.default.isExecutableFile(atPath: AppPaths.helperURL.path) ? "Helper v2 instalado." : "Instale ou repare as integrações."
            ),
            diagnostic(for: .codex, title: "Codex", integration: integrations.codexReadiness, provider: providerReadiness[.codex]),
            diagnostic(for: .claudeCode, title: "Claude Code", integration: integrations.claudeReadiness, provider: providerReadiness[.claudeCode]),
            PermissionDiagnostic(
                kind: .notifications,
                state: notificationState(notificationSettings.authorizationStatus),
                title: "Notificações",
                detail: notificationDetail(notificationSettings.authorizationStatus)
            ),
            automationDiagnostic(kind: .spotifyAutomation, title: "Automação do Spotify"),
            automationDiagnostic(kind: .terminalAutomation, title: "Automação do Terminal"),
            PermissionDiagnostic(
                kind: .launchAtLogin,
                state: launchAtLogin.isEnabled ? .ready : .setupRequired,
                title: "Início no login",
                detail: launchAtLogin.isEnabled ? "Ativo." : "Desativado."
            )
        ]
        next.sort { $0.kind.sortIndex < $1.kind.sortIndex }
        diagnostics = next
    }

    @discardableResult
    func requestNotifications() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge])
        } catch {
            return false
        }
    }

    @discardableResult
    func testAutomation(_ kind: PermissionDiagnosticKind) async -> Bool {
        let source: String
        switch kind {
        case .spotifyAutomation:
            source = "tell application \"Spotify\" to get player state"
        case .terminalAutomation:
            source = "tell application \"Terminal\" to get name"
        default:
            return false
        }
        let result = await ProcessRunner.run("/usr/bin/osascript", arguments: ["-e", source])
        let succeeded = result.status == 0
        defaults.set(succeeded ? "ready" : "degraded", forKey: "diagnostic.\(kind.rawValue)")
        defaults.set(result.stderr.sanitizedSummary, forKey: "diagnostic.\(kind.rawValue).detail")
        return succeeded
    }

    func openSystemSettings(for kind: PermissionDiagnosticKind) {
        let destination: String = switch kind {
        case .notifications: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        case .spotifyAutomation, .terminalAutomation: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        case .launchAtLogin: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        default: "x-apple.systempreferences:"
        }
        if let url = URL(string: destination) { NSWorkspace.shared.open(url) }
    }

    func copyRecoveryInstructions(for kind: PermissionDiagnosticKind) {
        let text: String = switch kind {
        case .installation: "Execute ./script/setup_local_signing.sh e depois ./script/build_and_install.sh."
        case .helper: "Abra Neon Notch > Ajustes > Integrações e clique em Instalar / reparar."
        case .codex: "No Codex, execute /hooks, revise NeonNotchHook e confirme a confiança explicitamente."
        case .claudeCode: "Repare a integração e inicie uma nova sessão do Claude Code."
        case .notifications: "Ajustes do Sistema > Notificações > Neon Notch."
        case .spotifyAutomation: "Ajustes do Sistema > Privacidade e Segurança > Automação > Neon Notch > Spotify."
        case .terminalAutomation: "Ajustes do Sistema > Privacidade e Segurança > Automação > Neon Notch > Terminal."
        case .launchAtLogin: "Ative Abrir silenciosamente ao iniciar sessão nos Ajustes do Neon Notch."
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func diagnostic(
        for kind: PermissionDiagnosticKind,
        title: String,
        integration: ProviderReadiness,
        provider: ProviderReadiness?
    ) -> PermissionDiagnostic {
        var combined = integration
        if let provider {
            combined.isAvailable = provider.isAvailable
            combined.detectedVersion = provider.detectedVersion
            combined.lastActivity = [integration.lastActivity, provider.lastActivity].compactMap { $0 }.max()
            if combined.state == .ready, !provider.isAvailable { combined.state = .degraded }
        }
        let version = combined.detectedVersion.map { " · \($0)" } ?? ""
        return PermissionDiagnostic(kind: kind, state: combined.state, title: title, detail: combined.detail + version)
    }

    private func automationDiagnostic(kind: PermissionDiagnosticKind, title: String) -> PermissionDiagnostic {
        let saved = defaults.string(forKey: "diagnostic.\(kind.rawValue)")
        let state = saved.flatMap(ProviderReadinessState.init(rawValue:)) ?? .setupRequired
        let detail = defaults.string(forKey: "diagnostic.\(kind.rawValue).detail")
        return PermissionDiagnostic(
            kind: kind,
            state: state,
            title: title,
            detail: state == .ready ? "Teste concluído com sucesso." : (detail?.isEmpty == false ? detail! : "Execute o teste para confirmar a permissão.")
        )
    }

    private func notificationState(_ status: UNAuthorizationStatus) -> ProviderReadinessState {
        switch status {
        case .authorized, .provisional, .ephemeral: .ready
        case .denied: .degraded
        case .notDetermined: .setupRequired
        @unknown default: .unavailable
        }
    }

    private func notificationDetail(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized, .provisional, .ephemeral: "Alertas autorizados."
        case .denied: "Notificações foram negadas nos Ajustes do Sistema."
        case .notDetermined: "Permissão ainda não solicitada."
        @unknown default: "Estado de permissão desconhecido."
        }
    }
}

private extension PermissionDiagnosticKind {
    var sortIndex: Int {
        switch self {
        case .installation: 0
        case .helper: 1
        case .codex: 2
        case .claudeCode: 3
        case .notifications: 4
        case .spotifyAutomation: 5
        case .terminalAutomation: 6
        case .launchAtLogin: 7
        }
    }
}
