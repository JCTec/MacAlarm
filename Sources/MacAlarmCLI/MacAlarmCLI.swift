import Foundation
import MacAlarmCLIKit
import MacAlarmCore
import OSLog

@main
struct MacAlarmCLI {
    @MainActor
    static func main() async {
        do {
            var arguments = Array(CommandLine.arguments.dropFirst())
            guard let command = arguments.first else {
                print(Self.helpText)
                return
            }
            arguments.removeFirst()

            switch command {
            case "default-config":
                try defaultConfig(arguments)
            case "validate-config":
                try validateConfig(arguments)
            case "verify-ledger":
                try await verifyLedger(arguments)
            case "export-proof":
                try await ExportProofCommand(arguments: arguments).run()
            case "init-secret":
                try initSecret(arguments)
            case "launch-agent-plist":
                try launchAgentPlist(arguments)
            case "agent-status", "agent-install", "agent-start", "agent-stop", "agent-restart", "agent-uninstall":
                try await AgentControlCommand.run(command: command, arguments: arguments)
            case "status":
                try await StatusCommand(arguments: arguments).run()
            case "health":
                try await HealthCommand(arguments: arguments).run()
            case "doctor":
                try await DoctorCommand(arguments: arguments).run()
            case "notification-status":
                await notificationStatus(arguments)
            case "test-notification":
                try await testNotification(arguments)
            case "emit-log":
                try emitLog(arguments)
            case "telegram-set-token":
                try telegramSetToken(arguments)
            case "telegram-pending":
                try await telegramPending(arguments)
            case "telegram-approve":
                try await telegramApprove(arguments, denied: false)
            case "telegram-deny":
                try await telegramApprove(arguments, denied: true)
            case "telegram-test":
                try await telegramTest(arguments)
            case "help", "--help", "-h":
                print(Self.helpText)
            default:
                fputs("Unknown command: \(command)\n\n\(Self.helpText)\n", stderr)
                Foundation.exit(2)
            }
        } catch {
            fputs("macalarmctl error: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func defaultConfig(_ arguments: [String]) throws {
        let config = MacAlarmConfig()
        if let outputPath = optionValue("--output", in: arguments) {
            try config.write(to: URL(fileURLWithPath: outputPath))
            print("Wrote \(outputPath)")
        } else {
            print(String(decoding: try config.prettyPrintedJSON(), as: UTF8.self))
        }
    }

    private static func validateConfig(_ arguments: [String]) throws {
        let config = try loadRequiredConfig(arguments)
        printJSON(ConfigValidator.validate(config))
    }

    @MainActor
    private static func verifyLedger(_ arguments: [String]) async throws {
        let config = try loadRequiredConfig(arguments)
        let hmacKey = try await AgentFactory.hmacKeyOffMain(
            for: config,
            secretStore: FileSecretStore.installedStore(for: config)
        )
        let runtime = try MacAlarmAgentRuntime(config: config, hmacKey: hmacKey)
        let verification = try await runtime.verifyLedger()
        printJSON(verification)
        Foundation.exit(verification.isValid ? 0 : 3)
    }

    private static func initSecret(_ arguments: [String]) throws {
        let config = try loadRequiredConfig(arguments)
        let store = FileSecretStore.installedStore(for: config)
        let key = try SecretMaterial.randomKey()
        try store.writeSecret(key, account: config.secrets.hmacKeyAccount)
        print(
            "Stored random HMAC key in \(FileSecretStore.installedSecretDirectory(for: config).path) account=\(config.secrets.hmacKeyAccount)"
        )
    }

    private static func launchAgentPlist(_ arguments: [String]) throws {
        guard let configPath = optionValue("--config", in: arguments) else {
            throw MacAlarmError.invalidConfiguration("launch-agent-plist requires --config")
        }
        guard let agentPath = optionValue("--agent-path", in: arguments) else {
            throw MacAlarmError.invalidConfiguration("launch-agent-plist requires --agent-path")
        }

        let plist = LaunchAgentPlist(executablePath: agentPath, configPath: configPath)
        if let outputPath = optionValue("--output", in: arguments) {
            let outputURL = URL(fileURLWithPath: outputPath)
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try plist.xmlString().write(to: outputURL, atomically: true, encoding: .utf8)
            print("Wrote \(outputPath)")
        } else {
            print(plist.xmlString())
        }
    }

    private static func notificationStatus(_ arguments: [String]) async {
        let config = (try? loadOptionalConfig(arguments)) ?? MacAlarmConfig()
        let notifier = ResilientLocalNotifier(
            soundEnabled: config.notifications.sound,
            useAppleScriptFallback: config.notifications.appleScriptFallback
        )
        let snapshot = await notifier.authorizationSnapshot()
        printJSON(snapshot)
    }

    private static func testNotification(_ arguments: [String]) async throws {
        let config = (try? loadOptionalConfig(arguments)) ?? MacAlarmConfig()
        let message = optionValue("--message", in: arguments) ?? "MacAlarm notification test"
        let hmacKey = try await AgentFactory.hmacKeyOffMain(
            for: config,
            secretStore: FileSecretStore.installedStore(for: config)
        )
        let runner = try NotificationTestRunner(
            config: config,
            hmacKey: hmacKey
        )
        let result = try await runner.run(
            message: message,
            origin: "macalarmctl test-notification"
        )
        printJSON(result)
    }

    private static func emitLog(_ arguments: [String]) throws {
        let name = try requiredOption("--name", in: arguments)
        let severity = try AlarmSeverity(argument: optionValue("--severity", in: arguments) ?? "notice")
        let subsystem = optionValue("--subsystem", in: arguments) ?? "dev.jc.macalarm.custom"
        let category = optionValue("--category", in: arguments) ?? "event"
        let message = optionValue("--message", in: arguments)
        let metadata = try metadataValues(from: optionValues("--metadata", in: arguments))
        let payload = CustomLogEventPayload(name: name, severity: severity, message: message, metadata: metadata)
        let logLine = try payload.logLine()

        os_log("%{public}@", log: OSLog(subsystem: subsystem, category: category), type: severity.osLogType, logLine)

        printJSON(
            CustomLogEmission(
                subsystem: subsystem,
                category: category,
                name: name,
                severity: severity,
                message: message,
                metadata: metadata
            )
        )
    }

    private static func telegramSetToken(_ arguments: [String]) throws {
        let config = try loadRequiredConfig(arguments)
        let token =
            if let token = optionValue("--token", in: arguments) {
                token
            } else if arguments.contains("--token-stdin") {
                String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
            } else {
                throw MacAlarmError.invalidConfiguration("telegram-set-token requires --token TEXT or --token-stdin")
            }
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw MacAlarmError.invalidConfiguration("telegram token must not be empty")
        }

        try FileSecretStore.installedStore(for: config).writeSecret(
            Data(normalized.utf8),
            account: config.telegram.botTokenAccount
        )
        print(
            "Stored Telegram bot token in \(FileSecretStore.installedSecretDirectory(for: config).path) account=\(config.telegram.botTokenAccount)"
        )
    }

    private static func telegramPending(_ arguments: [String]) async throws {
        let config = try loadRequiredConfig(arguments)
        let pending = try await PendingTelegramChatStore.installedStore(config: config).load()
        printJSON(pending)
    }

    private static func telegramApprove(_ arguments: [String], denied: Bool) async throws {
        let configPath = try requiredOption("--config", in: arguments)
        var config = try MacAlarmConfig.load(from: URL(fileURLWithPath: configPath))
        let chatID =
            try Int64(requiredOption("--chat-id", in: arguments))
            ?? { throw MacAlarmError.invalidConfiguration("--chat-id must be an integer") }()

        if denied {
            config.telegram.deniedChatIDs.appendUnique(chatID)
            config.telegram.approvedChatIDs.removeAll { $0 == chatID }
        } else {
            config.telegram.approvedChatIDs.appendUnique(chatID)
            config.telegram.deniedChatIDs.removeAll { $0 == chatID }
        }

        try config.write(to: URL(fileURLWithPath: configPath))
        try await PendingTelegramChatStore.installedStore(config: config).remove(chatID: chatID)
        print("\(denied ? "Denied" : "Approved") Telegram chat \(chatID)")
    }

    private static func telegramTest(_ arguments: [String]) async throws {
        let config = try loadRequiredConfig(arguments)
        guard config.telegram.enabled else {
            throw MacAlarmError.invalidConfiguration("telegram.enabled is false")
        }
        guard
            let tokenData = try FileSecretStore.installedStore(for: config)
                .readSecret(account: config.telegram.botTokenAccount),
            let token = String(data: tokenData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !token.isEmpty
        else {
            throw MacAlarmError.missingHMACKey(account: config.telegram.botTokenAccount)
        }

        let chatID =
            if let value = optionValue("--chat-id", in: arguments) {
                try Int64(value) ?? { throw MacAlarmError.invalidConfiguration("--chat-id must be an integer") }()
            } else if let first = config.telegram.approvedChatIDs.first {
                first
            } else {
                throw MacAlarmError.invalidConfiguration("telegram-test needs --chat-id or an approved chat")
            }
        let message = optionValue("--message", in: arguments) ?? "MacAlarm Telegram test"
        try await TelegramClient(token: token).sendMessage(chatID: chatID, text: message)
        print("Sent Telegram test message to \(chatID)")
    }

    private static func loadRequiredConfig(_ arguments: [String]) throws -> MacAlarmConfig {
        guard let path = optionValue("--config", in: arguments) else {
            throw MacAlarmError.invalidConfiguration("missing --config")
        }

        return try MacAlarmConfig.load(from: URL(fileURLWithPath: path))
    }

    private static func loadOptionalConfig(_ arguments: [String]) throws -> MacAlarmConfig? {
        guard let path = optionValue("--config", in: arguments) else {
            return nil
        }

        return try MacAlarmConfig.load(from: URL(fileURLWithPath: path))
    }

    private static func optionValue(_ option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option) else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            return nil
        }
        return arguments[valueIndex]
    }

    private static func optionValues(_ option: String, in arguments: [String]) -> [String] {
        var values = [String]()
        var index = arguments.startIndex

        while index < arguments.endIndex {
            if arguments[index] == option {
                let valueIndex = arguments.index(after: index)
                if valueIndex < arguments.endIndex {
                    values.append(arguments[valueIndex])
                    index = arguments.index(after: valueIndex)
                    continue
                }
            }
            index = arguments.index(after: index)
        }

        return values
    }

    private static func requiredOption(_ option: String, in arguments: [String]) throws -> String {
        guard let value = optionValue(option, in: arguments),
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw MacAlarmError.invalidConfiguration("\(option) is required")
        }

        return value
    }

    private static func metadataValues(from values: [String]) throws -> [String: String] {
        var metadata = [String: String]()
        for value in values {
            let parts = value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty else {
                throw MacAlarmError.invalidConfiguration("metadata must use KEY=VALUE format: \(value)")
            }
            metadata[String(parts[0])] = String(parts[1])
        }
        return metadata
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

    private static let helpText = """
        macalarmctl

        Commands:
          default-config [--output PATH]
          validate-config --config PATH
          verify-ledger --config PATH
          export-proof [--config PATH] --output DIR
          init-secret --config PATH
          launch-agent-plist --config PATH --agent-path PATH [--output PATH]
          agent-status [--json]
          agent-install [--config PATH] [--agent-path PATH]
          agent-start
          agent-stop
          agent-restart
          agent-uninstall
          status [--config PATH]
          health [--config PATH]
          doctor [--config PATH] [--json]
          notification-status [--config PATH]
          test-notification [--config PATH] [--message TEXT]
          emit-log --name NAME [--severity debug|info|notice|warning|critical] [--message TEXT] [--metadata KEY=VALUE] [--subsystem SUBSYSTEM] [--category CATEGORY]
          telegram-set-token --config PATH (--token TEXT | --token-stdin)
          telegram-pending --config PATH
          telegram-approve --config PATH --chat-id ID
          telegram-deny --config PATH --chat-id ID
          telegram-test --config PATH [--chat-id ID] [--message TEXT]

        Notes:
          init-secret stores or rotates a random HMAC key in the installed private secret file.
          export-proof writes events.jsonl, verification.json, summary.txt, and last-hash.txt.
          launch-agent-plist prints or writes a plist, but does not install it.
          agent-install creates an installed private HMAC key if the configured account is missing.
          agent-* commands manage the visible user LaunchAgent without deleting local data.
          status prints cheap machine-readable runtime status JSON.
          health prints a cheap human-readable runtime health summary.
          doctor checks installed binaries, LaunchAgent health, config, notifications, and ledger integrity.
          test-notification uses UserNotifications first, AppleScript fallback if configured, and records the attempt in the ledger.
          emit-log writes a structured custom event to macOS Unified Logging.
          telegram-* commands configure an optional user-owned Telegram bot without storing the bot token in config.json.
        """
}

private extension Array where Element: Equatable {
    mutating func appendUnique(_ element: Element) {
        if !contains(element) {
            append(element)
        }
    }
}

private struct CustomLogEmission: Codable {
    var subsystem: String
    var category: String
    var name: String
    var severity: AlarmSeverity
    var message: String?
    var metadata: [String: String]
}

private extension AlarmSeverity {
    init(argument: String) throws {
        guard let severity = AlarmSeverity(rawValue: argument) else {
            throw MacAlarmError.invalidConfiguration("unsupported severity: \(argument)")
        }
        self = severity
    }

    var osLogType: OSLogType {
        switch self {
        case .debug: .debug
        case .info: .info
        case .notice: .default
        case .warning: .error
        case .critical: .fault
        }
    }
}
