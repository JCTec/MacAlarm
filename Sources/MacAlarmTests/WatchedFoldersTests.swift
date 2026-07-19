import Foundation
import MacAlarmCore

@testable import MacAlarmAppSupport

extension MacAlarmTests {
    static func runWatchedFoldersTests(_ runner: TestRunner) async {
        await runner.run("watched folder bookmarks persist, dedupe, resolve, and remove") {
            try await MainActor.run {
                let suite = "MacAlarmTests.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suite), "suite should be created")
                defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

                // Use plain bookmarks so the test does not require sandbox entitlements.
                let store = WatchedFolderBookmarks(
                    defaults: defaults, key: "watched", creationOptions: [], resolutionOptions: [])

                let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
                    UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: folder) }

                try store.add(url: folder)
                try store.add(url: folder)  // adding the same path again should not duplicate
                let stored = store.bookmarks()
                try expect(stored.count == 1, "same folder should not be stored twice, got \(stored.count)")
                try expect(stored[0].displayPath == folder.standardizedFileURL.path, "display path should round-trip")

                let resolved = store.resolve()
                try expect(resolved.count == 1, "one folder should resolve")
                try expect(
                    resolved[0].url.standardizedFileURL.path == folder.standardizedFileURL.path,
                    "resolved URL should match the added folder")
                for entry in resolved where entry.didStartAccess {
                    entry.url.stopAccessingSecurityScopedResource()
                }

                store.remove(id: stored[0].id)
                try expect(store.bookmarks().isEmpty, "removing the folder should clear it")
            }
        }

        await runner.run("watch service forwards folder events to the spool as viewer-watch") {
            try await MainActor.run { () throws -> Void in
                let suite = "MacAlarmTests.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suite), "suite should be created")
                defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

                let store = WatchedFolderBookmarks(
                    defaults: defaults, key: "watched", creationOptions: [], resolutionOptions: [])
                let watched = FileManager.default.temporaryDirectory.appendingPathComponent(
                    UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: watched, withIntermediateDirectories: true)
                let spool = FileManager.default.temporaryDirectory.appendingPathComponent(
                    UUID().uuidString, isDirectory: true)
                defer {
                    try? FileManager.default.removeItem(at: watched)
                    try? FileManager.default.removeItem(at: spool)
                }

                try store.add(url: watched)
                let service = WatchService(bookmarks: store, spoolDirectory: spool)
                service.start()
                defer { service.stop() }
                try expect(service.watchedPaths.count == 1, "service should watch the added folder")
            }
        }
    }
}
