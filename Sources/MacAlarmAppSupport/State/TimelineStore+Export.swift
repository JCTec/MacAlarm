import AppKit

extension TimelineStore {
    func copySelectedCSV() {
        guard let selectedRecord else { return }
        copyCSV(records: [selectedRecord])
    }

    func copyVisibleCSV() {
        copyCSV(records: visibleRecords)
    }

    private func copyCSV(records: [TimelineRecord]) {
        pasteboardTask?.cancel()
        pasteboardTask = Task {
            let csv = await MacAlarmBackgroundTask.value(priority: .userInitiated) {
                TimelineCSVExporter.export(records: records)
            }

            guard !Task.isCancelled else {
                return
            }

            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(csv, forType: .string)
        }
    }
}
