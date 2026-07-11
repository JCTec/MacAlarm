import CoreGraphics

struct TimelineLayoutTimeMapper: Sendable {
    let records: [TimelineDisplayRecord]
    let width: CGFloat

    func xPosition(for record: TimelineDisplayRecord) -> CGFloat {
        guard let first = records.first?.timestamp, let last = records.last?.timestamp, first != last else {
            return width - 80
        }

        let total = last.timeIntervalSince(first)
        let elapsed = record.timestamp.timeIntervalSince(first)
        return 64 + CGFloat(elapsed / total) * max(width - 128, 1)
    }
}
