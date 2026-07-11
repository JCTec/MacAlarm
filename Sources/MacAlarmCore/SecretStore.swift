import Foundation
import Security

#if canImport(Darwin)
    import Darwin
#endif

public protocol SecretStore: Sendable {
    func readSecret(account: String) throws -> Data?
    func writeSecret(_ secret: Data, account: String) throws
    func deleteSecret(account: String) throws
}

public struct StaticSecretStore: SecretStore {
    private let values: [String: Data]

    public init(values: [String: Data]) {
        self.values = values
    }

    public func readSecret(account: String) throws -> Data? {
        values[account]
    }

    public func writeSecret(_ secret: Data, account: String) throws {
        throw MacAlarmError.readOnlySecretStore
    }

    public func deleteSecret(account: String) throws {
        throw MacAlarmError.readOnlySecretStore
    }
}

public final class FileSecretStore: SecretStore {
    private let directory: URL
    private static let maximumSecretFileNameLength = 255

    public init(directory: URL) {
        self.directory = directory
    }

    public static func installedStore(for config: MacAlarmConfig) -> FileSecretStore {
        FileSecretStore(directory: installedSecretDirectory(for: config))
    }

    public static func installedSecretDirectory(for config: MacAlarmConfig) -> URL {
        PathResolver.fileURL(config.storage.ledgerPath)
            .deletingLastPathComponent()
            .appendingPathComponent("secrets", isDirectory: true)
    }

    public static func fileName(forAccount account: String) throws -> String {
        guard !account.isEmpty else {
            throw MacAlarmError.invalidConfiguration("secret account must not be empty")
        }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard let fileName = account.addingPercentEncoding(withAllowedCharacters: allowed),
            !fileName.isEmpty
        else {
            throw MacAlarmError.invalidConfiguration("secret account is not file-name encodable: \(account)")
        }

        guard fileName != "." && fileName != ".." else {
            throw MacAlarmError.invalidConfiguration("secret account must not resolve to \(fileName)")
        }

        guard !fileName.contains("/") else {
            throw MacAlarmError.invalidConfiguration("secret account must not contain path separators")
        }

        guard fileName.utf8.count <= maximumSecretFileNameLength else {
            throw MacAlarmError.invalidConfiguration(
                "secret account file name is longer than \(maximumSecretFileNameLength) bytes")
        }

        return fileName
    }

    public func readSecret(account: String) throws -> Data? {
        let url = try secretURL(account: account)
        guard try validateExistingDirectoryIfPresent() else {
            return nil
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        try validateSecretFileForRead(at: url)
        return try Data(contentsOf: url)
    }

    public func writeSecret(_ secret: Data, account: String) throws {
        let url = try secretURL(account: account)
        try prepareDirectoryForWrite()
        try validateSecretFileForWrite(at: url)
        try secret.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func deleteSecret(account: String) throws {
        let url = try secretURL(account: account)
        guard try validateExistingDirectoryIfPresent() else {
            return
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        try validateSecretFileForWrite(at: url)
        try FileManager.default.removeItem(at: url)
    }

    private func secretURL(account: String) throws -> URL {
        try directory.appendingPathComponent(Self.fileName(forAccount: account), isDirectory: false)
    }

    private func validateExistingDirectoryIfPresent() throws -> Bool {
        guard let state = try Self.pathState(at: directory) else {
            return false
        }

        try Self.validateSecretDirectoryState(state, at: directory)
        return true
    }

    private func prepareDirectoryForWrite() throws {
        if let state = try Self.pathState(at: directory) {
            try Self.validateSecretDirectoryState(state, at: directory, allowRepairablePermissions: true)
        } else {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private func validateSecretFileForRead(at url: URL) throws {
        guard let state = try Self.pathState(at: url) else {
            throw MacAlarmError.invalidConfiguration("secret file disappeared while reading: \(url.path)")
        }

        guard state.kind == .regularFile else {
            throw MacAlarmError.invalidConfiguration("secret path is not a regular file: \(url.path)")
        }

        guard state.permissions == 0o600 else {
            throw MacAlarmError.invalidConfiguration(
                "secret file must be mode 0600, got \(String(state.permissions, radix: 8)): \(url.path)"
            )
        }
    }

    private func validateSecretFileForWrite(at url: URL) throws {
        guard let state = try Self.pathState(at: url) else {
            return
        }

        guard state.kind == .regularFile else {
            throw MacAlarmError.invalidConfiguration("secret path is not a regular file: \(url.path)")
        }
    }

    private static func validateSecretDirectoryState(
        _ state: PathState,
        at url: URL,
        allowRepairablePermissions: Bool = false
    ) throws {
        guard state.kind == .directory else {
            throw MacAlarmError.invalidConfiguration("secret directory path is not a directory: \(url.path)")
        }

        guard allowRepairablePermissions || state.permissions == 0o700 else {
            throw MacAlarmError.invalidConfiguration(
                "secret directory must be mode 0700, got \(String(state.permissions, radix: 8)): \(url.path)"
            )
        }
    }

    private static func pathState(at url: URL) throws -> PathState? {
        #if canImport(Darwin)
            var info = stat()
            guard lstat(url.path, &info) == 0 else {
                if errno == ENOENT {
                    return nil
                }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }

            let fileType = info.st_mode & S_IFMT
            let kind: PathKind =
                if fileType == S_IFREG {
                    .regularFile
                } else if fileType == S_IFDIR {
                    .directory
                } else if fileType == S_IFLNK {
                    .symbolicLink
                } else {
                    .other
                }

            return PathState(kind: kind, permissions: Int(info.st_mode & 0o777))
        #else
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                return nil
            }

            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
            return PathState(kind: isDirectory.boolValue ? .directory : .regularFile, permissions: permissions)
        #endif
    }

    private struct PathState {
        var kind: PathKind
        var permissions: Int
    }

    private enum PathKind {
        case regularFile
        case directory
        case symbolicLink
        case other
    }
}

public enum SecretMaterial {
    public typealias RandomByteProvider = @Sendable (_ byteCount: Int) throws -> Data

    public static func developmentHMACKey(identity: AgentIdentity) -> Data {
        Data("macalarm-development-hmac-key:\(identity.deviceID)".utf8)
    }

    public static func randomKey(
        byteCount: Int = 32,
        using provider: RandomByteProvider = secureRandomBytes(byteCount:)
    ) throws -> Data {
        guard byteCount > 0 else {
            throw MacAlarmError.invalidConfiguration("random key byteCount must be greater than zero")
        }

        let key = try provider(byteCount)
        guard key.count == byteCount else {
            throw MacAlarmError.invalidConfiguration(
                "random key provider returned \(key.count) bytes, expected \(byteCount)")
        }

        return key
    }

    public static func secureRandomBytes(byteCount: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw MacAlarmError.randomGenerationFailed(status: status)
        }
        return Data(bytes)
    }
}
