import MacAlarmCore
import SwiftUI

struct NotificationDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var diagnosticsStore = NotificationDiagnosticsStore()
    let openNotificationSettings: () -> Void

    var body: some View {
        let headerState = NotificationDiagnosticsHeaderState(
            snapshot: diagnosticsStore.snapshot,
            isLoading: diagnosticsStore.isLoading
        )

        VStack(spacing: 0) {
            PanelHeader(
                title: "Notifications",
                subtitle: headerState.subtitle,
                symbolName: "bell.badge.fill",
                tintColor: headerState.tintColor
            ) {
                HStack(spacing: AppSpacing.sm) {
                    ToolbarIconButton(
                        symbolName: "arrow.clockwise",
                        helpText: "Refresh notification status",
                        isEnabled: !diagnosticsStore.isLoading
                    ) {
                        diagnosticsStore.refresh()
                    }
                    ToolbarIconButton(symbolName: "xmark", helpText: "Close notifications") {
                        dismiss()
                    }
                }
            }

            AppSeparator()

            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                NotificationDiagnosticsStatusGrid(snapshot: diagnosticsStore.snapshot)

                if let result = diagnosticsStore.lastResult {
                    NotificationDiagnosticsLastTestSection(result: result)
                }

                if let error = diagnosticsStore.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                NotificationDiagnosticsActionRow(
                    isLoading: diagnosticsStore.isLoading,
                    sendTestNotification: {
                        diagnosticsStore.sendTestNotification()
                    },
                    openNotificationSettings: {
                        openNotificationSettings()
                    }
                )
            }
            .padding(18)
        }
        .frame(width: 520)
        .background(MacAlarmBackground())
        .task {
            if diagnosticsStore.snapshot == nil {
                diagnosticsStore.refresh()
            }
        }
    }
}
