import Foundation

#if canImport(Darwin)
    import Darwin
#endif

/// File-based transport for custom events. Producers (the viewer app and
/// `macalarmctl emit-log`) drop one canonical-JSON `CustomLogEventPayload` per
/// event into the spool directory using a UUID filename; the agent watches the
/// directory, ingests files in name order into the ledger as source `custom`,
/// and deletes each after a successful append.
///
/// This is the single event transport for both sandboxed and unsandboxed builds.
/// The UUID in the filename becomes the ingested `AlarmEvent.id`, so if a file is
/// re-seen (e.g. the agent crashed between append and delete) it reconstructs the
/// same event id, keeping downstream de-duplication possible.
public enum EventSpool {
    public static let fileExtension = "json"

    /// Writes `payload` to `<uuid>.json` in `directory` atomically with mode
    /// 0600, returning the file URL. The returned id equals the filename UUID and
    /// the eventual `AlarmEvent.id`.
    @discardableResult
    public static func write(
        _ payload: CustomLogEventPayload,
        id: UUID = UUID(),
        to directory: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(id.uuidString).\(fileExtension)", isDirectory: false)
        let data = try CanonicalJSON.encode(payload)
        try data.write(to: url, options: [.atomic])
        #if canImport(Darwin)
            chmod(url.path, S_IRUSR | S_IWUSR)
        #endif
        return url
    }

    /// Spool files in the directory, sorted by filename so ingestion is
    /// deterministic. Non-`.json` files are ignored.
    public static func pendingFiles(in directory: URL, fileManager: FileManager = .default) -> [URL] {
        guard
            let contents = try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else {
            return []
        }
        return
            contents
            .filter { $0.pathExtension == fileExtension }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Decodes a spool file into an `AlarmEvent` with source `custom`, preserving
    /// the event id from the filename and the produced timestamp from the file's
    /// creation date.
    public static func event(fromFile url: URL) throws -> AlarmEvent {
        let data = try Data(contentsOf: url)
        let payload = try CanonicalJSON.decoder.decode(CustomLogEventPayload.self, from: data)
        let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) ?? UUID()
        let observedAt = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()

        var metadata = payload.metadata
        if let message = payload.message, !message.isEmpty {
            metadata["message"] = message
        }

        return AlarmEvent(
            id: id,
            observedAt: observedAt,
            source: "custom",
            name: payload.name,
            severity: payload.severity,
            metadata: metadata
        )
    }
}

/// Serialized ingestion of spool files into the ledger. Actor isolation makes
/// concurrent `ingestPending()` calls safe when a burst of file-system events
/// arrives. A file that appends successfully is deleted; a file that fails to
/// decode/append is left in place and logged (attributed), and retried on the
/// next call.
public actor SpoolIngestor {
    public typealias Recorder = @Sendable (AlarmEvent) async -> Bool

    private let directory: URL
    private let record: Recorder
    private let fileManager: FileManager
    /// Filenames appended successfully but whose delete failed. Kept so a lingering
    /// file is not re-appended within this run.
    private var appendedPendingDelete = Set<String>()
    /// A drain pass is currently running. Because `record` awaits, this actor is
    /// reentrant; without this guard a file-system event arriving mid-append would
    /// start a second pass that re-reads the not-yet-deleted file and double-appends.
    private var isDraining = false
    private var rescanRequested = false

    public init(directory: URL, fileManager: FileManager = .default, record: @escaping Recorder) {
        self.directory = directory
        self.fileManager = fileManager
        self.record = record
    }

    public func ingestPending() async {
        guard !isDraining else {
            // A drain is already in flight; ask it to rescan once it finishes so
            // files that appeared during this pass are not missed.
            rescanRequested = true
            return
        }
        isDraining = true
        defer { isDraining = false }

        repeat {
            rescanRequested = false
            await drainOnce()
        } while rescanRequested
    }

    private func drainOnce() async {
        for url in EventSpool.pendingFiles(in: directory, fileManager: fileManager) {
            let name = url.lastPathComponent
            if appendedPendingDelete.contains(name) {
                // Already appended this run; only the delete is outstanding.
                delete(url, name: name)
                continue
            }

            let event: AlarmEvent
            do {
                event = try EventSpool.event(fromFile: url)
            } catch {
                MacAlarmLog.sources.error(
                    """
                    Spool file \(name, privacy: .public) could not be decoded: \
                    \(String(describing: error), privacy: .public)
                    """)
                continue
            }

            let appended = await record(event)
            guard appended else {
                MacAlarmLog.sources.error(
                    "Spool file \(name, privacy: .public) failed to append; will retry")
                continue
            }

            appendedPendingDelete.insert(name)
            delete(url, name: name)
        }
    }

    private func delete(_ url: URL, name: String) {
        do {
            try fileManager.removeItem(at: url)
            appendedPendingDelete.remove(name)
        } catch {
            // Leave it in `appendedPendingDelete` so it is not re-appended; the
            // delete is retried on the next ingest pass.
            MacAlarmLog.sources.notice(
                "Spool file \(name, privacy: .public) appended but not yet deleted")
        }
    }
}
