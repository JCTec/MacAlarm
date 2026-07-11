import Foundation

extension LaunchAgentManager {
    static func firstValue(after prefix: String, in output: String) -> String? {
        output
            .split(separator: "\n")
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix(prefix) else {
                    return nil
                }
                return trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            }
            .first
    }

    static func processID(in output: String) -> Int32? {
        guard let text = firstValue(after: "pid =", in: output) else {
            return nil
        }
        return Int32(text)
    }
}
