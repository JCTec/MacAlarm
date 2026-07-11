import SwiftUI

struct TimelineEventNode: View {
    let displayRecord: TimelineDisplayRecord
    let placement: TimelinePlacement
    let canvasHeight: CGFloat
    let selected: Bool
    let select: () -> Void

    @State private var hovering = false

    var body: some View {
        let showLabel = selected || hovering || placement.prominence.labelVisible
        let labelY = TimelineEventLabelPositioner.yPosition(
            nodeY: placement.nodeY,
            direction: placement.direction,
            circleSize: placement.prominence.circleSize,
            canvasHeight: canvasHeight
        )

        ZStack(alignment: .topLeading) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    select()
                }
            } label: {
                TimelineEventNodeIcon(
                    displayRecord: displayRecord,
                    prominence: placement.prominence,
                    selected: selected,
                    hovering: hovering
                )
            }
            .buttonStyle(.plain)
            .position(x: placement.x, y: placement.nodeY)
            .onHover { hovering = $0 }
            .accessibilityLabel(displayRecord.eventNodeAccessibilityLabel)
            .help(displayRecord.eventNodeHelpText)

            if showLabel {
                TimelineEventLabel(displayRecord: displayRecord, selected: selected)
                    .position(x: placement.x, y: labelY)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zIndex(selected ? 100 : placement.prominence.zIndex)
    }
}
