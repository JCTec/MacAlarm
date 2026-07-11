import SwiftUI

struct TimelineCanvasView: View {
    let records: [TimelineDisplayRecord]
    let zoom: Double
    let selectedID: TimelineRecord.ID?
    let searchText: String
    let select: (TimelineRecord) -> Void
    @State private var layoutState = TimelineCanvasLayoutState.empty

    var body: some View {
        GeometryReader { geometry in
            let request = TimelineLayoutRequest(
                records: records,
                viewportWidth: geometry.size.width,
                viewportHeight: geometry.size.height,
                zoom: zoom
            )
            let signature = request.signature
            let activeLayout = layoutState.activeLayout(for: request, signature: signature)

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    TimelineCanvasContent(
                        layout: activeLayout,
                        records: records,
                        selectedID: selectedID,
                        select: select
                    )
                }
                .onChange(of: records.last?.id) { _, newValue in
                    guard let newValue, searchText.isEmpty else { return }
                    withAnimation(.easeOut(duration: 0.35)) {
                        proxy.scrollTo(newValue, anchor: .trailing)
                    }
                }
            }
            .task(id: signature) {
                let result = await MacAlarmBackgroundTask.value(priority: .userInitiated) {
                    TimelineLayoutEngine().layoutIfNotCancelled(request: request)
                }

                guard let result, !Task.isCancelled else {
                    return
                }
                layoutState.apply(result)
            }
        }
        .overlay {
            if records.isEmpty {
                EmptyTimelineState()
            }
        }
        .overlay(alignment: .trailing) {
            LiveEdge()
        }
    }
}
