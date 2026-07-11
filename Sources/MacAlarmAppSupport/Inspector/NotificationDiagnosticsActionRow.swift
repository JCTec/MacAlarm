import SwiftUI

struct NotificationDiagnosticsActionRow: View {
    let isLoading: Bool
    let sendTestNotification: () -> Void
    let openNotificationSettings: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Button("Send Test Notification") {
                sendTestNotification()
            }
            .disabled(isLoading)

            Button("Open System Settings") {
                openNotificationSettings()
            }

            Spacer()
        }
        .buttonStyle(.bordered)
    }
}
