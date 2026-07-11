import SwiftUI

struct StatusBadge<Leading: View, Content: View>: View {
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 6) {
            leading()
            content()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: AppRadius.control))
    }
}
