import CoreGraphics
import Foundation

struct TimelineTickPlanner: Sendable {
    var contentWidth: CGFloat
    var clusterDistance: CGFloat = 88
    var minimumSampleSpacing: CGFloat = 190
    var minimumSampleCount = 4
    var edgePadding: CGFloat = 64
    var collapsedTrailingPadding: CGFloat = 80

    func labels(for timestamps: [Date]) -> [TimelineTickLabel] {
        let candidates = sampledTimestamps(timestamps).map { timestamp in
            TimelineTickCandidate(timestamp: timestamp, x: xPosition(for: timestamp, in: timestamps))
        }

        guard !candidates.isEmpty else {
            return []
        }

        return clusteredCandidates(candidates).map(label(for:))
    }

    private func sampledTimestamps(_ timestamps: [Date]) -> [Date] {
        guard timestamps.count > 6 else {
            return timestamps
        }

        let targetCount = max(Int(contentWidth / minimumSampleSpacing), minimumSampleCount)
        let strideValue = max(timestamps.count / targetCount, 1)
        return timestamps.enumerated().compactMap { index, timestamp in
            index.isMultiple(of: strideValue) || index == timestamps.count - 1 ? timestamp : nil
        }
    }

    private func clusteredCandidates(_ candidates: [TimelineTickCandidate]) -> [[TimelineTickCandidate]] {
        var groups = [[TimelineTickCandidate]]()
        for candidate in candidates {
            guard var lastGroup = groups.popLast() else {
                groups.append([candidate])
                continue
            }

            let lastX = lastGroup.map(\.x).reduce(0, +) / CGFloat(lastGroup.count)
            if abs(candidate.x - lastX) < clusterDistance {
                lastGroup.append(candidate)
                groups.append(lastGroup)
            } else {
                groups.append(lastGroup)
                groups.append([candidate])
            }
        }
        return groups
    }

    private func label(for group: [TimelineTickCandidate]) -> TimelineTickLabel {
        let sorted = group.sorted { $0.timestamp < $1.timestamp }
        let x = group.map(\.x).reduce(0, +) / CGFloat(group.count)
        let first = sorted.first?.timestamp ?? Date()
        let last = sorted.last?.timestamp ?? first
        return TimelineTickLabel(
            id: "\(first.timeIntervalSince1970)-\(last.timeIntervalSince1970)-\(group.count)",
            x: x,
            title: first == last
                ? first.timelineTickString : "\(first.timelineTickString)-\(last.timelineTickString)",
            count: group.count
        )
    }

    private func xPosition(for timestamp: Date, in timestamps: [Date]) -> CGFloat {
        guard let first = timestamps.first, let last = timestamps.last, first != last else {
            return contentWidth - collapsedTrailingPadding
        }

        let total = last.timeIntervalSince(first)
        let elapsed = timestamp.timeIntervalSince(first)
        return edgePadding + CGFloat(elapsed / total) * max(contentWidth - edgePadding * 2, 1)
    }
}

private struct TimelineTickCandidate {
    let timestamp: Date
    let x: CGFloat
}

struct TimelineTickLabel: Identifiable, Equatable, Sendable {
    let id: String
    let x: CGFloat
    let title: String
    let count: Int
}
