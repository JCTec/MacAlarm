import Foundation
import MacAlarmCore

enum MacAlarmProofServiceError: LocalizedError, Sendable {
    case missingSecret(account: String)

    var errorDescription: String? {
        switch self {
        case .missingSecret(let account):
            """
            MacAlarm cannot verify or export the ledger because the installed ledger HMAC key is missing.

            Install or start the recorder from Recorder > Install Recorder at Login... so MacAlarm can create the local secret account: \(account)
            """
        }
    }
}

struct MacAlarmProofService: Sendable {
    var launchAgentLabel: String

    func inspectLedger() async throws -> LedgerIntegritySnapshot {
        let launchAgentLabel = launchAgentLabel
        return try await MacAlarmBackgroundTask.throwing(priority: .userInitiated) {
            let context = try Self.proofContext(launchAgentLabel: launchAgentLabel)
            let exporter = try LedgerProofExporter(ledgerURL: context.ledgerURL, hmacKey: context.hmacKey)
            return try exporter.inspectLedger()
        }
    }

    func exportProofBundle(to destinationURL: URL) async throws -> LedgerProofBundle {
        let launchAgentLabel = launchAgentLabel
        return try await MacAlarmBackgroundTask.throwing(priority: .userInitiated) {
            let context = try Self.proofContext(launchAgentLabel: launchAgentLabel)
            let exporter = try LedgerProofExporter(ledgerURL: context.ledgerURL, hmacKey: context.hmacKey)
            return try exporter.exportProofBundle(to: destinationURL)
        }
    }

    private static func proofContext(launchAgentLabel: String) throws -> ProofContext {
        let paths = MacAlarmInstallationPaths(label: launchAgentLabel)
        let config =
            if FileManager.default.fileExists(atPath: paths.configURL.path) {
                try MacAlarmConfig.load(from: paths.configURL)
            } else {
                MacAlarmConfig()
            }
        let secretStore = FileSecretStore.installedStore(for: config)
        guard let hmacKey = try secretStore.readSecret(account: config.secrets.hmacKeyAccount) else {
            throw MacAlarmProofServiceError.missingSecret(account: config.secrets.hmacKeyAccount)
        }
        return ProofContext(
            ledgerURL: PathResolver.fileURL(config.storage.ledgerPath),
            hmacKey: hmacKey
        )
    }
}

private struct ProofContext: Sendable {
    var ledgerURL: URL
    var hmacKey: Data
}
