import Foundation
import MacAlarmCore

#if canImport(Darwin)
    import Darwin
#endif

@main
struct MacAlarmAgentCommand {
    @MainActor
    static func main() async {
        do {
            let arguments = AgentArguments(CommandLine.arguments.dropFirst())

            if arguments.help {
                print(Self.helpText)
                return
            }

            if arguments.printDefaultConfig {
                print(String(decoding: try MacAlarmConfig().prettyPrintedJSON(), as: UTF8.self))
                return
            }

            try Self.redirectInstalledLaunchLogsIfNeeded(arguments)

            let config = try Self.loadConfig(path: arguments.configPath)
            let validation = ConfigValidator.validate(config)
            MacAlarmLog.agent.info(
                """
                Config loaded (explicit=\(arguments.configPath != nil, privacy: .public), \
                valid=\(validation.isValid, privacy: .public), \
                issues=\(validation.issues.count, privacy: .public))
                """)
            guard validation.isValid else {
                MacAlarmLog.agent.error("Config validation failed; exiting")
                printJSON(validation)
                Foundation.exit(2)
            }

            let hmacKey = try await AgentFactory.hmacKeyOffMain(
                for: config,
                secretStore: FileSecretStore.installedStore(for: config)
            )
            MacAlarmLog.agent.debug("HMAC key loaded (\(hmacKey.count, privacy: .public) bytes)")
            let runtime = try MacAlarmAgentRuntime(config: config, hmacKey: hmacKey)

            if arguments.verifyLedger {
                let verification = try await runtime.verifyLedger()
                MacAlarmLog.ledger.info(
                    """
                    Verify-ledger requested: valid=\(verification.isValid, privacy: .public), \
                    records=\(verification.recordCount, privacy: .public)
                    """)
                printJSON(verification)
                Foundation.exit(verification.isValid ? 0 : 3)
            }

            try await runtime.run(duration: arguments.duration)
        } catch {
            MacAlarmLog.agent.error("Agent exiting on error: \(String(describing: error), privacy: .public)")
            fputs("macalarm-agent error: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func printJSON<T: Encodable>(_ value: T) {
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

    private static func loadConfig(path: String?) throws -> MacAlarmConfig {
        if let path {
            return try MacAlarmConfig.load(from: URL(fileURLWithPath: path))
        }

        let installedURL = MacAlarmInstallationPaths().configURL
        if FileManager.default.fileExists(atPath: installedURL.path) {
            return try MacAlarmConfig.load(from: installedURL)
        }

        return MacAlarmConfig()
    }

    private static func redirectInstalledLaunchLogsIfNeeded(_ arguments: AgentArguments) throws {
        guard arguments.shouldRedirectInstalledLaunchLogs else {
            return
        }

        #if canImport(Darwin)
            let paths = MacAlarmInstallationPaths()
            try FileManager.default.createDirectory(at: paths.logDirectory, withIntermediateDirectories: true)
            try redirectStandardDescriptor(STDOUT_FILENO, to: paths.standardOutputURL)
            try redirectStandardDescriptor(STDERR_FILENO, to: paths.standardErrorURL)
        #endif
    }

    #if canImport(Darwin)
        private static func redirectStandardDescriptor(_ descriptor: Int32, to url: URL) throws {
            let fileDescriptor = open(url.path, O_WRONLY | O_CREAT | O_APPEND, S_IRUSR | S_IWUSR)
            guard fileDescriptor >= 0 else {
                throw MacAlarmError.fileDescriptorOpenFailed(path: url.path, errno: errno)
            }
            defer {
                close(fileDescriptor)
            }

            guard dup2(fileDescriptor, descriptor) >= 0 else {
                throw MacAlarmError.fileDescriptorOpenFailed(path: url.path, errno: errno)
            }
        }
    #endif

    private static let helpText = """
        macalarm-agent

        Long-running local macOS alarm agent.

        Usage:
          macalarm-agent --config /path/to/config.json
          macalarm-agent --config /path/to/config.json --duration 60
          macalarm-agent --print-default-config
          macalarm-agent --config /path/to/config.json --verify-ledger

        Flags:
          --config PATH              Load JSON config. Defaults to the installed MacAlarm config when present.
          --duration SECONDS         Run for a bounded duration, useful for testing.
          --verify-ledger            Verify configured ledger and exit.
          --print-default-config     Print default JSON config.
          --help                     Show help.
        """
}

private struct AgentArguments {
    var configPath: String?
    var duration: TimeInterval?
    var help = false
    var printDefaultConfig = false
    var verifyLedger = false

    init(_ arguments: ArraySlice<String>) {
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--help", "-h":
                help = true
            case "--config":
                configPath = iterator.next()
            case "--duration":
                if let value = iterator.next() {
                    duration = TimeInterval(value)
                }
            case "--print-default-config":
                printDefaultConfig = true
            case "--verify-ledger":
                verifyLedger = true
            default:
                continue
            }
        }
    }

    var shouldRedirectInstalledLaunchLogs: Bool {
        configPath == nil
            && duration == nil
            && !help
            && !printDefaultConfig
            && !verifyLedger
    }
}
