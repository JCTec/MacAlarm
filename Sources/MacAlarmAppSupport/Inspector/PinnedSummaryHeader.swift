import SwiftUI

struct PinnedSummaryHeader: View {
    let record: TimelineRecord
    let presentation: TimelineEventPresentation

    var body: some View {
        PinnedSummaryCard(record: record, presentation: presentation)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                Rectangle()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.96))
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color(nsColor: .separatorColor).opacity(0.35))
                            .frame(height: 1)
                    }
            }
            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }
}
