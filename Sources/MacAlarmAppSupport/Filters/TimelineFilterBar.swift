import SwiftUI

private struct CategoryFilterButtonBoundsKey: PreferenceKey {
    static let defaultValue: [TimelineFilterDefinition.ID: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [TimelineFilterDefinition.ID: Anchor<CGRect>],
        nextValue: () -> [TimelineFilterDefinition.ID: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct CategoryFilterBar: View {
    let filters: [TimelineFilterDefinition]
    let state: (TimelineFilterDefinition) -> CategoryDisplayState
    let cycle: (TimelineFilterDefinition) -> Void
    @State private var hoveredFilterID: TimelineFilterDefinition.ID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(filters) { filter in
                    CategoryFilterButton(
                        filter: filter,
                        state: state(filter),
                        hoverChanged: updateHover
                    ) {
                        cycle(filter)
                    }
                    .anchorPreference(
                        key: CategoryFilterButtonBoundsKey.self,
                        value: .bounds
                    ) { [filter.id: $0] }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxWidth: 520, alignment: .leading)
        .overlayPreferenceValue(CategoryFilterButtonBoundsKey.self) { anchors in
            GeometryReader { proxy in
                if let hoveredFilterID,
                    let filter = filters.first(where: { $0.id == hoveredFilterID }),
                    let anchor = anchors[hoveredFilterID]
                {
                    let rect = proxy[anchor]
                    CategoryFilterTip(filter: filter, state: state(filter))
                        .position(x: rect.midX, y: rect.maxY + 49)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .zIndex(1_000)
                        .allowsHitTesting(false)
                }
            }
        }
        .zIndex(1_000)
    }

    private func updateHover(_ filterID: TimelineFilterDefinition.ID?, _ isHovering: Bool) {
        withAnimation(.easeOut(duration: 0.12)) {
            hoveredFilterID = isHovering ? filterID : (hoveredFilterID == filterID ? nil : hoveredFilterID)
        }
    }
}

struct FilterSettingsButton: View {
    let action: () -> Void

    var body: some View {
        ToolbarIconButton(
            symbolName: "slider.horizontal.3",
            helpText: "Configure timeline filters",
            action: action
        )
    }
}
