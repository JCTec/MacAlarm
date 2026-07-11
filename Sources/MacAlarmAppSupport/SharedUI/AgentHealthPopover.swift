import MacAlarmCore
import SwiftUI

struct AgentHealthPopover: View {
    let presentation: AgentHealthPresentation
    let snapshot: AgentStatusSnapshot?
    let loadError: String?
    let installAgent: @MainActor @Sendable () -> Void
    let startAgent: @MainActor @Sendable () -> Void
    let showLedgerIntegrity: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                IconTile(
                    symbolName: "waveform.path.ecg",
                    tintColor: presentation.level.tintColor,
                    size: 30
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.title)
                        .font(.headline.weight(.semibold))
                    Text(presentation.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let primaryAction = RecorderHealthActionContent.primaryAction(for: presentation) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Button {
                        switch primaryAction.action {
                        case .install:
                            installAgent()
                        case .start:
                            startAgent()
                        }
                    } label: {
                        Label(primaryAction.buttonTitle, systemImage: primaryAction.symbolName)
                    }
                    .buttonStyle(.borderedProminent)

                    Text(primaryAction.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let snapshot {
                AgentHealthDetailRow(title: "PID", value: String(snapshot.processID))
                AgentHealthDetailRow(title: "State", value: snapshot.state.rawValue)
                AgentHealthDetailRow(title: "Events", value: String(snapshot.processedEventCount))
                AgentHealthDetailRow(title: "Heartbeats", value: String(snapshot.heartbeatCount))
                AgentHealthDetailRow(title: "Ledger", value: snapshot.ledgerPath)
                if let latestEventName = snapshot.latestEventName {
                    AgentHealthDetailRow(title: "Latest", value: latestEventName)
                }
                if let latestLedgerHash = snapshot.latestLedgerHash {
                    AgentHealthDetailRow(title: "Hash", value: String(latestLedgerHash.prefix(12)))
                }
            } else if let error = loadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Button("Ledger Integrity") {
                showLedgerIntegrity()
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .frame(width: 320)
    }
}

private struct AgentHealthDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .leading)
            Text(value)
                .font(.caption)
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}
