import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            Form {
                Section("Inicialização") {
                    Toggle("Abrir silenciosamente ao iniciar sessão", isOn: Binding(
                        get: { model.launchAtLogin.isEnabled },
                        set: { model.setLaunchAtLogin($0) }
                    ))
                    Toggle("Reduzir pulsos e animações", isOn: $model.reducedMotion)
                }

                Section("Alertas") {
                    Toggle("Notificação quando um agente precisa de atenção", isOn: $model.agentNotificationsEnabled)
                    Toggle("Som dos alertas", isOn: $model.alertSoundsEnabled)
                }

                Section("Privacidade") {
                    Text("Prompts, respostas, comandos e parâmetros de ferramentas nunca são persistidos. O histórico fica somente neste Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Bundle IDs ignorados no clipboard", text: Binding(
                        get: { model.clipboardService.excludedBundleIDs.joined(separator: ", ") },
                        set: { value in
                            model.clipboardService.excludedBundleIDs = value
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                        }
                    ))
                }
            }
            .padding(20)
            .tabItem { Label("Geral", systemImage: "gearshape") }

            Form {
                integrationRow(
                    title: "Codex",
                    symbol: "terminal",
                    health: model.integrations.codexHealth
                )
                integrationRow(
                    title: "Claude Code",
                    symbol: "chevron.left.forwardslash.chevron.right",
                    health: model.integrations.claudeHealth
                )

                HStack {
                    Button("Instalar / reparar") { model.installIntegrations() }
                        .buttonStyle(.borderedProminent)
                        .tint(NeonTheme.cyan)
                    Button("Remover", role: .destructive) { model.removeIntegrations() }
                    Spacer()
                    if model.integrations.isWorking {
                        ProgressView().controlSize(.small)
                    }
                }

                if let message = model.integrations.lastMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .tabItem { Label("Integrações", systemImage: "point.3.connected.trianglepath.dotted") }

            Form {
                LabeledContent("Versão", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "com.cammis.NeonNotch")
                Text("Feito para uso pessoal. Sem analytics, telemetria remota ou sincronização em nuvem.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .tabItem { Label("Sobre", systemImage: "info.circle") }
        }
        .frame(width: 620, height: 390)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func integrationRow(title: String, symbol: String, health: IntegrationHealth) -> some View {
        LabeledContent {
            Text(health.title)
                .foregroundStyle(health.color)
        } label: {
            Label(title, systemImage: symbol)
        }
    }
}

private extension IntegrationHealth {
    var title: String {
        switch self {
        case .notInstalled: "Não instalada"
        case .installed: "Ativa"
        case .needsRepair: "Requer reparo"
        }
    }

    var color: Color {
        switch self {
        case .notInstalled: NeonTheme.muted
        case .installed: NeonTheme.green
        case .needsRepair: NeonTheme.magenta
        }
    }
}
