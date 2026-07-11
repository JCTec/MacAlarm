import Foundation

struct ProcessExecution: Codable, Sendable {
    var executable: String
    var arguments: [String]
    var terminationStatus: Int32
    var standardOutput: String
    var standardError: String

    static func run(executable: String, arguments: [String]) async -> ProcessExecution {
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
                return ProcessExecution(
                    executable: executable,
                    arguments: arguments,
                    terminationStatus: process.terminationStatus,
                    standardOutput: String(data: outputData, encoding: .utf8) ?? "",
                    standardError: String(data: errorData, encoding: .utf8) ?? ""
                )
            } catch {
                return ProcessExecution(
                    executable: executable,
                    arguments: arguments,
                    terminationStatus: -1,
                    standardOutput: "",
                    standardError: String(describing: error)
                )
            }
        }.value
    }

    var summary: String {
        let text =
            standardError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? standardOutput
            : standardError
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "\(executable) exited \(terminationStatus)" : trimmed
    }
}
