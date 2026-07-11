import AppKit
import Foundation

enum FinderRevealTarget: Equatable, Sendable {
    case select(URL)
    case open(URL)

    static func preparedDirectory(_ directoryURL: URL) async throws -> FinderRevealTarget {
        try await MacAlarmBackgroundTask.throwing(priority: .utility) {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            return .open(directoryURL)
        }
    }

    static func resolving(fileURL: URL, fallbackDirectory: URL) async -> FinderRevealTarget {
        await MacAlarmBackgroundTask.value(priority: .utility) {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return .select(fileURL)
            }

            try? FileManager.default.createDirectory(at: fallbackDirectory, withIntermediateDirectories: true)
            return .open(fallbackDirectory)
        }
    }

    @MainActor
    @discardableResult
    func openInFinder() -> Bool {
        switch self {
        case .select(let url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return true
        case .open(let url):
            return NSWorkspace.shared.open(url)
        }
    }
}
