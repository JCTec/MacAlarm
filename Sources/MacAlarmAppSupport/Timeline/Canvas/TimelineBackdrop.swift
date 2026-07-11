import SwiftUI

struct TimelineBackdrop: View {
    let width: CGFloat
    let height: CGFloat
    let spineY: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0...tickCount, id: \.self) { index in
                let x = 24 + CGFloat(index) * ((width - 48) / CGFloat(max(tickCount, 1)))
                Path { path in
                    path.move(to: CGPoint(x: x, y: 22))
                    path.addLine(to: CGPoint(x: x, y: height - 22))
                }
                .stroke(Color(nsColor: .separatorColor).opacity(index.isMultiple(of: 2) ? 0.18 : 0.09), lineWidth: 1)
            }

            Path { path in
                path.move(to: CGPoint(x: 24, y: spineY))
                path.addLine(to: CGPoint(x: width - 24, y: spineY))
            }
            .stroke(Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 3, lineCap: .round))

            Path { path in
                path.move(to: CGPoint(x: 24, y: spineY))
                path.addLine(to: CGPoint(x: width - 24, y: spineY))
            }
            .stroke(Color(nsColor: .separatorColor).opacity(0.55), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }
        .frame(width: width, height: height)
    }

    private var tickCount: Int {
        max(Int(width / 180), 2)
    }
}
