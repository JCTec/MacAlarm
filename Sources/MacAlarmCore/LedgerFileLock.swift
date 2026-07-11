import Foundation

#if canImport(Darwin)
    import Darwin
#endif

public enum LedgerFileReader {
    public static func readDataWithSharedLock(fileURL: URL, fileManager: FileManager = .default) throws -> Data {
        try LedgerFileLock.readDataWithSharedLock(fileURL: fileURL, fileManager: fileManager)
    }
}

enum LedgerFileLock {
    static func readDataWithSharedLock(fileURL: URL, fileManager: FileManager = .default) throws -> Data {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return Data()
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        return try withSharedLock(handle) {
            try handle.readToEnd() ?? Data()
        }
    }

    static func withExclusiveLock<T>(_ handle: FileHandle, _ body: () throws -> T) throws -> T {
        try withLock(handle, operation: LOCK_EX, body)
    }

    static func withSharedLock<T>(_ handle: FileHandle, _ body: () throws -> T) throws -> T {
        try withLock(handle, operation: LOCK_SH, body)
    }

    private static func withLock<T>(_ handle: FileHandle, operation: Int32, _ body: () throws -> T) throws -> T {
        #if canImport(Darwin)
            if flock(handle.fileDescriptor, operation) != 0 {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            defer { flock(handle.fileDescriptor, LOCK_UN) }
        #endif

        return try body()
    }
}
