import CoreGraphics

public struct TimelineLayout: Equatable, Sendable {
    public var signature: TimelineLayoutSignature
    public var contentWidth: CGFloat
    public var height: CGFloat
    public var spineY: CGFloat
    public var nodes: [TimelineLayoutNode]

    public static func placeholder(for request: TimelineLayoutRequest) -> TimelineLayout {
        placeholder(for: request, signature: request.signature)
    }

    public static func placeholder(for request: TimelineLayoutRequest, signature: TimelineLayoutSignature)
        -> TimelineLayout
    {
        let geometry = TimelineLayoutGeometry(signature: signature, recordCount: request.records.count)
        return TimelineLayout(
            signature: signature,
            contentWidth: geometry.contentWidth,
            height: geometry.height,
            spineY: geometry.spineY,
            nodes: []
        )
    }
}

public struct TimelineLayoutNode: Identifiable, Equatable, Sendable {
    public var displayRecord: TimelineDisplayRecord
    public var placement: TimelinePlacement

    public var id: TimelineRecord.ID { displayRecord.id }
}

public struct TimelinePlacement: Equatable, Sendable {
    public let x: CGFloat
    public let nodeY: CGFloat
    public let direction: CGFloat
    public let prominence: TimelineProminence
}
