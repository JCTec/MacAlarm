import SwiftUI

struct IconTile: View {
    let symbolName: String
    let tintColor: Color
    var size: CGFloat = 32
    var cornerRadius: CGFloat = AppRadius.control
    var opacity: Double = 0.16

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(tintColor.opacity(opacity))
                .frame(width: size, height: size)
            Image(systemName: symbolName)
                .font(.system(size: max(size * 0.45, 12), weight: .semibold))
                .foregroundStyle(tintColor)
        }
    }
}
