import MacAlarmCore
import SwiftUI

struct LedgerIntegritySummaryGrid: View {
    let snapshot: LedgerIntegritySnapshot?
    let isLoading: Bool
    let errorMessage: String?
    let ledgerPath: String
    let fallbackRecordCount: Int
    @State private var showsTechnicalDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if let errorMessage {
                setupMessage(errorMessage)
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                integrityRow("Status", statusText)
                integrityRow("Records", recordCount)
                integrityRow("First event", dateText(snapshot?.firstEventAt))
                integrityRow("Last event", dateText(snapshot?.lastEventAt))
                integrityRow("Checked", dateText(snapshot?.checkedAt))
            }

            DisclosureGroup("Technical details", isExpanded: $showsTechnicalDetails) {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                    integrityRow("Ledger", snapshot?.ledgerPath ?? ledgerPath, allowsWrapping: true)
                    integrityRow(
                        "Last hash",
                        snapshot?.verification.lastHash ?? HashChainLedger.zeroHash,
                        isMonospaced: true,
                        allowsWrapping: true
                    )
                    if let errorMessage {
                        integrityRow("Message", errorMessage, allowsWrapping: true)
                    }
                }
                .padding(.top, AppSpacing.sm)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        if isLoading {
            return "Verifying"
        }
        if errorMessage != nil {
            return "Unavailable"
        }
        guard let snapshot else {
            return "Not checked"
        }

        return snapshot.verification.isValid ? "Valid" : "Invalid"
    }

    private var recordCount: String {
        guard let snapshot else {
            return String(fallbackRecordCount)
        }
        return String(snapshot.verification.recordCount)
    }

    private func setupMessage(_ errorMessage: String) -> some View {
        let isMissingKey = errorMessage.localizedCaseInsensitiveContains("HMAC key")
        return HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: isMissingKey ? "key.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isMissingKey ? .orange : .red)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(isMissingKey ? "Ledger verification is waiting for recorder setup." : "Ledger verification is unavailable.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(
                    isMissingKey
                        ? "Install or start the recorder so MacAlarm can create the private HMAC key. No manual key management is needed."
                        : "MacAlarm could not verify the ledger right now. Open technical details only if you need the exact diagnostic message."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: AppRadius.card))
    }

    private func integrityRow(
        _ title: String,
        _ value: String,
        isMonospaced: Bool = false,
        allowsWrapping: Bool = false
    ) -> some View {
        GridRow {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)

            Text(value)
                .font(isMonospaced ? .system(.caption, design: .monospaced) : .caption)
                .textSelection(.enabled)
                .lineLimit(allowsWrapping ? 4 : 1)
        }
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else {
            return "none"
        }

        return date.formatted(date: .abbreviated, time: .standard)
    }
}
