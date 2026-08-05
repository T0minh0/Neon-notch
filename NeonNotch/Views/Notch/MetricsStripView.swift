import SwiftUI

struct MetricsStripView: View {
    let metrics: SystemMetricsSnapshot
    let history: [SystemMetricsSnapshot]

    private var memoryPercent: Double {
        metrics.memoryTotal == 0 ? 0 : Double(metrics.memoryUsed) / Double(metrics.memoryTotal) * 100
    }

    private var diskPercent: Double {
        metrics.diskTotal == 0 ? 0 : Double(metrics.diskUsed) / Double(metrics.diskTotal) * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            metricRow("CPU", value: Formatters.compactPercent(metrics.cpuPercent), percent: metrics.cpuPercent, color: NeonTheme.cyan)
            metricRow("RAM", value: Formatters.compactPercent(memoryPercent), percent: memoryPercent, color: NeonTheme.magenta)
            metricRow("SSD", value: Formatters.compactPercent(diskPercent), percent: diskPercent, color: NeonTheme.green)

            MiniWaveform(values: history.map(\.cpuPercent))
                .stroke(NeonTheme.cyan, style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
                .frame(height: 44)
                .overlay(alignment: .topTrailing) {
                    Text("↓ \(Formatters.bytes(metrics.networkDownPerSecond, perSecond: true))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(NeonTheme.cyan)
                }
        }
        .padding(.top, 3)
    }

    private func metricRow(_ title: String, value: String, percent: Double, color: Color) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(title).font(.caption.weight(.semibold))
                Spacer()
                Text(value).font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(color)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * min(1, max(0, percent / 100)))
                        .shadow(color: color.opacity(0.45), radius: 4)
                }
            }
            .frame(height: 5)
        }
    }
}

struct MiniWaveform: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        guard values.count > 1, let maxValue = values.max(), maxValue > 0 else { return Path() }
        var path = Path()
        for (index, value) in values.enumerated() {
            let x = rect.minX + CGFloat(index) / CGFloat(values.count - 1) * rect.width
            let y = rect.maxY - CGFloat(value / max(100, maxValue)) * rect.height
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}
