import Foundation
import MacAlarmCore

/// A user-selected folder the viewer app watches, persisted as a security-scoped
/// bookmark so the grant survives relaunch.
public struct WatchedFolderBookmark: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var displayPath: String
    public var bookmark: Data

    public init(id: UUID = UUID(), displayPath: String, bookmark: Data) {
        self.id = id
        self.displayPath = displayPath
        self.bookmark = bookmark
    }
}

/// A resolved watched folder, holding the live URL and whether the app began a
/// security-scoped access session for it (which must be balanced with
/// `stopAccessingSecurityScopedResource`).
public struct ResolvedWatchedFolder: Sendable {
    public var bookmark: WatchedFolderBookmark
    public var url: URL
    public var isStale: Bool
    public var didStartAccess: Bool
}

/// Persists and resolves the user-selected watched folders.
///
/// Bookmarks are app-scoped and security-scoped so the folder grant the user
/// gave through the open panel survives relaunch — the permanent App Store
/// architecture for folder watching. The grant belongs to *this* app process and
/// cannot be handed to the launchd-launched recorder, so folder watching is
/// active only while MacAlarm.app runs (documented honestly in the UI and
/// SANDBOX_BEHAVIOR.md).
///
/// Bookmark creation/resolution options are injectable so tests can exercise the
/// persistence and stale-handling logic with plain (non-security-scoped)
/// bookmarks on an unsandboxed machine.
@MainActor
public final class WatchedFolderBookmarks {
    public static let defaultsKey = "MacAlarm.WatchedFolders"

    private let defaults: UserDefaults
    private let key: String
    private let creationOptions: URL.BookmarkCreationOptions
    private let resolutionOptions: URL.BookmarkResolutionOptions

    public init(
        defaults: UserDefaults = .standard,
        key: String = WatchedFolderBookmarks.defaultsKey,
        creationOptions: URL.BookmarkCreationOptions = [.withSecurityScope],
        resolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
    ) {
        self.defaults = defaults
        self.key = key
        self.creationOptions = creationOptions
        self.resolutionOptions = resolutionOptions
    }

    public func bookmarks() -> [WatchedFolderBookmark] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }
        return (try? JSONDecoder().decode([WatchedFolderBookmark].self, from: data)) ?? []
    }

    /// Creates and persists a bookmark for `url`. If the folder is already
    /// watched (same standardized path) the existing entry is refreshed rather
    /// than duplicated. Returns the stored bookmark.
    @discardableResult
    public func add(url: URL) throws -> WatchedFolderBookmark {
        let bookmarkData = try url.bookmarkData(
            options: creationOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
        let displayPath = url.standardizedFileURL.path

        var stored = bookmarks().filter { $0.displayPath != displayPath }
        let bookmark = WatchedFolderBookmark(displayPath: displayPath, bookmark: bookmarkData)
        stored.append(bookmark)
        persist(stored)
        MacAlarmLog.appShell.info("Watched folder added (\(stored.count, privacy: .public) total)")
        return bookmark
    }

    public func remove(id: UUID) {
        let stored = bookmarks().filter { $0.id != id }
        persist(stored)
        MacAlarmLog.appShell.info("Watched folder removed (\(stored.count, privacy: .public) remaining)")
    }

    public func removeAll() {
        persist([])
    }

    /// Resolves every stored bookmark to a live URL, starting a security-scoped
    /// access session for each. Stale bookmarks are refreshed in place when
    /// possible. The caller owns the returned access sessions and must call
    /// `stopAccessing` when watching ends.
    public func resolve() -> [ResolvedWatchedFolder] {
        var refreshed = false
        var stored = bookmarks()
        var resolved = [ResolvedWatchedFolder]()

        for index in stored.indices {
            var isStale = false
            guard
                let url = try? URL(
                    resolvingBookmarkData: stored[index].bookmark,
                    options: resolutionOptions,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
            else {
                MacAlarmLog.appShell.error(
                    "Watched folder bookmark could not be resolved; keeping the entry for user removal")
                continue
            }

            let didStart = url.startAccessingSecurityScopedResource()

            if isStale,
                let fresh = try? url.bookmarkData(
                    options: creationOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
            {
                stored[index].bookmark = fresh
                stored[index].displayPath = url.standardizedFileURL.path
                refreshed = true
            }

            resolved.append(
                ResolvedWatchedFolder(
                    bookmark: stored[index], url: url, isStale: isStale, didStartAccess: didStart))
        }

        if refreshed {
            persist(stored)
        }
        return resolved
    }

    private func persist(_ bookmarks: [WatchedFolderBookmark]) {
        if let data = try? JSONEncoder().encode(bookmarks) {
            defaults.set(data, forKey: key)
        }
    }
}
