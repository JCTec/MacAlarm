import SwiftUI

struct Tag: View {
    let title: String
    let color: Color

    init(_ title: String, color: Color) {
        self.title = title
        self.color = color
    }

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .foregroundStyle(color == .secondary ? Color.secondary : Color.white)
            .background(
                Capsule()
                    .fill(color == .secondary ? Color.secondary.opacity(0.12) : color.opacity(0.9))
            )
    }
}
