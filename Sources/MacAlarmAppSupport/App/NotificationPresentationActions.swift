import AppKit
import MacAlarmCore
import UserNotifications

extension MacAlarmApplicationDelegate: UNUserNotificationCenterDelegate {
    func configureNotificationPresentation() {
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    @objc func sendTestNotification(_ sender: Any?) {
        let service = MacAlarmNotificationService()
        Task {
            do {
                let result = try await service.sendTestNotification()
                showInfo(title: notificationResultTitle(result), message: notificationResultMessage(result))
            } catch {
                showError(title: "Notification Test Failed", error: error)
            }
        }
    }

    @objc func openNotificationSettings(_ sender: Any?) {
        MacAlarmSystemSettings.openNotifications()
    }

    private func notificationResultTitle(_ result: NotificationTestResult) -> String {
        result.delivery.succeeded ? "Test Notification Sent" : "Test Notification Failed"
    }

    private func notificationResultMessage(_ result: NotificationTestResult) -> String {
        [
            "Channel: \(result.delivery.channel)",
            "Succeeded: \(result.delivery.succeeded ? "yes" : "no")",
            "Detail: \(result.delivery.detail)",
            "Authorization: \(result.after.authorizationStatus)",
            "Ledger: \(result.deliveryRecord == nil ? "not recorded" : "recorded")",
        ].joined(separator: "\n")
    }
}
