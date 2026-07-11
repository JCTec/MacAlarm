import SwiftUI

struct PinnedSummaryCard: View {
    let record: TimelineRecord
    let presentation: TimelineEventPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                PinnedSummaryIcon(
                    symbolName: presentation.symbolName,
                    tintColor: presentation.tintColor,
                    severity: record.event.severity
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(record.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    Text(record.subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    Text(record.category.inspectorSummaryInsight)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }

            PinnedSummaryTagRow(record: record, presentation: presentation)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.card))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: AppRadius.card)
                .fill(presentation.tintColor)
                .frame(width: 3)
        }
    }
}
