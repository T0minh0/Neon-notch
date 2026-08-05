import AppKit
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEON NOTCH 0.2")
                        .font(.caption.monospaced().weight(.bold))
                        .tracking(2)
                        .foregroundStyle(NeonTheme.cyan)
                    Text(stepTitle).font(.title2.weight(.bold))
                    Text(stepSubtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(model.onboardingStep.rawValue + 1) / \(OnboardingStep.allCases.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(NeonTheme.muted)
            }

            ProgressView(
                value: Double(model.onboardingStep.rawValue + 1),
                total: Double(OnboardingStep.allCases.count)
            )
            .tint(NeonTheme.cyan)

            Group {
                switch model.onboardingStep {
                case .installation:
                    installationStep
                case .helper:
                    helperStep
                case .providers:
                    providersStep
                case .notifications:
                    notificationStep
                case .automation:
                    automationStep
                case .launchAtLogin:
                    launchStep
                case .summary:
                    ReadinessStatusView(model: model, showsRecoveryActions: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 300, alignment: .top)

            if let message = model.integrationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Continuar depois") { model.continueOnboardingLater() }
                Spacer()
                if model.onboardingStep != .installation {
                    Button("Voltar") { model.goBackOnboarding() }
                }
                Button(model.onboardingStep == .summary ? "Concluir" : "Continuar") {
                    if model.onboardingStep == .summary { model.completeOnboarding() }
                    else { model.advanceOnboarding() }
                }
                .buttonStyle(.borderedProminent)
                .tint(model.onboardingStep == .summary ? NeonTheme.green : NeonTheme.magenta)
            }
        }
        .padding(28)
        .frame(width: 680, height: 560)
        .background(NeonTheme.background)
        .preferredColorScheme(.dark)
        .task { model.refreshDiagnostics() }
    }

    private var installationStep: some View {
        VStack(spacing: 16) {
            onboardingFeature("Local correto", detail: "O app Release deve executar de ~/Applications para preservar sua identidade.", symbol: "internaldrive")
            diagnosticSummary(.installation)
            HStack {
                Button("Copiar comandos de instalação") {
                    model.permissionDiagnostics.copyRecoveryInstructions(for: .installation)
                }
                Spacer()
            }
        }
    }

    private var helperStep: some View {
        VStack(spacing: 16) {
            onboardingFeature("Helper sanitizado v2", detail: "Grava somente metadados permitidos em uma fila JSONL local.", symbol: "wrench.and.screwdriver")
            diagnosticSummary(.helper)
            HStack {
                Button("Instalar / reparar helper") { model.installHelper() }
                    .buttonStyle(.borderedProminent)
                    .tint(NeonTheme.cyan)
                Button("Testar helper") { model.testHelper() }
                Spacer()
            }
        }
    }

    private var providersStep: some View {
        VStack(spacing: 12) {
            diagnosticSummary(.codex)
            diagnosticSummary(.claudeCode)
            Text("No Codex, execute /hooks, revise a definição exata do NeonNotchHook e confirme a confiança. Essa aprovação nunca é automatizada.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Button("Configurar Codex") { model.installIntegration(.codex) }
                Button("Configurar Claude Code") { model.installIntegration(.claudeCode) }
                Menu("Mais") {
                    Button("Reparar ambas") { model.installIntegrations() }
                    Button("Copiar instruções do Codex") {
                        model.permissionDiagnostics.copyRecoveryInstructions(for: .codex)
                    }
                }
                Spacer()
            }
        }
    }

    private var notificationStep: some View {
        VStack(spacing: 16) {
            onboardingFeature("Alertas acionáveis", detail: "O banner abre diretamente a sessão que precisa de você.", symbol: "bell.badge")
            diagnosticSummary(.notifications)
            HStack {
                Button("Solicitar permissão") { model.requestNotifications() }
                    .buttonStyle(.borderedProminent)
                    .tint(NeonTheme.magenta)
                Button("Abrir Ajustes do Sistema") {
                    model.permissionDiagnostics.openSystemSettings(for: .notifications)
                }
                Spacer()
            }
        }
    }

    private var automationStep: some View {
        VStack(spacing: 12) {
            diagnosticSummary(.spotifyAutomation)
            HStack {
                Button("Testar Spotify") { model.testAutomation(.spotifyAutomation) }
                Button("Abrir Automação") { model.permissionDiagnostics.openSystemSettings(for: .spotifyAutomation) }
                Spacer()
            }
            diagnosticSummary(.terminalAutomation)
            HStack {
                Button("Testar Terminal") { model.testAutomation(.terminalAutomation) }
                Button("Abrir Automação") { model.permissionDiagnostics.openSystemSettings(for: .terminalAutomation) }
                Spacer()
            }
        }
    }

    private var launchStep: some View {
        VStack(spacing: 16) {
            onboardingFeature("Início silencioso", detail: "No próximo login, somente o notch é carregado.", symbol: "power")
            diagnosticSummary(.launchAtLogin)
            Toggle("Abrir silenciosamente ao iniciar sessão", isOn: Binding(
                get: { model.launchAtLogin.isEnabled },
                set: { model.setLaunchAtLogin($0) }
            ))
        }
    }

    @ViewBuilder
    private func diagnosticSummary(_ kind: PermissionDiagnosticKind) -> some View {
        if let item = model.permissionDiagnostics.diagnostics.first(where: { $0.kind == kind }) {
            ReadinessRow(item: item)
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private func onboardingFeature(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(NeonTheme.cyan)
                .frame(width: 42, height: 42)
                .background(NeonTheme.cyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .neonCard()
    }

    private var stepTitle: String {
        switch model.onboardingStep {
        case .installation: "Instalação estável"
        case .helper: "Helper local"
        case .providers: "Codex e Claude Code"
        case .notifications: "Notificações"
        case .automation: "Automação"
        case .launchAtLogin: "Início no login"
        case .summary: "Prontidão"
        }
    }

    private var stepSubtitle: String {
        switch model.onboardingStep {
        case .installation: "Confirme a origem do bundle antes de conceder permissões."
        case .helper: "Instale e valide o coletor local de eventos."
        case .providers: "Configure cada integração sem substituir hooks existentes."
        case .notifications: "Receba apenas alertas produzidos pelo Neon Notch."
        case .automation: "Teste Spotify e Terminal de forma explícita."
        case .launchAtLogin: "Carregue o notch sem abrir a central."
        case .summary: "Revise o que está pronto e o que ainda precisa de ação."
        }
    }
}

struct ReadinessStatusView: View {
    @ObservedObject var model: AppModel
    let showsRecoveryActions: Bool

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(model.permissionDiagnostics.diagnostics) { item in
                    HStack(spacing: 10) {
                        ReadinessRow(item: item)
                        if showsRecoveryActions, item.state != .ready {
                            Menu {
                                recoveryActions(for: item.kind)
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .frame(width: 28, height: 28)
                            }
                            .menuStyle(.borderlessButton)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recoveryActions(for kind: PermissionDiagnosticKind) -> some View {
        switch kind {
        case .helper, .codex, .claudeCode:
            Button("Reparar integração") { model.installIntegrations() }
            Button("Testar helper") { model.testHelper() }
        case .notifications:
            Button("Solicitar novamente") { model.requestNotifications() }
            Button("Abrir Ajustes do Sistema") { model.permissionDiagnostics.openSystemSettings(for: kind) }
        case .spotifyAutomation, .terminalAutomation:
            Button("Repetir teste") { model.testAutomation(kind) }
            Button("Abrir Ajustes do Sistema") { model.permissionDiagnostics.openSystemSettings(for: kind) }
        case .launchAtLogin:
            Button("Ativar") { model.setLaunchAtLogin(true) }
        case .installation:
            EmptyView()
        }
        Button("Copiar instruções") { model.permissionDiagnostics.copyRecoveryInstructions(for: kind) }
    }
}

struct ReadinessRow: View {
    let item: PermissionDiagnostic

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.state.symbol)
                .foregroundStyle(item.state.color)
                .frame(width: 28, height: 28)
                .background(item.state.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline.weight(.semibold))
                Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Text(item.state.label)
                .font(.caption2.monospaced().weight(.bold))
                .foregroundStyle(item.state.color)
        }
        .padding(10)
        .neonCard(color: item.state.color)
    }
}

struct ShortcutRecorderView: View {
    @ObservedObject var service: GlobalHotKeyService
    @State private var isRecording = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(service.configuration.label)
                    .font(.title3.monospaced().weight(.semibold))
                    .foregroundStyle(isRecording ? NeonTheme.magenta : NeonTheme.cyan)
                Spacer()
                Button(isRecording ? "Pressione o atalho…" : "Gravar novo atalho") {
                    isRecording = true
                }
            }
            ShortcutCaptureView(isRecording: $isRecording) { keyCode, modifiers, label in
                var candidate = service.configuration
                candidate.keyCode = keyCode
                candidate.modifiers = modifiers
                candidate.label = label
                _ = service.update(candidate)
            }
            .frame(width: 1, height: 1)

            Picker("Abrir em", selection: Binding(
                get: { service.configuration.target },
                set: { service.updateTarget($0) }
            )) {
                ForEach(GlobalShortcutTarget.allCases) { target in
                    Text(target.title).tag(target)
                }
            }

            if let error = service.registrationError {
                Text(error).font(.caption).foregroundStyle(NeonTheme.magenta)
            } else {
                Text("Command+1 abre Agentes; Command+2 abre Clipboard. Setas, Return, P, Delete e Esc funcionam no painel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCapture: (UInt32, GlobalShortcutModifiers, String) -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.onCapture = onCapture
        view.onFinish = { isRecording = false }
        return view
    }

    func updateNSView(_ view: ShortcutCaptureNSView, context: Context) {
        view.onCapture = onCapture
        view.onFinish = { isRecording = false }
        if isRecording {
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
    }
}

private final class ShortcutCaptureNSView: NSView {
    var onCapture: ((UInt32, GlobalShortcutModifiers, String) -> Void)?
    var onFinish: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        var modifiers: GlobalShortcutModifiers = []
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        let key = Self.keyLabel(event)
        let prefixes = [
            modifiers.contains(.control) ? "⌃" : "",
            modifiers.contains(.option) ? "⌥" : "",
            modifiers.contains(.shift) ? "⇧" : "",
            modifiers.contains(.command) ? "⌘" : ""
        ].joined()
        onCapture?(UInt32(event.keyCode), modifiers, prefixes + key)
        onFinish?()
    }

    private static func keyLabel(_ event: NSEvent) -> String {
        switch event.keyCode {
        case 49: "Space"
        case 36: "Return"
        case 51: "Delete"
        case 123: "←"
        case 124: "→"
        case 125: "↓"
        case 126: "↑"
        default: event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        }
    }
}

extension ProviderReadinessState {
    var label: String {
        switch self {
        case .setupRequired: "CONFIGURAR"
        case .awaitingTrust: "CONFIAR"
        case .ready: "PRONTO"
        case .degraded: "DEGRADADO"
        case .unavailable: "INDISPONÍVEL"
        }
    }

    var symbol: String {
        switch self {
        case .setupRequired: "wrench.and.screwdriver"
        case .awaitingTrust: "hand.raised"
        case .ready: "checkmark.circle.fill"
        case .degraded: "exclamationmark.triangle.fill"
        case .unavailable: "xmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .setupRequired, .unavailable: NeonTheme.muted
        case .awaitingTrust, .degraded: NeonTheme.magenta
        case .ready: NeonTheme.green
        }
    }
}
