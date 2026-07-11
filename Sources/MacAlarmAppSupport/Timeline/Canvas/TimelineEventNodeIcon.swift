import SwiftUI

struct TimelineEventNodeIcon: View {
    let displayRecord: TimelineDisplayRecord
    let prominence: TimelineProminence
    let selected: Bool
    let hovering: Bool

    var body: some View {
        let size = max(prominence.circleSize, 16)
        let presentation = displayRecord.presentation

        ZStack {
            Circle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .frame(width: size + 8, height: size + 8)

            Circle()
                .fill(presentation.tintColor.opacity(displayRecord.hiddenBySearch ? 0.62 : prominence.opacity))
                .frame(width: size, height: size)

            Circle()
                .stroke(
                    displayRecord.event.severity.timelineColor.opacity(selected ? 1 : 0.85),
                    lineWidth: displayRecord.event.severity >= .warning ? 2.6 : 1.2
                )
                .frame(width: size + 3, height: size + 3)

            Image(systemName: presentation.symbolName)
                .font(.system(size: max(size * 0.42, 8), weight: .semibold))
                .foregroundStyle(.white)
        }
        .shadow(color: selected ? presentation.tintColor.opacity(0.38) : .clear, radius: 12, y: 3)
        .scaleEffect(selected ? 1.08 : hovering ? 1.04 : 1)
        .animation(.spring(response: 0.24, dampingFraction: 0.78), value: selected)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .opacity(displayRecord.hiddenBySearch ? 0.7 : 1)
    }
}
