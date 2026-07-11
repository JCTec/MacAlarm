import SwiftUI

struct TimelineFilterTemplateBadge: View {
    var body: some View {
        Text("template")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
    }
}
