import Charts
import SwiftUI

struct ControlCenterView: View {
    @ObservedObject var model: AppModel
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            List(ControlCenterSection.allCases, selection: $model.requestedControlCenterSection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationTitle("Neon Notch")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                if !model.onboardingCompleted {
                    Button {
                        model.resumeOnboarding()
                    } label: {
                        Label("Configuração pendente", systemImage: "exclamationmark.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(NeonTheme.magenta)
                    .padding(12)
                    .background(NeonTheme.raised)
                }
            }
        } detail: {
            Group {
                switch model.requestedControlCenterSection {
                case .agents:
                    AgentsDashboard(model: model, searchText: searchText)
                case .clipboard:
                    ClipboardDashboard(model: model, searchText: searchText)
                case .system:
                    SystemDashboard(model: model)
                }
            }
            .searchable(text: $searchText, prompt: "Buscar")
            .background(NeonTheme.background.ignoresSafeArea())
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 900, minHeight: 620)
        .sheet(isPresented: $model.showsOnboarding) {
            OnboardingView(model: model)
        }
    }
}

private struct AgentsDashboard: View {
    @ObservedObject var model: AppModel
    let searchText: String

    private var agents: [AgentSnapshot] {
        guard !searchText.isEmpty else { return model.agents }
        return model.agents.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.project.localizedCaseInsensitiveContains(searchText)
                || $0.source.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                dashboardHeader(
                    eyebrow: "COMMAND DECK",
                    title: "Agentes",
                    subtitle: "Codex e Claude Code em uma linha do tempo local."
                )

                if model.integrations.codexHealth != .installed
                    || model.integrations.claudeHealth != .installed {
                    IntegrationCallout(model: model)
                }

                HStack(spacing: 12) {
                    statusStat(.needsAttention, agents: model.agents)
                    statusStat(.working, agents: model.agents)
                    statusStat(.completed, agents: model.agents)
                }

                LazyVStack(spacing: 10) {
                    if agents.isEmpty {
                        ContentUnavailableView(
                            "Nenhum agente encontrado",
                            systemImage: "point.3.connected.trianglepath.dotted",
                            description: Text("Os eventos dos hooks aparecem aqui em tempo real.")
                        )
                        .frame(minHeight: 260)
                    } else {
                        ForEach(agents) { agent in
                            AgentDetailCard(agent: agent) {
                                model.open(agent)
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
        .navigationTitle("Agentes")
    }

    private func statusStat(_ status: AgentStatus, agents: [AgentSnapshot]) -> some View {
        let count = agents.filter { $0.status == status }.count
        return HStack(spacing: 13) {
            Image(systemName: status.symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(NeonTheme.color(for: status))
                .frame(width: 42, height: 42)
                .background(NeonTheme.color(for: status).opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count)")
                    .font(.title2.monospacedDigit().weight(.bold))
                Text(status.title)
                    .font(.caption)
                    .foregroundStyle(NeonTheme.muted)
            }
            Spacer()
        }
        .padding(15)
        .neonCard()
    }
}

private struct AgentDetailCard: View {
    let agent: AgentSnapshot
    let open: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(NeonTheme.color(for: agent.status).opacity(0.14))
                Image(systemName: agent.source.symbol)
                    .foregroundStyle(NeonTheme.color(for: agent.status))
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(agent.title).font(.headline)
                    Text(agent.source.title.uppercased())
                        .font(.caption2.monospaced().weight(.bold))
                        .foregroundStyle(NeonTheme.cyan)
                }
                Text(agent.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 12) {
                    Label(agent.project, systemImage: "folder")
                    Label(Formatters.duration(agent.duration), systemImage: "clock")
                    Text(agent.updatedAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(NeonTheme.muted)
            }

            Spacer(minLength: 20)

            Text(agent.status.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NeonTheme.color(for: agent.status))

            Button("Abrir sessão", systemImage: "arrow.up.right.square", action: open)
                .buttonStyle(.bordered)
                .tint(NeonTheme.cyan)
        }
        .padding(16)
        .neonCard(color: NeonTheme.color(for: agent.status))
    }
}

private struct IntegrationCallout: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "link.badge.plus")
                .font(.title2)
                .foregroundStyle(NeonTheme.magenta)
            VStack(alignment: .leading, spacing: 3) {
                Text("Conecte seus agentes")
                    .font(.headline)
                Text("O helper salva somente metadados sanitizados no seu Mac.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Instalar integrações") {
                model.installIntegrations()
            }
            .buttonStyle(.borderedProminent)
            .tint(NeonTheme.magenta)
        }
        .padding(18)
        .neonCard(color: NeonTheme.magenta)
    }
}

private struct ClipboardDashboard: View {
    @ObservedObject var model: AppModel
    let searchText: String

    private var entries: [ClipboardEntry] {
        model.clipboardService.filteredEntries(searchText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .bottom) {
                dashboardHeader(
                    eyebrow: "LOCAL MEMORY",
                    title: "Clipboard",
                    subtitle: "100 itens recentes, com exclusões de privacidade."
                )
                Spacer()
                Button("Limpar", systemImage: "trash") {
                    model.clipboardService.clear()
                }
                .disabled(entries.isEmpty)
            }

            List(entries) { entry in
                ClipboardRow(entry: entry, service: model.clipboardService)
                    .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "Clipboard vazio",
                        systemImage: "clipboard",
                        description: Text("Texto, URLs, imagens e arquivos copiados aparecerão aqui.")
                    )
                }
            }
        }
        .padding(28)
        .navigationTitle("Clipboard")
    }
}

private struct ClipboardRow: View {
    let entry: ClipboardEntry
    @ObservedObject var service: ClipboardService

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: entry.kind.symbol)
                .foregroundStyle(entry.isPinned ? NeonTheme.magenta : NeonTheme.cyan)
                .frame(width: 38, height: 38)
                .background(NeonTheme.raised, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.preview)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(entry.sourceName)
                    Text("•")
                    Text(entry.createdAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(NeonTheme.muted)
            }
            Spacer()
            Button {
                service.togglePinned(entry.id)
            } label: {
                Image(systemName: entry.isPinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.plain)
            Button {
                service.copy(entry)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            Button(role: .destructive) {
                service.delete(entry.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }
}

private struct SystemDashboard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                dashboardHeader(
                    eyebrow: "SYSTEM PULSE",
                    title: "Sistema",
                    subtitle: "Histórico local dos últimos 60 pontos."
                )

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    metricCard("CPU", value: model.metrics.cpuPercent, tint: NeonTheme.cyan)
                    metricCard("RAM", value: model.metrics.memoryPercent, tint: NeonTheme.magenta)
                    metricCard("Armazenamento", value: model.metrics.storagePercent, tint: NeonTheme.green)
                    networkCard
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Atividade recente")
                        .font(.headline)
                    Chart(Array(model.metricsHistory.enumerated()), id: \.offset) { index, point in
                        LineMark(x: .value("Amostra", index), y: .value("CPU", point.cpuPercent))
                            .foregroundStyle(NeonTheme.cyan)
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("Amostra", index), y: .value("RAM", point.memoryPercent))
                            .foregroundStyle(NeonTheme.magenta)
                            .interpolationMethod(.catmullRom)
                    }
                    .chartYScale(domain: 0...100)
                    .chartLegend(position: .bottom, alignment: .leading)
                    .frame(height: 240)
                }
                .padding(18)
                .neonCard()
            }
            .padding(28)
        }
        .navigationTitle("Sistema")
    }

    private func metricCard(_ title: String, value: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("\(Int(value))%")
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(tint)
            }
            ProgressView(value: value, total: 100).tint(tint)
        }
        .padding(18)
        .neonCard(color: tint)
    }

    private var networkCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rede").font(.headline)
            Label("↓ \(Formatters.bytes(model.metrics.downloadBytesPerSecond, perSecond: true))", systemImage: "arrow.down")
                .foregroundStyle(NeonTheme.cyan)
            Label("↑ \(Formatters.bytes(model.metrics.uploadBytesPerSecond, perSecond: true))", systemImage: "arrow.up")
                .foregroundStyle(NeonTheme.magenta)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .neonCard()
    }
}

@ViewBuilder
private func dashboardHeader(eyebrow: String, title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
        Text(eyebrow)
            .font(.caption.monospaced().weight(.bold))
            .tracking(2)
            .foregroundStyle(NeonTheme.cyan)
        Text(title)
            .font(.largeTitle.weight(.bold))
        Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}
