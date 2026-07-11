import Foundation

#if canImport(Darwin)
    import Darwin
#endif

extension LaunchAgentManager {
    public static func archiveDevelopmentFallbackLedgerIfNeeded(
        config: MacAlarmConfig,
        activeHMACKey: Data,
        now: Date = .now
    ) async throws -> URL? {
        let ledgerURL = PathResolver.fileURL(config.storage.ledgerPath)

        guard try await ledgerExistsWithRecords(at: ledgerURL) else {
            return nil
        }

        let activeLedger = try HashChainLedger(fileURL: ledgerURL, hmacKey: activeHMACKey)
        let activeVerification = try await activeLedger.verify()
        guard !activeVerification.isValid else {
            return nil
        }

        let developmentLedger = try HashChainLedger(
            fileURL: ledgerURL,
            hmacKey: SecretMaterial.developmentHMACKey(identity: config.identity)
        )
        let developmentVerification = try await developmentLedger.verify()
        guard developmentVerification.isValid, developmentVerification.recordCount > 0 else {
            return nil
        }

        return try await archiveLedger(ledgerURL: ledgerURL, now: now)
    }

    private static func ledgerExistsWithRecords(at url: URL) async throws -> Bool {
        try await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path) else {
                return false
            }

            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = attributes[.size] as? NSNumber
            return (size?.intValue ?? 0) > 0
        }.value
    }

    private static func archiveLedger(ledgerURL: URL, now: Date) async throws -> URL {
        try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let parent = ledgerURL.deletingLastPathComponent()
            let archiveDirectory = parent.appendingPathComponent("archives", isDirectory: true)
            try fileManager.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)

            let destination = uniqueArchiveURL(
                for: ledgerURL,
                archiveDirectory: archiveDirectory,
                now: now,
                fileManager: fileManager
            )

            let handle = try FileHandle(forUpdating: ledgerURL)
            defer { try? handle.close() }

            return try LedgerFileLock.withExclusiveLock(handle) {
                try fileManager.moveItem(at: ledgerURL, to: destination)
                fileManager.createFile(atPath: ledgerURL.path, contents: nil)
                chmod(ledgerURL.path, S_IRUSR | S_IWUSR)
                return destination
            }
        }.value
    }

    static func uniqueArchiveURL(
        for ledgerURL: URL,
        archiveDirectory: URL,
        now: Date,
        fileManager: FileManager
    ) -> URL {
        let stamp = archiveTimestampFormatter.string(from: now)
        let baseName = ledgerURL.lastPathComponent
        let name = "\(baseName).development-fallback-\(stamp)"
        var candidate = archiveDirectory.appendingPathComponent(name)
        var suffix = 2

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = archiveDirectory.appendingPathComponent("\(name)-\(suffix)")
            suffix += 1
        }

        return candidate
    }

    private static let archiveTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }()
}
