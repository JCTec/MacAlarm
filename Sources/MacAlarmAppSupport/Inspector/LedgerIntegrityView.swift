import AppKit
import SwiftUI

struct LedgerIntegrityView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var integrityStore = LedgerIntegrityStore()
    let ledgerPath: String
    let fallbackRecordCount: Int
    let exportProofBundle: () -> Void

    var body: some View {
        let headerState = LedgerIntegrityHeaderState(
            snapshot: integrityStore.snapshot,
            isLoading: integrityStore.isLoading,
            errorMessage: integrityStore.errorMessage
        )

        VStack(spacing: 0) {
            PanelHeader(
                title: "Ledger Integrity",
                subtitle: headerState.subtitle,
                symbolName: "link",
                tintColor: headerState.tintColor
            ) {
                HStack(spacing: AppSpacing.sm) {
                    ToolbarIconButton(
                        symbolName: "arrow.clockwise",
                        helpText: "Refresh ledger integrity",
                        isEnabled: !integrityStore.isLoading
                    ) {
                        integrityStore.refresh()
                    }
                    ToolbarIconButton(symbolName: "xmark", helpText: "Close integrity view") {
                        dismiss()
                    }
                }
            }

            AppSeparator()

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    LedgerIntegritySummaryGrid(
                        snapshot: integrityStore.snapshot,
                        isLoading: integrityStore.isLoading,
                        errorMessage: integrityStore.errorMessage,
                        ledgerPath: ledgerPath,
                        fallbackRecordCount: fallbackRecordCount
                    )

                    if let issues = integrityStore.snapshot?.verification.issues, !issues.isEmpty {
                        LedgerIntegrityIssueSection(issues: issues)
                    }

                    LedgerIntegrityActionRow(
                        canExportProof: integrityStore.snapshot != nil && integrityStore.errorMessage == nil,
                        canCopyLastHash: integrityStore.snapshot?.verification.lastHash != nil,
                        exportProofBundle: exportProofBundle,
                        revealLedger: revealLedger,
                        copyLastHash: copyLastHash
                    )
                }
                .padding(18)
            }
        }
        .frame(width: 620)
        .frame(minHeight: 430)
        .background(MacAlarmBackground())
        .task {
            if integrityStore.snapshot == nil {
                integrityStore.refresh()
            }
        }
    }

    private func revealLedger() {
        let path = integrityStore.snapshot?.ledgerPath ?? ledgerPath
        let url = URL(fileURLWithPath: path)
        Task {
            let target = await FinderRevealTarget.resolving(
                fileURL: url,
                fallbackDirectory: url.deletingLastPathComponent()
            )
            if !target.openInFinder() {
                MacAlarmAlertPresenter.showInfo(
                    title: "Could Not Open Ledger Location",
                    message: "Finder did not open the ledger location.\n\nPath: \(url.path)"
                )
            }
        }
    }

    private func copyLastHash() {
        guard let hash = integrityStore.snapshot?.verification.lastHash else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hash, forType: .string)
    }
}
