import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchGeometry: ObservableObject {
    @Published var notchWidth: CGFloat = 210
    @Published var notchHeight: CGFloat = 38
}

@MainActor
final class NotchRenderingState: ObservableObject {
    @Published var renderedState: PanelPresentationState

    init(renderedState: PanelPresentationState) {
        self.renderedState = renderedState
    }
}

@MainActor
final class NotchPanelController {
    private let model: AppModel
    private let geometry = NotchGeometry()
    private let renderingState: NotchRenderingState
    private let panel: NeonPanel
    private var cancellables: Set<AnyCancellable> = []
    private var outsideMonitor: Any?
    private var keyMonitor: Any?
    private var transitionTask: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
        renderingState = NotchRenderingState(renderedState: model.panelState)
        panel = NeonPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configurePanel()
        let hostingView = NSHostingView(
            rootView: PanelRootView(
                model: model,
                geometry: geometry,
                renderingState: renderingState
            )
        )
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        model.$panelState
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] state in self?.transition(to: state) }
            .store(in: &cancellables)

        let center = NotificationCenter.default
        center.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .merge(with: center.publisher(for: NSWorkspace.didWakeNotification))
            .sink { [weak self] _ in self?.setFrame(for: model.panelState) }
            .store(in: &cancellables)
        installEventMonitors()
    }

    func show() {
        transitionTask?.cancel()
        renderingState.renderedState = model.panelState
        setFrame(for: model.panelState)
        panel.orderFrontRegardless()
    }

    private func configurePanel() {
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
    }

    private func installEventMonitors() {
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in
                guard let self, self.model.panelState == .expanded else { return }
                let location = NSEvent.mouseLocation
                if !self.panel.frame.contains(location) { self.model.collapsePanel() }
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self else { return event }
            self.model.collapsePanel()
            return nil
        }
    }

    private func transition(to targetState: PanelPresentationState) {
        transitionTask?.cancel()

        if targetState == .collapsed {
            withAnimation(.easeOut(duration: NotchPanelMetrics.collapseDuration)) {
                renderingState.renderedState = .collapsed
            }
            transitionTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(NotchPanelMetrics.collapseDuration))
                guard !Task.isCancelled, let self, self.model.panelState == .collapsed else { return }
                self.setFrame(for: .collapsed)
            }
            return
        }

        let revealAfterResize = renderingState.renderedState == .collapsed || targetSizeIsLarger(targetState)
        if revealAfterResize {
            setFrame(for: targetState)
            panel.displayIfNeeded()
            transitionTask = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled, let self, self.model.panelState == targetState else { return }
                withAnimation(.easeOut(duration: NotchPanelMetrics.revealDuration)) {
                    self.renderingState.renderedState = targetState
                }
            }
        } else {
            withAnimation(.easeOut(duration: NotchPanelMetrics.collapseDuration)) {
                renderingState.renderedState = targetState
            }
            transitionTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(NotchPanelMetrics.collapseDuration))
                guard !Task.isCancelled, let self, self.model.panelState == targetState else { return }
                self.setFrame(for: targetState)
            }
        }
    }

    private func targetSizeIsLarger(_ state: PanelPresentationState) -> Bool {
        guard let screen = preferredScreen() else { return false }
        let target = size(for: state, screen: screen)
        return target.width > panel.frame.width || target.height > panel.frame.height
    }

    private func setFrame(for state: PanelPresentationState) {
        guard let screen = preferredScreen() else { return }
        updateGeometry(from: screen)
        let size = size(for: state, screen: screen)
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        panel.contentMinSize = size
        panel.contentMaxSize = size
        panel.setFrame(frame, display: true, animate: false)
        panel.orderFrontRegardless()
    }

    private func preferredScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    private func updateGeometry(from screen: NSScreen) {
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            geometry.notchWidth = max(170, right.minX - left.maxX)
            geometry.notchHeight = max(30, screen.safeAreaInsets.top)
        } else {
            geometry.notchWidth = 210
            geometry.notchHeight = 38
        }
    }

    private func size(for state: PanelPresentationState, screen: NSScreen) -> NSSize {
        switch state {
        case .collapsed:
            NSSize(
                width: geometry.notchWidth + NotchPanelMetrics.collapsedHorizontalAllowance,
                height: geometry.notchHeight + NotchPanelMetrics.collapsedVerticalAllowance
            )
        case .hoverPreview:
            NSSize(width: min(600, screen.frame.width - 48), height: 142)
        case .expanded:
            NSSize(width: min(1120, screen.frame.width - 48), height: NotchPanelMetrics.expandedHeight)
        }
    }

}

private final class NeonPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
