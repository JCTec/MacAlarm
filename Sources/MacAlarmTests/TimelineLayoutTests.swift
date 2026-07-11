import Foundation
import MacAlarmCore

@testable import MacAlarmAppSupport

extension MacAlarmTests {
    static func runTimelineLayoutTests(_ runner: TestRunner) async {
        await runner.run("timeline layout spreads dense nodes apart") {
            let base = Date(timeIntervalSince1970: 2_000)
            let displayRecords = (0..<14).map { index in
                timelineDisplayRecord(
                    index: index,
                    event: AlarmEvent(
                        id: UUID(),
                        observedAt: base.addingTimeInterval(Double(index)),
                        source: "session",
                        name: "application.activated",
                        metadata: ["applicationName": "App \(index)"]
                    ),
                    displayState: index.isMultiple(of: 3) ? .spotlight : .normal
                )
            }

            let layout = TimelineLayoutEngine().layout(
                request: TimelineLayoutRequest(
                    records: displayRecords, viewportWidth: 620, viewportHeight: 420, zoom: 1)
            )

            try expect(layout.nodes.count == displayRecords.count, "layout should include every display record")
            for lhsIndex in layout.nodes.indices {
                for rhsIndex in layout.nodes.indices where rhsIndex > lhsIndex {
                    let lhs = layout.nodes[lhsIndex].placement
                    let rhs = layout.nodes[rhsIndex].placement
                    let dx = abs(lhs.x - rhs.x)
                    let dy = abs(lhs.nodeY - rhs.nodeY)
                    let minX = (lhs.prominence.circleSize + rhs.prominence.circleSize) / 2 + 12
                    let minY = (lhs.prominence.circleSize + rhs.prominence.circleSize) / 2 + 8
                    try expect(dx >= minX || dy >= minY, "layout nodes should not visually collide")
                }
            }
        }

        await runner.run("timeline layout signature ignores presentation-only changes") {
            let eventID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
            let event = AlarmEvent(
                id: eventID, observedAt: Date(timeIntervalSince1970: 3_000), source: "custom", name: "audio.detected")
            let first = timelineDisplayRecord(index: 0, event: event, displayState: .spotlight)
            var second = first
            second.presentation = TimelineEventPresentation(
                title: "Renamed", symbolName: "mic.fill", color: .notification)

            let firstSignature = TimelineLayoutRequest(
                records: [first], viewportWidth: 600, viewportHeight: 400, zoom: 1
            ).signature
            let secondSignature = TimelineLayoutRequest(
                records: [second], viewportWidth: 600, viewportHeight: 400, zoom: 1
            ).signature

            try expect(firstSignature == secondSignature, "layout identity should ignore presentation-only changes")
        }

        await runner.run("timeline layout placeholder preserves request geometry") {
            let records = [
                timelineDisplayRecord(
                    index: 0, event: AlarmEvent(source: "session", name: "screen.unlocked"), displayState: .spotlight),
                timelineDisplayRecord(
                    index: 1, event: AlarmEvent(source: "session", name: "screen.locked"), displayState: .normal),
            ]
            let request = TimelineLayoutRequest(records: records, viewportWidth: 640, viewportHeight: 360, zoom: 1.5)
            let layout = TimelineLayout.placeholder(for: request)

            try expect(layout.signature == request.signature, "placeholder should keep the request signature")
            try expect(layout.height == 360, "placeholder should keep viewport height")
            try expect(layout.spineY == 180, "placeholder should keep the spine centered")
            try expect(layout.contentWidth == 960, "placeholder should honor zoomed viewport width")
            try expect(layout.nodes.isEmpty, "placeholder should not contain stale nodes")
        }

        await runner.run("timeline canvas layout state hides stale layouts") {
            let base = Date(timeIntervalSince1970: 3_200)
            let firstRecords = [
                timelineDisplayRecord(
                    index: 0,
                    event: AlarmEvent(observedAt: base, source: "session", name: "screen.unlocked"),
                    displayState: .spotlight
                ),
                timelineDisplayRecord(
                    index: 1,
                    event: AlarmEvent(observedAt: base.addingTimeInterval(4), source: "session", name: "screen.locked"),
                    displayState: .normal
                ),
            ]
            let secondRecords =
                firstRecords + [
                    timelineDisplayRecord(
                        index: 2,
                        event: AlarmEvent(
                            observedAt: base.addingTimeInterval(8),
                            source: "session",
                            name: "application.activated",
                            metadata: ["applicationName": "Finder"]
                        ),
                        displayState: .normal
                    )
                ]
            let firstRequest = TimelineLayoutRequest(
                records: firstRecords, viewportWidth: 600, viewportHeight: 360, zoom: 1)
            let secondRequest = TimelineLayoutRequest(
                records: secondRecords, viewportWidth: 720, viewportHeight: 420, zoom: 1.25)
            let firstLayout = TimelineLayoutEngine().layout(request: firstRequest)
            let state = TimelineCanvasLayoutState(layout: firstLayout)

            try expect(
                state.activeLayout(for: firstRequest) == firstLayout,
                "matching canvas requests should reuse the finished layout"
            )

            let staleFallback = state.activeLayout(for: secondRequest)
            try expect(staleFallback.signature == secondRequest.signature, "fallback should match the new request")
            try expect(staleFallback.nodes.isEmpty, "fallback should not show stale nodes")
            try expect(staleFallback.height == 420, "fallback should preserve new viewport height")
            try expect(staleFallback.contentWidth == 900, "fallback should preserve new zoomed width")
        }

        await runner.run("timeline layout geometry keeps content floor and centered spine") {
            let signature = TimelineLayoutSignature(
                viewportWidth: 300,
                viewportHeight: 420,
                zoom: 1,
                records: []
            )
            let geometry = TimelineLayoutGeometry(signature: signature, recordCount: 8)

            try expect(geometry.contentWidth == 704, "content width should preserve per-record floor")
            try expect(geometry.height == 420, "geometry should preserve viewport height")
            try expect(geometry.spineY == 210, "geometry should keep the spine centered")
        }

        await runner.run("timeline zoom scales dense record floor") {
            let zoomedOut = TimelineLayoutGeometry(
                signature: TimelineLayoutSignature(
                    viewportWidth: 300,
                    viewportHeight: 420,
                    zoom: 0.5,
                    records: []
                ),
                recordCount: 20
            )
            let normal = TimelineLayoutGeometry(
                signature: TimelineLayoutSignature(
                    viewportWidth: 300,
                    viewportHeight: 420,
                    zoom: 1,
                    records: []
                ),
                recordCount: 20
            )
            let zoomedIn = TimelineLayoutGeometry(
                signature: TimelineLayoutSignature(
                    viewportWidth: 300,
                    viewportHeight: 420,
                    zoom: 3,
                    records: []
                ),
                recordCount: 20
            )

            try expect(zoomedOut.contentWidth == 880, "zooming out should compress dense timelines")
            try expect(normal.contentWidth == 1_760, "normal dense timeline should keep per-record spacing")
            try expect(zoomedIn.contentWidth == 5_280, "zooming in should expand dense timelines")
        }

        await runner.run("timeline zoom levels step predictably") {
            try expect(TimelineZoomLevel.nearest(to: 1.2) == 1, "zoom should snap to nearest level")
            try expect(TimelineZoomLevel.next(after: 1) == 1.5, "zoom in should step to next level")
            try expect(TimelineZoomLevel.previous(before: 1) == 0.75, "zoom out should step to previous level")
            try expect(TimelineZoomLevel.value(forNormalizedIndex: 3.4) == 1.5, "slider index should snap to level")
            try expect(TimelineZoomLevel.title(for: 0.75) == "0.75x", "zoom title should show multiplier")
        }

        await runner.run("timeline layout time mapper anchors first middle and last records") {
            let base = Date(timeIntervalSince1970: 4_000)
            let records = [
                timelineDisplayRecord(
                    index: 0,
                    event: AlarmEvent(observedAt: base, source: "session", name: "screen.unlocked"),
                    displayState: .spotlight
                ),
                timelineDisplayRecord(
                    index: 1,
                    event: AlarmEvent(
                        observedAt: base.addingTimeInterval(50), source: "session", name: "screen.locked"),
                    displayState: .normal
                ),
                timelineDisplayRecord(
                    index: 2,
                    event: AlarmEvent(
                        observedAt: base.addingTimeInterval(100), source: "session", name: "screen.unlocked"),
                    displayState: .normal
                ),
            ]
            let mapper = TimelineLayoutTimeMapper(records: records, width: 1_000)

            try expect(mapper.xPosition(for: records[0]) == 64, "first record should anchor at left inset")
            try expect(mapper.xPosition(for: records[1]) == 500, "middle record should land halfway across")
            try expect(mapper.xPosition(for: records[2]) == 936, "last record should anchor at right inset")
        }

        await runner.run("timeline tick planner aggregates overlapping labels") {
            let base = Date(timeIntervalSince1970: 7_000)
            let timestamps = (0..<8).map { base.addingTimeInterval(Double($0)) }
            let labels = TimelineTickPlanner(contentWidth: 320).labels(for: timestamps)

            try expect(labels.count == 2, "dense nearby timestamps should be clustered into two labels")
            try expect(labels.map(\.count) == [3, 2], "clusters should preserve hidden label counts")
            try expect(labels[1].x - labels[0].x >= 88, "clustered labels should keep visual spacing")
        }

        await runner.run("timeline tick planner collapses equal timestamps near live edge") {
            let timestamp = Date(timeIntervalSince1970: 7_500)
            let labels = TimelineTickPlanner(contentWidth: 500).labels(for: [timestamp, timestamp, timestamp])

            try expect(labels.count == 1, "equal timestamps should render as one clustered label")
            try expect(labels.first?.count == 3, "collapsed label should retain the clustered count")
            try expect(labels.first?.x == 420, "collapsed equal timestamps should sit near the trailing edge")
            try expect(
                labels.first?.title == timestamp.timelineTickString, "single-time clusters should not show a range")
        }

        await runner.run("timeline tick planner keeps newest timestamp after sampling") {
            let base = Date(timeIntervalSince1970: 8_000)
            let timestamps = (0..<20).map { base.addingTimeInterval(Double($0)) }
            let labels = TimelineTickPlanner(contentWidth: 400).labels(for: timestamps)

            try expect(
                labels.last?.title == timestamps.last?.timelineTickString, "sampled ticks should keep latest time")
            try expect(labels.last?.count == 1, "latest sampled timestamp should stay independently visible")
        }

        await runner.run("timeline event label positioner clamps to canvas bounds") {
            try expect(
                TimelineEventLabelPositioner.yPosition(
                    nodeY: 120, direction: 1, circleSize: 30, canvasHeight: 400) == 165,
                "downward labels should sit below the node"
            )
            try expect(
                TimelineEventLabelPositioner.yPosition(
                    nodeY: 120, direction: -1, circleSize: 30, canvasHeight: 400) == 75,
                "upward labels should sit above the node"
            )
            try expect(
                TimelineEventLabelPositioner.yPosition(
                    nodeY: 12, direction: -1, circleSize: 38, canvasHeight: 400) == 34,
                "labels should clamp away from the top edge"
            )
            try expect(
                TimelineEventLabelPositioner.yPosition(
                    nodeY: 388, direction: 1, circleSize: 38, canvasHeight: 400) == 366,
                "labels should clamp away from the bottom edge"
            )
        }

        await runner.run("timeline event node text exposes title severity and help detail") {
            let event = AlarmEvent(
                observedAt: Date(timeIntervalSince1970: 8_500),
                source: "session",
                name: "application.activated",
                severity: .critical,
                metadata: [
                    "applicationName": "Terminal",
                    "bundleIdentifier": "com.apple.Terminal",
                ]
            )
            let displayRecord = timelineDisplayRecord(index: 0, event: event, displayState: .spotlight)

            try expect(
                displayRecord.eventNodeAccessibilityLabel.contains("Terminal, critical"),
                "accessibility label should include title and severity"
            )
            try expect(
                displayRecord.eventNodeHelpText.contains("Terminal\ncom.apple.Terminal"),
                "help text should include title and subtitle on separate lines"
            )
        }

        await runner.run("timeline placement scorer penalizes overlapping candidates") {
            let scorer = TimelinePlacementScorer()
            let placed = [
                TimelinePlacedNode(x: 100, y: 100, size: 30, direction: 1)
            ]
            let overlapping = TimelinePlacementCandidate(
                x: 104, nodeY: 104, direction: 1, distance: 40, lane: 0, preferredDirection: 1, size: 30)
            let separated = TimelinePlacementCandidate(
                x: 220, nodeY: 180, direction: -1, distance: 40, lane: 0, preferredDirection: 1, size: 30)

            try expect(
                scorer.score(overlapping, placedNodes: placed) > scorer.score(separated, placedNodes: placed),
                "overlapping candidates should receive a larger placement score"
            )
        }

        await runner.run("timeline layout cancellation stops stale work") {
            let base = Date(timeIntervalSince1970: 3_500)
            let displayRecords = (0..<80).map { index in
                timelineDisplayRecord(
                    index: index,
                    event: AlarmEvent(
                        id: UUID(),
                        observedAt: base.addingTimeInterval(Double(index)),
                        source: "session",
                        name: "application.activated",
                        metadata: ["applicationName": "App \(index)"]
                    ),
                    displayState: .normal
                )
            }
            let request = TimelineLayoutRequest(
                records: displayRecords, viewportWidth: 620, viewportHeight: 420, zoom: 1)

            let task = Task.detached(priority: .userInitiated) {
                TimelineLayoutEngine().layoutIfNotCancelled(request: request)
            }
            task.cancel()

            let layout = await task.value
            try expect(layout == nil, "cancelled timeline layout should not publish stale nodes")
        }

    }
}
