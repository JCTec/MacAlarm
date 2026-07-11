import SwiftUI

struct LedgerIntegrityActionRow: View {
    let canExportProof: Bool
    let canCopyLastHash: Bool
    let exportProofBundle: () -> Void
    let revealLedger: () -> Void
    let copyLastHash: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Button("Export Proof...") {
                exportProofBundle()
            }
            .disabled(!canExportProof)
            Button("Reveal Ledger") {
                revealLedger()
            }
            Button("Copy Last Hash") {
                copyLastHash()
            }
            .disabled(!canCopyLastHash)

            Spacer()
        }
        .buttonStyle(.bordered)
    }
}
