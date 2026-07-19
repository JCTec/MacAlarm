import Darwin
import Dispatch
import Foundation

public struct FileEvent: Codable, Equatable, Sendable {
    public var path: String
    public var flags: [String]

    public init(path: String, flags: [String]) {
        self.path = path
        self.flags = flags
    }

    public var alarmEvent: AlarmEvent {
        AlarmEvent(
            source: "filesystem",
            name: "path.changed",
            severity: .notice,
            metadata: [
                "path": path,
                "flags": flags.joined(separator: ","),
            ]
        )
    }
}

@MainActor
public final class FileEventSource {
    private let path: String
    private let queue: DispatchQueue
    private var descriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?

    public init(path: String, queue: DispatchQueue = DispatchQueue(label: "com.jctec.macalarm.file-events")) {
        self.path = path
        self.queue = queue
    }

    deinit {
        source?.cancel()
        source = nil
        descriptor = -1
    }

    public func start(handler: @escaping @Sendable (FileEvent) -> Void) throws {
        guard source == nil else {
            return
        }

        let openedDescriptor = open(path, O_EVTONLY)
        guard openedDescriptor >= 0 else {
            throw MacAlarmError.fileDescriptorOpenFailed(path: path, errno: errno)
        }

        descriptor = openedDescriptor
        // Build the source and its handlers in a nonisolated context. If the
        // event-handler closure were formed here (a @MainActor method) Swift 6
        // would infer it as MainActor-isolated, and Dispatch's client callout
        // would assert the main queue while the handler actually runs on `queue`
        // (a background queue) — a hard crash on recent macOS. The nonisolated
        // helper keeps the handler unisolated so it runs safely off-main.
        let dispatchSource = Self.makeFileSystemSource(
            descriptor: openedDescriptor,
            path: path,
            queue: queue,
            handler: handler
        )

        source = dispatchSource
        dispatchSource.resume()
    }

    private nonisolated static func makeFileSystemSource(
        descriptor: CInt,
        path: String,
        queue: DispatchQueue,
        handler: @escaping @Sendable (FileEvent) -> Void
    ) -> DispatchSourceFileSystemObject {
        let dispatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke],
            queue: queue
        )

        dispatchSource.setEventHandler {
            let flags = dispatchSource.data.flagNames
            MacAlarmLog.sources.debug(
                "File event delivered (\(flags.joined(separator: ","), privacy: .public))")
            handler(FileEvent(path: path, flags: flags))
        }

        dispatchSource.setCancelHandler {
            close(descriptor)
        }

        return dispatchSource
    }

    public func stop() {
        if source != nil {
            MacAlarmLog.sources.debug("File watch stopped")
        }
        source?.cancel()
        source = nil
        descriptor = -1
    }
}

private extension DispatchSource.FileSystemEvent {
    var flagNames: [String] {
        var names = [String]()

        if contains(.write) {
            names.append("write")
        }
        if contains(.extend) {
            names.append("extend")
        }
        if contains(.attrib) {
            names.append("attrib")
        }
        if contains(.delete) {
            names.append("delete")
        }
        if contains(.rename) {
            names.append("rename")
        }
        if contains(.revoke) {
            names.append("revoke")
        }

        return names.isEmpty ? ["unknown"] : names
    }
}
