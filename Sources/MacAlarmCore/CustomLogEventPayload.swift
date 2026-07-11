import Foundation

public struct CustomLogEventPayload: Codable, Equatable, Sendable {
    public static let prefix = "MACALARM_EVENT "

    public var name: String
    public var severity: AlarmSeverity
    public var message: String?
    public var metadata: [String: String]

    public init(
        name: String,
        severity: AlarmSeverity = .notice,
        message: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.name = name
        self.severity = severity
        self.message = message
        self.metadata = metadata
    }

    public func logLine() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        return Self.prefix + String(decoding: data, as: UTF8.self)
    }

    public static func parseLogLine(_ line: String) -> CustomLogEventPayload? {
        guard let prefixRange = line.range(of: prefix) else {
            return nil
        }

        let payloadText = line[prefixRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = payloadText.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(CustomLogEventPayload.self, from: data)
    }
}
