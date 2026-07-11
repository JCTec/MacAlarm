import Foundation

extension LaunchAgentManager {
    static func runProcess(executable: String, arguments: [String]) async -> LaunchAgentCommandResult {
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
