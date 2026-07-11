import Foundation

public enum MacAlarmError: Error, Equatable, LocalizedError, Sendable {
    case invalidHexString
    case emptyHMACKey
    case ledgerRecordHashMismatch(line: Int)
    case ledgerPreviousHashMismatch(line: Int)
    case fileDescriptorOpenFailed(path: String, errno: Int32)
    case unsupportedLogStoreScope(String)
    case randomGenerationFailed(status: OSStatus)
    case missingHMACKey(account: String)
    case readOnlySecretStore
    case invalidConfiguration(String)

    public var errorDescription: String? {
        switch self {
        case .invalidHexString:
            "Invalid hexadecimal string."
        case .emptyHMACKey:
            "HMAC key must not be empty."
        case .ledgerRecordHashMismatch(let line):
            "Ledger record hash mismatch at line \(line)."
        case .ledgerPreviousHashMismatch(let line):
            "Ledger previous hash mismatch at line \(line)."
        case .fileDescriptorOpenFailed(let path, let errno):
            "Could not open \(path) for file-system monitoring. errno=\(errno)."
        case .unsupportedLogStoreScope(let scope):
            "Unsupported OSLogStore scope: \(scope)."
        case .randomGenerationFailed(let status):
            "Secure random byte generation failed with status \(status)."
        case .missingHMACKey(let account):
            "Missing HMAC key in secret account \(account)."
        case .readOnlySecretStore:
            "Secret store is read-only."
        case .invalidConfiguration(let message):
            "Invalid configuration: \(message)"
        }
    }
}
