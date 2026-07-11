import Foundation

extension TimelineStore {
    func select(_ record: TimelineRecord) {
        selectedID = record.id
        if inspectorAutoOpens {
            inspectorVisible = true
        }
    }

    func hideInspector() {
        inspectorVisible = false
    }

    func toggleInspector() {
        if inspectorVisible {
            inspectorVisible = false
            return
        }

        if selectedID == nil {
            selectedID = visibleRecords.last?.id
        }

        inspectorVisible = selectedRecord != nil
    }

    func toggleInspectorAutoOpen() {
        inspectorAutoOpens.toggle()
    }

    func toggleInspectorSummaryHeader() {
        inspectorSummaryHeaderVisible.toggle()
    }

    func clearMissingSelection() {
        guard selectedID != nil, selectedRecord == nil else {
            return
        }

        selectedID = nil
        inspectorVisible = false
    }
}
