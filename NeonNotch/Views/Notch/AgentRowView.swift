import SwiftUI

struct AgentRowView: View {
    let agent: AgentSnapshot
    var isSelected = false
    let openAction: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: agent.source.symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(NeonTheme.color(for: agent.status))
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 11).fill(Color.black.opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(NeonTheme.color(for: agent.status).opacity(0.38)))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Circle().fill(NeonTheme.color(for: agent.status)).frame(width: 7, height: 7)
                    Text(agent.source.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NeonTheme.color(for: agent.status))
                }
                Text(agent.task).font(.system(size: 15, weight: .medium)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(agent.project).font(.subheadline).lineLimit(1)
                Text(URL(fileURLWithPath: agent.workingDirectory).deletingLastPathComponent().lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)

            Text(Formatters.duration(agent.elapsed))
                .font(.caption.monospacedDigit())
                .foregroundStyle(agent.status == .needsAttention ? NeonTheme.magenta : .secondary)
                .frame(width: 72)

            VStack(alignment: .trailing, spacing: 5) {
                Label(agent.status.title, systemImage: agent.status.symbol)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(NeonTheme.color(for: agent.status))
                if agent.status == .needsAttention {
                    Button("OPEN SESSION", action: openAction)
                        .buttonStyle(.bordered)
                        .tint(NeonTheme.magenta)
                        .controlSize(.small)
                }
            }
            .frame(width: 112, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minHeight: 70)
        .neonCard(status: agent.status)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(NeonTheme.cyan.opacity(0.9), lineWidth: 1.25)
                    .allowsHitTesting(false)
            }
        }
        .contextMenu {
            Button("Open Session", action: openAction)
        }
    }
}
