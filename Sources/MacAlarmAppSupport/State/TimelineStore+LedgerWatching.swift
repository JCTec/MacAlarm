import Darwin
import Dispatch
import Foundation
import MacAlarmCore

extension TimelineStore {
    func startWatchingLedgerPath() {
        guard fileSource == nil else {
            return
        }

        watchSetupTask?.cancel()
        let ledgerURL = ledgerURL
        watchSetupTask = Task { [weak self] in
            let target = await MacAlarmBackgroundTask.value(priority: .utility) {
                TimelineLedgerWatchTarget.resolve(ledgerURL: ledgerURL)
            }

            guard let target, !Task.isCancelled, self?.fileSource == nil else {
                return
            }

            switch target {
            case .ledgerFile(let path):
                MacAlarmLog.timeline.debug("Watching ledger file")
                self?.startWatchingFile(at: path, eventMask: [.write, .extend, .rename, .delete])
            case .directory(let path):
                MacAlarmLog.timeline.notice("Ledger missing; watching parent directory for it to appear")
                self?.startWatchingFile(at: path, eventMask: [.write, .extend, .rename, .delete, .attrib])
            }
        }
    }

    private func startWatchingFile(at path: String, eventMask: DispatchSource.FileSystemEvent) {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else {
            MacAlarmLog.timeline.error(
                "Failed to open watch target (errno \(errno, privacy: .public))")
            return
        }
        fileDescriptor = descriptor
        watchedFilePath = path

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: eventMask,
            queue: .main
        )
        source.setEventHandler { [weak self, weak source] in
            self?.handleLedgerFilesystemEvent(source?.data ?? [])
        }
        source.setCancelHandler {
            if descriptor >= 0 {
                close(descriptor)
            }
        }
        fileSource = source
        source.resume()
    }

    private func handleLedgerFilesystemEvent(_ events: DispatchSource.FileSystemEvent) {
        let watchedPath = watchedFilePath
        let isWatchingLedger = watchedPath == ledgerURL.path
        let shouldReattach = !isWatchingLedger || events.contains(.rename) || events.contains(.delete)

        reload()

        if shouldReattach {
            MacAlarmLog.timeline.notice("Ledger watch reattaching (rename/delete or directory event)")
            stopWatchingLedger()
            startWatchingLedgerPath()
        }
    }

    private func stopWatchingLedger() {
        fileSource?.cancel()
        fileSource = nil
        fileDescriptor = -1
        watchedFilePath = nil
        watchSetupTask?.cancel()
        watchSetupTask = nil
    }
}

enum TimelineLedgerWatchTarget: Equatable, Sendable {
    case ledgerFile(String)
    case directory(String)

    static func resolve(ledgerURL: URL) -> TimelineLedgerWatchTarget? {
        if FileManager.default.fileExists(atPath: ledgerURL.path) {
            return .ledgerFile(ledgerURL.path)
        }

        let directory = ledgerURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return .directory(directory.path)
        } catch {
            return nil
        }
    }
}
