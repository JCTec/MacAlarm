import Foundation

extension LaunchAgentManager {
    static func runProcess(executable: String, arguments: [String]) async -> LaunchAgentCommandResult {
        let result = await Self.runProcessDetached(executable: executable, arguments: arguments)
        let toolName = URL(fileURLWithPath: executable).lastPathComponent
        if result.terminationStatus == 0 {
            MacAlarmLog.launchAgent.debug(
                """
                \(toolName, privacy: .public) \(result.arguments.first ?? "", privacy: .public) \
                exited 0
                """)
        } else {
            MacAlarmLog.launchAgent.error(
                """
                \(toolName, privacy: .public) \(result.arguments.first ?? "", privacy: .public) \
                exited \(result.terminationStatus, privacy: .public): \
                \(String(result.standardError.prefix(200)), privacy: .public)
                """)
        }
        return result
    }

    private static func runProcessDetached(
        executable: String, arguments: [String]
    ) async -> LaunchAgentCommandResult {
        await Task.detached(priority: .utility) {
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                return LaunchAgentCommandResult(
                    executable: executable,
                    arguments: arguments,
                    terminationStatus: process.terminationStatus,
                    standardOutput: String(data: outputData, encoding: .utf8) ?? "",
                    standardError: String(data: errorData, encoding: .utf8) ?? ""
                )
            } catch {
                return LaunchAgentCommandResult(
                    executable: executable,
                    arguments: arguments,
                    terminationStatus: -1,
                    standardOutput: "",
                    standardError: String(describing: error)
                )
            }
        }.value
    }
}
