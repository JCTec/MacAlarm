import AppKit
import Foundation
import MacAlarmCore

extension MacAlarmApplicationDelegate {
    @objc func exportProofBundle(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.title = "Export MacAlarm Proof Bundle"
        panel.message = "Choose where MacAlarm should write the protected proof directory."
        panel.prompt = "Export"
        panel.nameFieldStringValue = defaultProofBundleName()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self, panel] response in
            let destinationURL = panel.url
            let didConfirm = response == .OK
            Task { @MainActor [weak self] in
                guard didConfirm, let destinationURL else {
                    return
                }
                self?.runProofExport(to: destinationURL)
            }
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    private func runProofExport(to destinationURL: URL) {
        let proofService = MacAlarmProofService(launchAgentLabel: launchAgentLabel)
        Task {
            do {
                let bundle = try await proofService.exportProofBundle(to: destinationURL)

                let result = proofExportMessage(bundle)
                showInfo(title: result.title, message: result.message)
                let target = await FinderRevealTarget.resolving(
                    fileURL: URL(fileURLWithPath: bundle.summaryPath),
                    fallbackDirectory: URL(fileURLWithPath: bundle.proofDirectoryPath, isDirectory: true)
                )
                if !target.openInFinder() {
                    showInfo(
                        title: "Proof Bundle Exported",
                        message: "MacAlarm wrote the proof bundle, but Finder did not open it.\n\nDestination: \(bundle.proofDirectoryPath)"
                    )
                }
            } catch {
                showError(title: "Proof Export Failed", error: error)
            }
        }
    }

    private func proofExportMessage(_ bundle: LedgerProofBundle) -> (title: String, message: String) {
        let title = bundle.verification.isValid ? "Proof Bundle Exported" : "Proof Bundle Exported With Issues"
        let message = [
            "Destination: \(bundle.proofDirectoryPath)",
            "Records: \(bundle.verification.recordCount)",
            "Valid: \(bundle.verification.isValid ? "yes" : "no")",
            "Last hash: \(bundle.verification.lastHash)",
        ].joined(separator: "\n")

        return (title, message)
    }

    private func defaultProofBundleName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "MacAlarm-Proof-\(formatter.string(from: Date()))"
    }
}
