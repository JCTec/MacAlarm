import CoreGraphics
import MacAlarmCore

public struct TimelineLayoutEngine: Sendable {
    public init() {}

    public func layout(request: TimelineLayoutRequest) -> TimelineLayout {
        let state = MacAlarmLog.signposter.beginInterval("timelineLayout")
        defer { MacAlarmLog.signposter.endInterval("timelineLayout", state) }
        return layout(records: request.records, signature: request.signature, shouldCancel: { false })
            ?? TimelineLayout.placeholder(for: request)
    }

    public func layoutIfNotCancelled(request: TimelineLayoutRequest) -> TimelineLayout? {
        let state = MacAlarmLog.signposter.beginInterval("timelineLayout")
        defer { MacAlarmLog.signposter.endInterval("timelineLayout", state) }
        return layout(records: request.records, signature: request.signature) {
            Task.isCancelled
        }
    }

    public func layout(records: [TimelineDisplayRecord], viewportSize: CGSize, zoom: Double) -> TimelineLayout {
        let request = TimelineLayoutRequest(
            records: records, viewportWidth: viewportSize.width, viewportHeight: viewportSize.height, zoom: zoom)
        return layout(request: request)
    }

    private func layout(
        records: [TimelineDisplayRecord],
        signature: TimelineLayoutSignature,
        shouldCancel: () -> Bool
    ) -> TimelineLayout? {
        let geometry = TimelineLayoutGeometry(signature: signature, recordCount: records.count)
        let timeMapper = TimelineLayoutTimeMapper(records: records, width: geometry.contentWidth)
        let lanePlanner = TimelineLanePlanner()
        let scorer = TimelinePlacementScorer()
        var nodes = [TimelineLayoutNode]()
        var placedNodes = [TimelinePlacedNode]()

        for (offset, record) in records.enumerated() {
            if offset.isMultiple(of: 16), shouldCancel() {
                return nil
            }

            let prominence = prominence(for: record)
            let x = timeMapper.xPosition(for: record)
            let candidates = lanePlanner.candidates(x: x, offset: offset, prominence: prominence, geometry: geometry)
            let candidate =
                candidates.min { lhs, rhs in
                    scorer.score(lhs, placedNodes: placedNodes) < scorer.score(rhs, placedNodes: placedNodes)
                } ?? lanePlanner.fallbackCandidate(x: x, prominence: prominence, geometry: geometry)

            let placement = TimelinePlacement(
                x: candidate.x,
                nodeY: candidate.nodeY,
                direction: candidate.direction,
                prominence: prominence
            )
            nodes.append(TimelineLayoutNode(displayRecord: record, placement: placement))
            placedNodes.append(
                TimelinePlacedNode(
                    x: candidate.x,
                    y: candidate.nodeY,
                    size: max(prominence.circleSize, 16),
                    direction: candidate.direction
                )
            )
        }

        guard !shouldCancel() else {
            return nil
        }

        return TimelineLayout(
            signature: signature,
            contentWidth: geometry.contentWidth,
            height: geometry.height,
            spineY: geometry.spineY,
            nodes: nodes
        )
    }

    private func prominence(for record: TimelineDisplayRecord) -> TimelineProminence {
        let effectiveState: CategoryDisplayState = record.hiddenBySearch ? .normal : record.displayState
        return TimelineProminence.forState(effectiveState, severity: record.event.severity)
    }
}
