import Foundation
import MacAlarmCore

/// Watches the user-selected folders in the app process and forwards changes to
/// the event spool, where the recorder ingests them into the ledger.
///
/// This is the permanent App Store architecture for folder watching: a
/// security-scoped bookmark grants *this* app process access, and that grant
/// cannot cross into the launchd-launched recorder. So sandboxed folder watching
/// is active only while MacAlarm.app is running — an inherent property of the
/// sandbox, documented in the UI and SANDBOX_BEHAVIOR.md, not a limitation to
/// revisit.
@MainActor
public final class WatchService {
    private let bookmarks: WatchedFolderBookmarks
    private let spoolDirectory: URL
    private var sources = [FileEventSource]()
    private var accessedURLs = [URL]()
    private var isRunning = false

    public init(bookmarks: WatchedFolderBookmarks, spoolDirectory: URL) {
        self.bookmarks = bookmarks
        self.spoolDirectory = spoolDirectory
    }

    /// Convenience initializer resolving the installed spool directory.
    public convenience init(bookmarks: WatchedFolderBookmarks, label: String) {
        self.init(
            bookmarks: bookmarks,
            spoolDirectory: MacAlarmInstallationPaths(label: label).resolvedSpoolDirectory()
        )
    }

    public var watchedPaths: [String] {
        sources.isEmpty ? [] : accessedURLs.map(\.path)
    }

    /// Resolves the persisted bookmarks and starts one watcher per folder.
    /// Idempotent: restarts cleanly if already running.
    public func start() {
        stop()
        isRunning = true

        for folder in bookmarks.resolve() {
            if folder.didStartAccess {
                accessedURLs.append(folder.url)
            }

            let source = FileEventSource(path: folder.url.path)
            do {
                try source.start { [spoolDirectory, path = folder.url.path] fileEvent in
                    let payload = CustomLogEventPayload(
                        name: "path.changed",
                        severity: .notice,
                        message: nil,
                        metadata: [
                            "path": path,
                            "flags": fileEvent.flags.joined(separator: ","),
                            "origin": "viewer-watch",
                        ]
                    )
                    do {
                        _ = try EventSpool.write(payload, to: spoolDirectory)
                    } catch {
                        MacAlarmLog.appShell.error(
                            "Watched folder event could not be spooled: \(String(describing: error), privacy: .public)")
                    }
                }
                sources.append(source)
                MacAlarmLog.appShell.info("Watched folder started (\(folder.url.path, privacy: .public))")
            } catch {
                MacAlarmLog.appShell.error(
                    "Watched folder failed to start (\(folder.url.path, privacy: .public)): \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    public func stop() {
        for source in sources {
            source.stop()
        }
        sources.removeAll()

        for url in accessedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        accessedURLs.removeAll()
        isRunning = false
    }

    /// Re-reads the bookmarks and restarts watching (call after add/remove).
    public func reload() {
        guard isRunning else {
            return
        }
        start()
    }
}
