import Foundation
import MacAlarmCore

enum AgentControlCommand {
    static func run(command: String, arguments: [String]) async throws -> Never {
        let manager = LaunchAgentManager()
        let results: [LaunchAgentCommandResult]

        switch command {
        case "agent-status":
            let status = await manager.status()
            if arguments.contains("--json") {
                printJSON(status)
            } else {
                printStatus(status)
            }
            Foundation.exit(status.isLoaded ? 0 : 3)

        case "agent-install":
            results = try await manager.install(
                agentPath: optionValue("--agent-path", in: arguments),
                configPath: optionValue("--config", in: arguments)
            )
            printResults("installed", results)
            Foundation.exit(0)

        case "agent-start":
            results = try await manager.start()
            printResults("started", results)
            Foundation.exit(0)

        case "agent-stop":
            results = await manager.stop()
            printResults("stopped", results)
            Foundation.exit(0)

        case "agent-restart":
            results = try await manager.restart()
            printResults("restarted", results)
            Foundation.exit(0)

        case "agent-uninstall":
            results = try await manager.uninstall()
            printResults("uninstalled", results)
            Foundation.exit(0)

        default:
            throw MacAlarmError.invalidConfiguration("unsupported agent command: \(command)")
        }
    }

    private static func printStatus(_ status: LaunchAgentServiceStatus) {
        print("MacAlarm LaunchAgent")
        print("Status: \(status.isLoaded ? "loaded" : "not loaded")")
        print("Service: \(status.service)")
        print("Plist: \(status.plistPath)")
        if let state = status.state {
            print("State: \(state)")
        }
        if let processID = status.processID {
            print("PID: \(processID)")
        }
        if !status.isLoaded {
            print("Detail: \(status.result.summary)")
        }
    }

    private static func printResults(_ action: String, _ results: [LaunchAgentCommandResult]) {
        print("MacAlarm LaunchAgent \(action).")
        for result in results {
            let command = ([result.executable] + result.arguments).joined(separator: " ")
            print("[\(result.succeeded ? "OK" : "FAIL")] \(command)")
            if !result.summary.isEmpty {
                print(result.summary)
            }
        }
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
}
