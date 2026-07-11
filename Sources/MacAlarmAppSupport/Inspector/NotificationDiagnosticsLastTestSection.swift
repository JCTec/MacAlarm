import MacAlarmCore
import SwiftUI

struct NotificationDiagnosticsLastTestSection: View {
    let result: NotificationTestResult

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Last Test")
                .font(.headline)
            detailRow("Channel", result.delivery.channel)
            detailRow("Succeeded", result.delivery.succeeded ? "yes" : "no")
            detailRow("Detail", result.delivery.detail)
            detailRow("Ledger", result.deliveryRecord == nil ? "not recorded" : "recorded")
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)

            Text(value)
                .font(.caption)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
    }
}
