import SwiftUI

struct TimelineConnector: View {
    let width: CGFloat
    let height: CGFloat
    let x: CGFloat
    let spineY: CGFloat
    let nodeY: CGFloat
    let color: Color
    let prominence: TimelineProminence
    let selected: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: CGPoint(x: x, y: spineY))
                path.addLine(to: CGPoint(x: x, y: nodeY))
            }
            .stroke(
                color.opacity(selected ? 0.76 : max(prominence.opacity * 0.36, 0.16)),
                style: StrokeStyle(
                    lineWidth: selected ? prominence.lineWidth + 1 : prominence.lineWidth, lineCap: .round)
            )

            Circle()
                .fill(color.opacity(selected ? 0.9 : 0.42))
                .frame(width: selected ? 7 : 5, height: selected ? 7 : 5)
                .position(x: x, y: spineY)
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }
}
