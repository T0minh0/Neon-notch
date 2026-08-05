import Foundation
import UserNotifications

struct AgentNotificationTarget: Sendable {
    let sessionID: String
    let source: AgentSource
}

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private let categoryIdentifier = "AGENT_ATTENTION"
    private let openActionIdentifier = "OPEN_SESSION"
    private var openHandler: ((AgentNotificationTarget) -> Void)?

    func configure(openHandler: @escaping (AgentNotificationTarget) -> Void) {
        self.openHandler = openHandler
        let action = UNNotificationAction(
            identifier: openActionIdentifier,
            title: "Abrir sessão",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [action],
            intentIdentifiers: [],
            options: []
        )
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([category])
    }

    func postAttention(for agent: AgentSnapshot, playsSound: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = "\(agent.source.title) precisa de você"
        content.body = agent.reason ?? agent.task
        content.sound = playsSound ? .default : nil
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = ["sessionID": agent.sessionID, "source": agent.source.rawValue]
        let request = UNNotificationRequest(identifier: "agent-\(agent.id)-\(agent.updatedAt.timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier
                || response.actionIdentifier == "OPEN_SESSION",
              let sessionID = response.notification.request.content.userInfo["sessionID"] as? String,
              let sourceValue = response.notification.request.content.userInfo["source"] as? String,
              let source = AgentSource(rawValue: sourceValue) else { return }
        await MainActor.run {
            openHandler?(AgentNotificationTarget(sessionID: sessionID, source: source))
        }
    }
}
