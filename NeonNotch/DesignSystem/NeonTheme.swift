import SwiftUI

enum NeonTheme {
    static let background = Color(red: 0.012, green: 0.022, blue: 0.035)
    static let smokeTop = Color(red: 0.018, green: 0.035, blue: 0.050)
    static let smokeMiddle = Color(red: 0.012, green: 0.027, blue: 0.039)
    static let smokeBottom = Color(red: 0.008, green: 0.016, blue: 0.026)
    static let raised = Color(red: 0.027, green: 0.047, blue: 0.065)
    static let graphite = Color(red: 0.11, green: 0.14, blue: 0.17)
    static let cyan = Color(red: 0.0, green: 0.82, blue: 1.0)
    static let magenta = Color(red: 1.0, green: 0.12, blue: 0.42)
    static let green = Color(red: 0.42, green: 0.94, blue: 0.14)
    static let amber = Color(red: 1.0, green: 0.62, blue: 0.12)
    static let muted = Color.white.opacity(0.48)
    static let separator = Color.white.opacity(0.12)

    static func color(for status: AgentStatus) -> Color {
        switch status {
        case .working: cyan
        case .needsAttention: magenta
        case .completed: green
        case .unknown: muted
        }
    }
}

enum NotchPanelMetrics {
    static let expandedHeight: CGFloat = 380
    static let footerHeight: CGFloat = 72
    static let collapsedHorizontalAllowance: CGFloat = 16
    static let collapsedVerticalAllowance: CGFloat = 8
    static let revealDuration: TimeInterval = 0.18
    static let collapseDuration: TimeInterval = 0.16

    static func bottomInset(for width: CGFloat) -> CGFloat {
        min(width * 0.27, 300)
    }

    static func taperStartY(in rect: CGRect) -> CGFloat {
        max(rect.minY, rect.maxY - footerHeight)
    }
}

struct NeonCardModifier: ViewModifier {
    var status: AgentStatus?

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(NeonTheme.raised.opacity(0.72))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(status.map(NeonTheme.color(for:)) ?? NeonTheme.separator, lineWidth: status == .needsAttention ? 1.2 : 0.75)
                    }
                    .shadow(color: status.map { NeonTheme.color(for: $0).opacity(0.22) } ?? .clear, radius: 12)
            )
    }
}

struct NeonBorderCardModifier: ViewModifier {
    var color: Color?

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(NeonTheme.raised.opacity(0.72))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(color?.opacity(0.58) ?? NeonTheme.separator, lineWidth: color == nil ? 0.75 : 1)
                    }
                    .shadow(color: color?.opacity(0.2) ?? .clear, radius: 12)
            )
    }
}

extension View {
    func neonCard(status: AgentStatus? = nil) -> some View {
        modifier(NeonCardModifier(status: status))
    }

    func neonCard(color: Color?) -> some View {
        modifier(NeonBorderCardModifier(color: color))
    }
}

struct NeonNotchShape: Shape {
    var topInset: CGFloat = 40
    var notchWidth: CGFloat = 210
    var taperedBottom = false

    func path(in rect: CGRect) -> Path {
        let corner: CGFloat = 34
        let shoulder: CGFloat = 18
        let notchLeft = rect.midX - notchWidth / 2
        let notchRight = rect.midX + notchWidth / 2
        var path = Path()
        path.move(to: CGPoint(x: corner, y: 0))
        path.addLine(to: CGPoint(x: notchLeft - shoulder, y: 0))
        path.addCurve(
            to: CGPoint(x: notchLeft, y: topInset),
            control1: CGPoint(x: notchLeft - 8, y: 0),
            control2: CGPoint(x: notchLeft - 10, y: topInset)
        )
        path.addLine(to: CGPoint(x: notchRight, y: topInset))
        path.addCurve(
            to: CGPoint(x: notchRight + shoulder, y: 0),
            control1: CGPoint(x: notchRight + 10, y: topInset),
            control2: CGPoint(x: notchRight + 8, y: 0)
        )
        path.addLine(to: CGPoint(x: rect.maxX - corner, y: 0))
        path.addCurve(to: CGPoint(x: rect.maxX, y: corner), control1: CGPoint(x: rect.maxX - 10, y: 0), control2: CGPoint(x: rect.maxX, y: 10))
        if taperedBottom {
            let bottomInset = NotchPanelMetrics.bottomInset(for: rect.width)
            let taperStart = NotchPanelMetrics.taperStartY(in: rect)
            let curveMidY = taperStart + NotchPanelMetrics.footerHeight * 0.5
            let firstShoulder = bottomInset * 0.43
            path.addLine(to: CGPoint(x: rect.maxX, y: taperStart))
            path.addCurve(
                to: CGPoint(x: rect.maxX - firstShoulder, y: curveMidY),
                control1: CGPoint(x: rect.maxX, y: taperStart + 18),
                control2: CGPoint(x: rect.maxX - bottomInset * 0.18, y: curveMidY - 5)
            )
            path.addCurve(
                to: CGPoint(x: rect.maxX - bottomInset, y: rect.maxY),
                control1: CGPoint(x: rect.maxX - bottomInset * 0.68, y: curveMidY + 7),
                control2: CGPoint(x: rect.maxX - bottomInset + 42, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX + bottomInset, y: rect.maxY))
            path.addCurve(
                to: CGPoint(x: rect.minX + firstShoulder, y: curveMidY),
                control1: CGPoint(x: rect.minX + bottomInset - 42, y: rect.maxY),
                control2: CGPoint(x: rect.minX + bottomInset * 0.68, y: curveMidY + 7)
            )
            path.addCurve(
                to: CGPoint(x: rect.minX, y: taperStart),
                control1: CGPoint(x: rect.minX + bottomInset * 0.18, y: curveMidY - 5),
                control2: CGPoint(x: rect.minX, y: taperStart + 18)
            )
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - corner))
            path.addCurve(to: CGPoint(x: rect.maxX - corner, y: rect.maxY), control1: CGPoint(x: rect.maxX, y: rect.maxY - 10), control2: CGPoint(x: rect.maxX - 10, y: rect.maxY))
            path.addLine(to: CGPoint(x: corner, y: rect.maxY))
            path.addCurve(to: CGPoint(x: 0, y: rect.maxY - corner), control1: CGPoint(x: 10, y: rect.maxY), control2: CGPoint(x: 0, y: rect.maxY - 10))
        }
        path.addLine(to: CGPoint(x: 0, y: corner))
        path.addCurve(to: CGPoint(x: corner, y: 0), control1: CGPoint(x: 0, y: 10), control2: CGPoint(x: 10, y: 0))
        path.closeSubpath()
        return path
    }
}

struct NotchContourShape: Shape {
    var notchWidth: CGFloat = 210
    var notchHeight: CGFloat = 38

    func path(in rect: CGRect) -> Path {
        let left = rect.midX - notchWidth / 2
        let right = rect.midX + notchWidth / 2
        let bottom = min(rect.maxY - 1, notchHeight)
        let radius = min(10, notchHeight * 0.28)
        var path = Path()
        path.move(to: CGPoint(x: left, y: rect.minY))
        path.addLine(to: CGPoint(x: left, y: bottom - radius))
        path.addCurve(
            to: CGPoint(x: left + radius, y: bottom),
            control1: CGPoint(x: left, y: bottom - radius * 0.35),
            control2: CGPoint(x: left + radius * 0.35, y: bottom)
        )
        path.addLine(to: CGPoint(x: right - radius, y: bottom))
        path.addCurve(
            to: CGPoint(x: right, y: bottom - radius),
            control1: CGPoint(x: right - radius * 0.35, y: bottom),
            control2: CGPoint(x: right, y: bottom - radius * 0.35)
        )
        path.addLine(to: CGPoint(x: right, y: rect.minY))
        return path
    }
}
