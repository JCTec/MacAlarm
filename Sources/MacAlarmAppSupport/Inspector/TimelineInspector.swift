import SwiftUI

struct TimelineInspector: View {
    let record: TimelineRecord
    let presentation: TimelineEventPresentation
    let visibleRecords: [TimelineDisplayRecord]
    let summaryHeaderVisible: Bool
    let select: (TimelineRecord) -> Void

    var body: some View {
        VStack(spacing: 0) {
            InspectorHeader(record: record, presentation: presentation)
            AppSeparator()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: pinnedViews) {
                        Section {
                            inspectorContent
                                .padding(.horizontal, 16)
                                .padding(.top, summaryHeaderVisible ? 8 : 16)
                                .padding(.bottom, 16)
                        } header: {
                            if summaryHeaderVisible {
                                PinnedSummaryHeader(record: record, presentation: presentation)
                                    .id("summary-\(record.id)")
                            }
                        }
                    }
                }
                .onAppear {
                    proxy.scrollTo(record.id, anchor: .center)
                }
                .onChange(of: record.id) { _, newValue in
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
    }

    private var pinnedViews: PinnedScrollableViews {
        summaryHeaderVisible ? [.sectionHeaders] : []
    }

    private var inspectorContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            InspectorVerticalTimeline(
                records: visibleRecords,
                selectedID: record.id,
                select: select
            )

            HashProofSection(record: record)

            MetadataSection(record: record)
        }
    }
}
