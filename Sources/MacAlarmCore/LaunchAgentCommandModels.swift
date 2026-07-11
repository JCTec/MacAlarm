import Foundation

public struct LaunchAgentCommandResult: Codable, Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var terminationStatus: Int32
    public var standardOutput: String
    public var standardError: String

    public init(
        executable: String,
        arguments: [String],
        terminationStatus: Int32,
        standardOutput: String,
        standardError: String
    ) {
        self.executable = executable
        self.arguments = arguments
        self.terminationStatus = terminationStatus
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var succeeded: Bool {
        terminationStatus == 0
    }

    public var summary: String {
        let text =
            standardError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? standardOutput
            : standardError
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "\(executable) exited \(terminationStatus)" : trimmed
    }
}

public struct LaunchAgentServiceStatus: Codable, Equatable, Sendable {
    public var label: String
    public var service: String
    public var plistPath: String
    public var isLoaded: Bool
    public var state: String?
    public var processID: Int32?
    public var result: LaunchAgentCommandResult
}
