import SwiftUI

struct TimeTicks: View {
    let records: [TimelineDisplayRecord]
    let contentWidth: CGFloat
    let spineY: CGFloat

    private var ticks: [TimelineTickLabel] {
        TimelineTickPlanner(contentWidth: contentWidth).labels(for: records.map(\.timestamp))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(ticks) { tick in
                VStack(spacing: 5) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.32))
                        .frame(width: 1, height: 11)
                    HStack(spacing: 4) {
                        Text(tick.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if tick.count > 1 {
                            Text("+\(tick.count - 1)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                        }
                    }
                    .fixedSize()
                }
                .position(x: tick.x, y: spineY + 24)
            }
        }
        .allowsHitTesting(false)
    }
}
