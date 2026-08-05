import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: NotchPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        AppModel.shared.start()
        panelController = NotchPanelController(model: AppModel.shared)
        panelController?.show()

        let shouldPresentOnboarding = AppModel.shared.showsOnboarding
        DispatchQueue.main.async { [weak self] in
            // SwiftUI scenes created by an older build may still be restored once.
            // The daily-driver launch owns only the notch until explicitly opened.
            for window in NSApp.windows where self?.panelController?.owns(window) != true {
                window.isRestorable = false
                window.close()
            }
            if shouldPresentOnboarding {
                NotificationCenter.default.post(name: .openControlCenter, object: nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NotificationCenter.default.post(name: .openControlCenter, object: nil)
        }
        return true
    }
}

extension Notification.Name {
    static let openControlCenter = Notification.Name("NeonNotch.openControlCenter")
    static let globalShortcutTriggered = Notification.Name("NeonNotch.globalShortcutTriggered")
}
