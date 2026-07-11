import SwiftUI

struct InspectorHeader: View {
    let record: TimelineRecord
    let presentation: TimelineEventPresentation

    var body: some View {
        PanelHeader(
            title: record.title,
            subtitle: record.timestamp.inspectorDateString,
            symbolName: presentation.symbolName,
            tintColor: presentation.tintColor
        )
    }
}
