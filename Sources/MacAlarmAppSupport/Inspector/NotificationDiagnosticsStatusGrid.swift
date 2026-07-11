import MacAlarmCore
import SwiftUI

struct NotificationDiagnosticsStatusGrid: View {
    let snapshot: NotificationAuthorizationSnapshot?

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
            diagnosticRow("Authorization", snapshot?.authorizationStatus ?? "unknown")
            diagnosticRow("Alerts", snapshot?.alertSetting ?? "unknown")
            diagnosticRow("Sound", snapshot?.soundSetting ?? "unknown")
            diagnosticRow("Badge", snapshot?.badgeSetting ?? "unknown")
        }
    }

    private func diagnosticRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)

            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
    }
}
