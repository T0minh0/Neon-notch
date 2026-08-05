import SwiftUI

@main
struct NeonNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("Neon Notch", id: "controlCenter") {
            ControlCenterView(model: model)
                .preferredColorScheme(.dark)
                .frame(minWidth: 860, minHeight: 600)
        }
        .defaultSize(width: 1040, height: 720)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commands {
            CommandGroup(after: .appInfo) {
                OpenWindowButton(title: "Open Control Center", windowID: "controlCenter")
                    .keyboardShortcut("0", modifiers: [.command])
            }
        }

        Settings {
            SettingsView(model: model)
                .preferredColorScheme(.dark)
                .frame(width: 580, height: 470)
        }
        .restorationBehavior(.disabled)
    }
}

private struct OpenWindowButton: View {
    let title: String
    let windowID: String
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(title) { openWindow(id: windowID) }
            .onReceive(NotificationCenter.default.publisher(for: .openControlCenter)) { _ in
                openWindow(id: windowID)
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}
