import Foundation
import UserNotifications

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .badge]) { _, _ in }
    }

    func postAttention(for agent: AgentSnapshot, playsSound: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = "\(agent.source.title) needs you"
        content.body = agent.reason ?? agent.task
        content.sound = playsSound ? .default : nil
        content.userInfo = ["sessionID": agent.sessionID, "source": agent.source.rawValue]
        let request = UNNotificationRequest(identifier: "agent-\(agent.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner]
    }
}
