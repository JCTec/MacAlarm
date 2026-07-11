import AppKit
import SwiftUI

extension MacAlarmApplicationDelegate {
    @objc func showTimelineMenuAction(_ sender: Any?) {
        showTimelineWindow()
    }

    @objc func copySelectedCSV(_ sender: Any?) {
        store.copySelectedCSV()
    }

    @objc func copyVisibleCSV(_ sender: Any?) {
        store.copyVisibleCSV()
    }

    @objc func toggleInspector(_ sender: Any?) {
        withAnimation(.easeOut(duration: 0.2)) {
            store.toggleInspector()
        }
        refreshInspectorMenuState()
    }

    @objc func toggleInspectorAutoOpen(_ sender: Any?) {
        store.toggleInspectorAutoOpen()
        refreshInspectorMenuState()
    }

    @objc func toggleInspectorSummaryHeader(_ sender: Any?) {
        withAnimation(.easeOut(duration: 0.18)) {
            store.toggleInspectorSummaryHeader()
        }
        refreshInspectorMenuState()
    }

    @objc func showLedgerIntegrity(_ sender: Any?) {
        store.ledgerIntegrityVisible = true
        showTimelineWindow()
    }

    @objc func showNotificationDiagnostics(_ sender: Any?) {
        store.notificationDiagnosticsVisible = true
        showTimelineWindow()
    }

    @objc func showTelegramSettings(_ sender: Any?) {
        store.telegramSettingsVisible = true
        showTimelineWindow()
    }

    @objc func showLast15Minutes(_ sender: Any?) {
        store.timeRange = TimeRangePreset.last15Minutes.seconds
    }

    @objc func showLastHour(_ sender: Any?) {
        store.timeRange = TimeRangePreset.lastHour.seconds
    }

    @objc func showLast6Hours(_ sender: Any?) {
        store.timeRange = TimeRangePreset.last6Hours.seconds
    }

    @objc func showLast24Hours(_ sender: Any?) {
        store.timeRange = TimeRangePreset.last24Hours.seconds
    }

    @objc func showLast7Days(_ sender: Any?) {
        store.timeRange = TimeRangePreset.last7Days.seconds
    }

    @objc func zoomIn(_ sender: Any?) {
        store.zoom = TimelineZoomLevel.next(after: store.zoom)
    }

    @objc func zoomOut(_ sender: Any?) {
        store.zoom = TimelineZoomLevel.previous(before: store.zoom)
    }

    func refreshInspectorMenuState() {
        showInspectorMenuItem?.title = store.inspectorVisible ? "Hide Inspector" : "Show Inspector"
        showInspectorMenuItem?.state = store.inspectorVisible ? .on : .off
        showInspectorMenuItem?.isEnabled =
            store.inspectorVisible || store.selectedRecord != nil || !store.visibleRecords.isEmpty
        inspectorAutoOpenMenuItem?.state = store.inspectorAutoOpens ? .on : .off
        inspectorSummaryHeaderMenuItem?.state = store.inspectorSummaryHeaderVisible ? .on : .off
    }
}
