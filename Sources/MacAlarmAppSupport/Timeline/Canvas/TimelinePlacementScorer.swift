import CoreGraphics

struct TimelinePlacementScorer: Sendable {
    func score(_ candidate: TimelinePlacementCandidate, placedNodes: [TimelinePlacedNode]) -> CGFloat {
        var score = CGFloat(candidate.lane) * 10
        score += candidate.direction == candidate.preferredDirection ? 0 : 4
        score += candidate.distance * 0.01

        for node in placedNodes.suffix(96) {
            let dx = abs(candidate.x - node.x)
            guard dx < 132 else { continue }

            let dy = abs(candidate.nodeY - node.y)
            let minX = (candidate.size + node.size) / 2 + 24
            let minY = (candidate.size + node.size) / 2 + 18

            if dx < minX && dy < minY {
                score += 12_000
                score += (minX - dx) * 120
                score += (minY - dy) * 160
            } else if dx < 72 && dy < minY + 18 {
                score += (72 - dx) * 5
                score += (minY + 18 - dy) * 8
            }

            if dx < 12 && candidate.direction == node.direction {
                score += 18
            }
        }

        return score
    }
}
