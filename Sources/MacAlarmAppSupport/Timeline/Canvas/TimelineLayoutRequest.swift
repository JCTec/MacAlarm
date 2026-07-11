import CoreGraphics
import MacAlarmCore

public struct TimelineLayoutRequest: Sendable {
    public var records: [TimelineDisplayRecord]
    public var viewportWidth: CGFloat
    public var viewportHeight: CGFloat
    public var zoom: Double

    public init(records: [TimelineDisplayRecord], viewportWidth: CGFloat, viewportHeight: CGFloat, zoom: Double) {
        self.records = records
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.zoom = zoom
    }

    public var signature: TimelineLayoutSignature {
        TimelineLayoutSignature(
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
            zoom: zoom,
            records: records.map { record in
                TimelineLayoutRecordSignature(
                    id: record.id,
                    severity: record.event.severity,
                    displayState: record.displayState,
                    hiddenBySearch: record.hiddenBySearch
                )
            }
        )
    }
}

public struct TimelineLayoutSignature: Equatable, Sendable {
    public var viewportWidth: CGFloat
    public var viewportHeight: CGFloat
    public var zoom: Double
    public var records: [TimelineLayoutRecordSignature]
}

public struct TimelineLayoutRecordSignature: Equatable, Sendable {
    public var id: TimelineRecord.ID
    public var severity: AlarmSeverity
    public var displayState: CategoryDisplayState
    public var hiddenBySearch: Bool
}
