import SwiftUI

struct PinnedSummaryTagRow: View {
    let record: TimelineRecord
    let presentation: TimelineEventPresentation

    var body: some View {
        HStack {
            Tag(record.event.severity.rawValue.uppercased(), color: record.event.severity.timelineColor)
            Tag(presentation.title, color: presentation.tintColor)
            Tag(record.event.source, color: .secondary)
        }
    }
}
