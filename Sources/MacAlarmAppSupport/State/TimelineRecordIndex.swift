import Foundation

public struct TimelineRecordSet: Sendable {
    public var records: [TimelineRecord]
    public var index: TimelineRecordIndex

    public init(records: [TimelineRecord]) {
        self.records = records
        self.index = TimelineRecordIndex(records: records)
    }

    public static let empty = TimelineRecordSet(records: [])
}

public struct TimelineRecordIndex: Sendable {
    private var recordsByID: [TimelineRecord.ID: TimelineRecord]

    public init(records: [TimelineRecord]) {
        var recordsByID = [TimelineRecord.ID: TimelineRecord](minimumCapacity: records.count)
        for record in records where recordsByID[record.id] == nil {
            recordsByID[record.id] = record
        }
        self.recordsByID = recordsByID
    }

    public func record(for id: TimelineRecord.ID?) -> TimelineRecord? {
        guard let id else { return nil }
        return recordsByID[id]
    }

    public func contains(_ id: TimelineRecord.ID?) -> Bool {
        record(for: id) != nil
    }
}
