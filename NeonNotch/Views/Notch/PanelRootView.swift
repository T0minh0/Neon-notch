import SwiftUI

struct PanelRootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var geometry: NotchGeometry
    @ObservedObject var renderingState: NotchRenderingState
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var pulseStrength: CGFloat = 0
    @State private var transientAlert: NotchAlertKind?
    @State private var pulseTask: Task<Void, Never>?

    private var reduceMotion: Bool {
        model.reducedMotion || accessibilityReduceMotion
    }

    var body: some View {
        ZStack(alignment: .top) {
            renderedPanel
                .id(renderingState.renderedState)
                .transition(.opacity.combined(with: .scale(scale: 0.994, anchor: .top)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onHover(perform: model.hoverChanged)
        .modifier(PanelExpansionGesture(enabled: renderingState.renderedState != .expanded) {
            model.toggleExpanded()
        })
        .onChange(of: model.alertPulse) { _, _ in runAlertPulse() }
        .onDisappear { pulseTask?.cancel() }
        .ignoresSafeArea()
        .accessibilityLabel("Neon Notch")
        .accessibilityHint(model.panelState == .expanded ? "Click to interact with agents and media" : "Click to expand")
    }

    @ViewBuilder
    private var renderedPanel: some View {
        switch renderingState.renderedState {
        case .collapsed:
            CollapsedNotchView(
                geometry: geometry,
                showsPersistentAttention: model.unreadAttention,
                transientAlert: transientAlert,
                pulseStrength: pulseStrength
            )
        case .hoverPreview:
            ShapedNotchPanel(
                topInset: geometry.notchHeight,
                notchWidth: geometry.notchWidth,
                taperedBottom: false,
                highlightsAttention: model.unreadAttention
            ) {
                HoverPreviewView(model: model, topInset: geometry.notchHeight)
            }
        case .expanded:
            ShapedNotchPanel(
                topInset: geometry.notchHeight,
                notchWidth: geometry.notchWidth,
                taperedBottom: true,
                highlightsAttention: model.unreadAttention
            ) {
                ExpandedPanelView(model: model, topInset: geometry.notchHeight)
            }
        }
    }

    private func runAlertPulse() {
        pulseTask?.cancel()
        let kind: NotchAlertKind = model.unreadAttention ? .attention : model.latestNotchAlert
        transientAlert = kind

        if reduceMotion {
            pulseStrength = 0.72
            pulseTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.1))
                guard !Task.isCancelled else { return }
                pulseStrength = 0
                transientAlert = nil
            }
            return
        }

        pulseTask = Task { @MainActor in
            let pulseCount = kind == .attention ? 3 : 1
            for _ in 0..<pulseCount {
                guard !Task.isCancelled else { return }
                withAnimation(.easeIn(duration: 0.16)) { pulseStrength = 1 }
                try? await Task.sleep(for: .milliseconds(160))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.24)) { pulseStrength = 0 }
                try? await Task.sleep(for: .milliseconds(240))
            }
            guard !Task.isCancelled else { return }
            transientAlert = nil
        }
    }
}

private struct ShapedNotchPanel<Content: View>: View {
    let topInset: CGFloat
    let notchWidth: CGFloat
    let taperedBottom: Bool
    let highlightsAttention: Bool
    let content: Content

    init(
        topInset: CGFloat,
        notchWidth: CGFloat,
        taperedBottom: Bool,
        highlightsAttention: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.topInset = topInset
        self.notchWidth = notchWidth
        self.taperedBottom = taperedBottom
        self.highlightsAttention = highlightsAttention
        self.content = content()
    }

    var body: some View {
        let shape = NeonNotchShape(
            topInset: topInset,
            notchWidth: notchWidth,
            taperedBottom: taperedBottom
        )

        ZStack {
            shape
                .fill(Color.black)
                .shadow(
                    color: (highlightsAttention ? NeonTheme.magenta : NeonTheme.cyan).opacity(0.25),
                    radius: 18
                )
                .allowsHitTesting(false)

            ZStack {
                shape.fill(
                    LinearGradient(
                        colors: [NeonTheme.smokeTop, NeonTheme.smokeMiddle, NeonTheme.smokeBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .allowsHitTesting(false)
                shape.fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.055), Color.clear, NeonTheme.cyan.opacity(0.025)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .allowsHitTesting(false)
                content
            }
            .clipShape(shape)

            shape.stroke(
                LinearGradient(
                    colors: [
                        NeonTheme.cyan.opacity(0.84),
                        Color.white.opacity(0.13),
                        NeonTheme.magenta.opacity(highlightsAttention ? 1 : 0.78)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
            .allowsHitTesting(false)

            shape
                .stroke(Color.white.opacity(0.055), lineWidth: 3)
                .blur(radius: 1.5)
                .clipShape(shape)
                .allowsHitTesting(false)
        }
        .compositingGroup()
    }
}

private struct CollapsedNotchView: View {
    @ObservedObject var geometry: NotchGeometry
    let showsPersistentAttention: Bool
    let transientAlert: NotchAlertKind?
    let pulseStrength: CGFloat

    private var pulseColor: Color {
        transientAlert == .completion ? NeonTheme.green : NeonTheme.magenta
    }

    var body: some View {
        ZStack {
            Color.clear

            if showsPersistentAttention {
                NotchContourShape(notchWidth: geometry.notchWidth, notchHeight: geometry.notchHeight)
                    .stroke(NeonTheme.magenta.opacity(0.62), lineWidth: 0.5)
            }

            if transientAlert != nil, pulseStrength > 0 {
                NotchContourShape(notchWidth: geometry.notchWidth, notchHeight: geometry.notchHeight)
                    .stroke(pulseColor.opacity(pulseStrength), lineWidth: 0.9)
                    .shadow(color: pulseColor.opacity(pulseStrength * 0.82), radius: 7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(showsPersistentAttention ? "Agent needs attention" : "Neon Notch standby")
    }
}

private struct HoverPreviewView: View {
    @ObservedObject var model: AppModel
    let topInset: CGFloat

    var body: some View {
        HStack(spacing: 18) {
            if let agent = model.sortedAgents.first {
                Image(systemName: agent.source.symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(NeonTheme.color(for: agent.status))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(NeonTheme.raised))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(agent.source.title).foregroundStyle(NeonTheme.color(for: agent.status))
                        Text(agent.status.title)
                            .font(.caption.monospaced().weight(.semibold))
                            .foregroundStyle(NeonTheme.color(for: agent.status))
                    }
                    Text(agent.task).font(.headline).lineLimit(1)
                    Text(agent.reason ?? agent.project).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                Label("No active agents", systemImage: "moon.stars")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            if model.media.state != .stopped {
                CompactMediaView(model: model)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, topInset + 13)
        .padding(.bottom, 14)
    }
}

private struct ExpandedPanelView: View {
    @ObservedObject var model: AppModel
    let topInset: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 20) {
                panelSection
                .frame(maxWidth: .infinity)

                Divider().overlay(NeonTheme.separator)

                MetricsStripView(metrics: model.metrics, history: model.metricsHistory)
                    .frame(width: 220)
            }
            .padding(.horizontal, 26)
            .padding(.top, topInset + 16)
            .padding(.bottom, 14)
            .frame(
                height: NotchPanelMetrics.expandedHeight - NotchPanelMetrics.footerHeight,
                alignment: .top
            )
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(NeonTheme.separator)
                    .frame(height: 1)
                    .allowsHitTesting(false)
            }

            MediaFooterView(model: model)
                .frame(maxWidth: 600)
                .frame(height: NotchPanelMetrics.footerHeight)
                .padding(.horizontal, 28)
                .offset(y: -3)
        }
        .frame(height: NotchPanelMetrics.expandedHeight, alignment: .top)
        .overlay(alignment: .topLeading) {
            ExpandedPanelSectionHeader(model: model)
                .padding(.leading, 26)
                .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var panelSection: some View {
        switch model.expandedPanelSection {
        case .agents:
            VStack(spacing: 10) {
                ForEach(model.panelAgents) { agent in
                    AgentRowView(agent: agent, isSelected: model.selectedAgentID == agent.id) { model.open(agent) }
                }
                if model.panelAgents.isEmpty {
                    EmptyAgentsView()
                }
            }
            .transition(.opacity)
        case .clipboard:
            ExpandedClipboardView(model: model)
                .transition(.opacity)
        }
    }
}

private struct PanelExpansionGesture: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.onTapGesture(perform: action)
        } else {
            content
        }
    }
}

private struct ExpandedPanelSectionHeader: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(ExpandedPanelSection.allCases) { section in
                    Button {
                        withAnimation(.easeOut(duration: 0.14)) {
                            model.expandedPanelSection = section
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: section.symbol)
                            Text(section.title)
                            if section == .agents, model.unreadAttention {
                                Circle()
                                    .fill(NeonTheme.magenta)
                                    .frame(width: 6, height: 6)
                                    .shadow(color: NeonTheme.magenta.opacity(0.7), radius: 4)
                                    .allowsHitTesting(false)
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(model.expandedPanelSection == section ? Color.white : NeonTheme.muted)
                        .padding(.horizontal, 9)
                        .frame(minHeight: 28)
                        .background {
                            if model.expandedPanelSection == section {
                                Capsule().fill(NeonTheme.raised)
                                    .overlay(Capsule().stroke(NeonTheme.cyan.opacity(0.34), lineWidth: 0.75))
                                    .allowsHitTesting(false)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Mostrar \(section.title.lowercased())")
                    .accessibilityLabel("Mostrar \(section.title)")
                }
            }
            .padding(2)
            .background(Capsule().fill(Color.black.opacity(0.5)).allowsHitTesting(false))

            if model.expandedPanelSection == .clipboard {
                Button("Clear") { model.clearClipboard() }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(model.hasClearableClipboardEntries ? NeonTheme.magenta : NeonTheme.muted)
                    .frame(minWidth: 44, minHeight: 28)
                    .contentShape(Rectangle())
                    .disabled(!model.hasClearableClipboardEntries)
                    .help("Remover itens não fixados do cache")
                    .accessibilityLabel("Limpar itens não fixados do Clipboard")
            }
        }
    }
}

private struct EmptyAgentsView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 26))
                .foregroundStyle(NeonTheme.cyan)
            Text("No active agents").font(.headline)
            Text("Recent Codex and Claude Code sessions appear here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 190)
        .neonCard()
    }
}
