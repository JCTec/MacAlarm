import SwiftUI

struct CategoryFilterButton: View {
    let filter: TimelineFilterDefinition
    let state: CategoryDisplayState
    let hoverChanged: (TimelineFilterDefinition.ID?, Bool) -> Void
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: AppRadius.control)
                    .fill(backgroundColor)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppRadius.control)
                            .strokeBorder(borderColor, lineWidth: state == .spotlight ? 1.5 : 1)
                    }

                Image(systemName: filter.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(foregroundColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if state == .hidden {
                    Image(systemName: "slash")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                        .offset(x: -4, y: 4)
                } else if state == .spotlight {
                    Circle()
                        .fill(filter.tintColor)
                        .frame(width: 7, height: 7)
                        .offset(x: -5, y: 5)
                }
            }
            .frame(width: 34, height: 30)
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.control))
        }
        .buttonStyle(.plain)
        .opacity(state == .hidden ? 0.48 : 1)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
            hoverChanged(filter.id, hovering)
        }
        .zIndex(isHovering ? 1_000 : 0)
        .accessibilityLabel(Text(filter.title))
        .accessibilityValue(Text(state.accessibilityText))
        .accessibilityHint(Text("Cycles filter visibility."))
    }

    private var foregroundColor: Color {
        switch state {
        case .normal: filter.tintColor
        case .spotlight: .white
        case .hidden: .secondary
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .normal: Color(nsColor: .controlBackgroundColor)
        case .spotlight: filter.tintColor
        case .hidden: Color(nsColor: .controlBackgroundColor).opacity(0.45)
        }
    }

    private var borderColor: Color {
        switch state {
        case .normal: filter.tintColor.opacity(0.28)
        case .spotlight: filter.tintColor.opacity(0.72)
        case .hidden: Color(nsColor: .separatorColor).opacity(0.45)
        }
    }
}
