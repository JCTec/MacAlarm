import SwiftUI

struct InspectorVerticalTimeline: View {
    let records: [TimelineDisplayRecord]
    let selectedID: TimelineRecord.ID
    let select: (TimelineRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Timeline")
                .font(.headline)

            if records.isEmpty {
                Text("No visible events.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(records) { record in
                        InspectorTimelineRow(displayRecord: record, selected: record.id == selectedID)
                            .id(record.id)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                    select(record.record)
                                }
                            }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct InspectorTimelineRow: View {
    let displayRecord: TimelineDisplayRecord
    let selected: Bool

    var body: some View {
        let presentation = displayRecord.presentation

        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Circle()
                    .fill(presentation.tintColor)
                    .frame(width: selected ? 18 : 14, height: selected ? 18 : 14)
                    .overlay {
                        Circle()
                            .stroke(
                                displayRecord.event.severity.timelineColor,
                                lineWidth: displayRecord.event.severity >= .warning ? 2 : 1)
                    }
                    .overlay {
                        Image(systemName: presentation.symbolName)
                            .font(.system(size: selected ? 8 : 7, weight: .bold))
                            .foregroundStyle(.white)
                    }
                Rectangle()
                    .fill(presentation.tintColor.opacity(selected ? 0.42 : 0.22))
                    .frame(width: 1, height: 34)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(displayRecord.title)
                    .font(.callout.weight(selected ? .semibold : .medium))
                    .lineLimit(1)
                Text(displayRecord.timestamp.timelineTimeString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(displayRecord.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
        .padding(.horizontal, selected ? 7 : 0)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.control)
                .fill(selected ? presentation.tintColor.opacity(0.10) : Color.clear)
        )
    }
}
