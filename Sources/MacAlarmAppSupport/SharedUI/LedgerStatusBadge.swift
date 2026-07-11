import MacAlarmCore
import SwiftUI

struct LedgerStatusBadge: View {
    let continuity: LedgerVerification?

    var body: some View {
        let status = continuityStatus

        StatusBadge {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
        } content: {
            Text(status.title)
            if let continuity {
                Text("\(continuity.recordCount) records")
                    .foregroundStyle(.secondary)
            }
        }
        .help(status.help)
    }

    private var continuityStatus: (title: String, color: Color, help: String) {
        guard let continuity else {
            return (
                "Loading",
                Color.secondary.opacity(0.8),
                "Loading live ledger. Open Ledger Integrity for HMAC verification."
            )
        }

        if continuity.isValid {
            return (
                "Linked",
                Color.blue.opacity(0.85),
                "Live timeline continuity check passed. Open Ledger Integrity for HMAC verification."
            )
        }

        return (
            "Chain issue",
            Color.red.opacity(0.9),
            "Live timeline detected a broken previous-hash link. Open Ledger Integrity for full HMAC verification."
        )
    }
}
