import MacAlarmCore
import SwiftUI

struct TimelineStatusRow: View {
    let continuity: LedgerVerification?
    let visibleCount: Int
    let totalCount: Int
    let loadError: String?
    let showLedgerIntegrity: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            LedgerStatusBadge(continuity: continuity)
                .onTapGesture {
                    showLedgerIntegrity()
                }

            Text("\(visibleCount) / \(totalCount)")
                .foregroundStyle(.secondary)

            if let error = loadError {
                Text(error)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Spacer()
        }
        .font(.caption)
    }
}
