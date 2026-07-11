import CoreGraphics

struct TimelineLanePlanner: Sendable {
    func candidates(
        x: CGFloat,
        offset: Int,
        prominence: TimelineProminence,
        geometry: TimelineLayoutGeometry
    ) -> [TimelinePlacementCandidate] {
        let preferredDirection: CGFloat = offset.isMultiple(of: 2) ? -1 : 1
        let alternateDirection = -preferredDirection
        let directions = [preferredDirection, alternateDirection]
        let nodeSize = max(prominence.circleSize, 16)
        let baseDistance = max(prominence.stemLength, nodeSize + 42)
        let laneSpacing = max(nodeSize + 24, 44)
        let aboveDistances = laneDistances(
            maxDistance: max(geometry.spineY - 42, 0),
            baseDistance: baseDistance,
            laneSpacing: laneSpacing
        )
        let belowDistances = laneDistances(
            maxDistance: max(geometry.height - geometry.spineY - 42, 0),
            baseDistance: baseDistance,
            laneSpacing: laneSpacing
        )
        let laneCount = max(aboveDistances.count, belowDistances.count)

        guard laneCount > 0 else {
            return []
        }

        var candidates: [TimelinePlacementCandidate] = []
        for lane in 0..<laneCount {
            for direction in directions {
                let distances = direction < 0 ? aboveDistances : belowDistances
                guard lane < distances.count else { continue }
                let distance = distances[lane]
                candidates.append(
                    TimelinePlacementCandidate(
                        x: x,
                        nodeY: geometry.spineY + direction * distance,
                        direction: direction,
                        distance: distance,
                        lane: lane,
                        preferredDirection: preferredDirection,
                        size: nodeSize
                    )
                )
            }
        }

        return candidates
    }

    func fallbackCandidate(
        x: CGFloat,
        prominence: TimelineProminence,
        geometry: TimelineLayoutGeometry
    ) -> TimelinePlacementCandidate {
        let nodeSize = max(prominence.circleSize, 16)
        let distance = min(max(prominence.stemLength, nodeSize + 36), max(geometry.height - geometry.spineY - 34, 28))
        return TimelinePlacementCandidate(
            x: x,
            nodeY: geometry.spineY + distance,
            direction: 1,
            distance: distance,
            lane: 0,
            preferredDirection: 1,
            size: nodeSize
        )
    }

    private func laneDistances(maxDistance: CGFloat, baseDistance: CGFloat, laneSpacing: CGFloat) -> [CGFloat] {
        guard maxDistance >= 28 else {
            return []
        }

        var distances = [min(baseDistance, maxDistance)]

        while let last = distances.last, last + laneSpacing <= maxDistance {
            distances.append(last + laneSpacing)
        }

        if let last = distances.last, maxDistance - last > 22 {
            distances.append(maxDistance)
        }

        return distances
    }
}
