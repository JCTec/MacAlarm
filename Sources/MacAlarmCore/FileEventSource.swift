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

    public init(path: String, queue: DispatchQueue = DispatchQueue(label: "dev.jc.macalarm.file-events")) {
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
        let dispatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: openedDescriptor,
            eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke],
            queue: queue
        )

        dispatchSource.setEventHandler { [path] in
            handler(FileEvent(path: path, flags: dispatchSource.data.flagNames))
        }

        dispatchSource.setCancelHandler { [openedDescriptor] in
            close(openedDescriptor)
        }

        source = dispatchSource
        dispatchSource.resume()
    }

    public func stop() {
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
