import Foundation
import MacAlarmCore

struct ExportProofCommand {
    private let arguments: [String]

    init(arguments: [String]) {
        self.arguments = arguments
    }

    func run() async throws -> Never {
        guard let outputPath = optionValue("--output") else {
            throw MacAlarmError.invalidConfiguration("export-proof requires --output DIR")
        }

        let config = try loadConfig()
        let outputURL = URL(fileURLWithPath: outputPath)
        let bundle = try await Task.detached(priority: .userInitiated) {
            let secretStore = FileSecretStore.installedStore(for: config)
            let hmacKey = try AgentFactory.hmacKey(for: config, secretStore: secretStore)
            let exporter = try LedgerProofExporter(
                ledgerURL: PathResolver.fileURL(config.storage.ledgerPath),
                hmacKey: hmacKey
            )
            return try exporter.exportProofBundle(to: outputURL)
        }.value

        printJSON(bundle)
        Foundation.exit(bundle.verification.isValid ? 0 : 3)
    }

    private func loadConfig() throws -> MacAlarmConfig {
        guard let configPath = optionValue("--config") else {
            return MacAlarmConfig()
        }

        return try MacAlarmConfig.load(from: URL(fileURLWithPath: configPath))
    }

    private func optionValue(_ option: String) -> String? {
        guard let index = arguments.firstIndex(of: option) else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            return nil
        }
        return arguments[valueIndex]
    }

    private func printJSON<T: Encodable>(_ value: T) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(value)
            print(String(decoding: data, as: UTF8.self))
        } catch {
            print("{\"encodingError\":\"\(error)\"}")
        }
    }
}
