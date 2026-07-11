import SwiftUI

struct CategoryFilterTip: View {
    let filter: TimelineFilterDefinition
    let state: CategoryDisplayState

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: filter.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(filter.tintColor)
                    .frame(width: 15)

                Text(filter.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(state.indicatorColor(for: filter))
                    .frame(width: 6, height: 6)

                Text(state.tipText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 142, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.control)
                .strokeBorder(filter.tintColor.opacity(0.34), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
        .allowsHitTesting(false)
    }
}
