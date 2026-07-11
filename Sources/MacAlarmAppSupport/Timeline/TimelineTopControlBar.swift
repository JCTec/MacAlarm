import MacAlarmCore
import SwiftUI

struct TopControlBar: View {
    let brandSubtitle: String
    let agentPresentation: AgentHealthPresentation
    let agentSnapshot: AgentStatusSnapshot?
    let agentLoadError: String?
    let installAgent: @MainActor @Sendable () -> Void
    let startAgent: @MainActor @Sendable () -> Void
    let filters: [TimelineFilterDefinition]
    let filterState: (TimelineFilterDefinition) -> CategoryDisplayState
    let cycleFilter: (TimelineFilterDefinition) -> Void
    let timeRange: TimeInterval
    let setTimeRange: (TimeInterval) -> Void
    @Binding var zoom: Double
    @Binding var searchText: String
    let inspectorVisible: Bool
    let inspectorToggleEnabled: Bool
    let toggleInspector: () -> Void
    let continuity: LedgerVerification?
    let visibleCount: Int
    let totalCount: Int
    let loadError: String?
    let filterSettings: TimelineFilterSettingsConfiguration
    let showLedgerIntegrity: () -> Void
    @State private var showingFilterSettings = false

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.md) {
                BrandMark(subtitle: brandSubtitle)
                AgentHealthPill(
                    presentation: agentPresentation,
                    snapshot: agentSnapshot,
                    loadError: agentLoadError,
                    installAgent: installAgent,
                    startAgent: startAgent,
                    showLedgerIntegrity: showLedgerIntegrity
                )

                Divider()
                    .frame(height: 30)

                CategoryFilterBar(
                    filters: filters,
                    state: filterState,
                    cycle: cycleFilter
                )
                FilterSettingsButton {
                    showingFilterSettings = true
                }

                Spacer(minLength: AppSpacing.md)

                TimeRangeControl(timeRange: timeRange, setTimeRange: setTimeRange)
                ZoomControl(zoom: $zoom)

                SearchField(text: $searchText)
                    .frame(width: 230)

                InspectorToggleButton(
                    isVisible: inspectorVisible,
                    isEnabled: inspectorToggleEnabled,
                    toggle: toggleInspector
                )
            }
            .zIndex(20)

            TimelineStatusRow(
                continuity: continuity,
                visibleCount: visibleCount,
                totalCount: totalCount,
                loadError: loadError,
                showLedgerIntegrity: showLedgerIntegrity
            )
            .zIndex(0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.bar)
        .sheet(isPresented: $showingFilterSettings) {
            TimelineFilterSettingsView(
                visibleButtonCount: filterSettings.visibleButtonCount,
                filters: filterSettings.filters,
                state: filterSettings.state,
                setEnabled: filterSettings.setEnabled,
                cycle: filterSettings.cycle,
                delete: filterSettings.delete,
                create: filterSettings.create,
                reset: filterSettings.reset
            )
        }
    }
}
