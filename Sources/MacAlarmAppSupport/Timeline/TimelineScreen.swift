import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: TimelineStore
    @EnvironmentObject private var healthStore: AgentHealthStore
    let appActions: MacAlarmAppActions

    var body: some View {
        VStack(spacing: 0) {
            TopControlBar(
                brandSubtitle: store.ledgerContinuity?.isValid == false ? "Chain issue" : "Live ledger",
                agentPresentation: healthStore.presentation,
                agentSnapshot: healthStore.snapshot,
                agentLoadError: healthStore.loadError,
                installAgent: appActions.installAgent,
                startAgent: appActions.startAgent,
                filters: store.enabledFilters,
                filterState: { store.filterState(for: $0) },
                cycleFilter: { store.cycle($0) },
                timeRange: store.timeRange,
                setTimeRange: { store.timeRange = $0 },
                zoom: $store.zoom,
                searchText: $store.searchText,
                inspectorVisible: store.inspectorVisible,
                inspectorToggleEnabled: store.inspectorVisible || store.selectedRecord != nil
                    || !store.visibleRecords.isEmpty,
                toggleInspector: { store.toggleInspector() },
                continuity: store.ledgerContinuity,
                visibleCount: store.visibleRecords.count,
                totalCount: store.records.count,
                loadError: store.loadError,
                filterSettings: TimelineFilterSettingsConfiguration(
                    visibleButtonCount: store.enabledFilters.count,
                    filters: store.timelineFilters,
                    state: { store.filterState(for: $0) },
                    setEnabled: { store.setFilterEnabled($0, enabled: $1) },
                    cycle: { store.cycle($0) },
                    delete: { store.deleteFilter($0) },
                    create: { store.addFilter($0) },
                    reset: { store.resetFiltersToDefaults() }
                ),
                showLedgerIntegrity: { store.ledgerIntegrityVisible = true }
            )
            if shouldShowAgentSetupBanner {
                AgentSetupBanner(
                    presentation: healthStore.presentation,
                    installAgent: appActions.installAgent,
                    startAgent: appActions.startAgent
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            AppSeparator()
            HStack(spacing: 0) {
                TimelineCanvasView(
                    records: store.visibleDisplayRecords,
                    zoom: store.zoom,
                    selectedID: store.selectedID,
                    searchText: store.searchText
                ) { record in
                    store.select(record)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if store.inspectorVisible, let selected = store.selectedRecord {
                    Divider()
                    TimelineInspector(
                        record: selected,
                        presentation: store.presentation(for: selected),
                        visibleRecords: store.visibleDisplayRecords,
                        summaryHeaderVisible: store.inspectorSummaryHeaderVisible
                    ) { record in
                        store.select(record)
                    }
                    .frame(width: 380)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .background(MacAlarmBackground())
        .sheet(isPresented: $store.ledgerIntegrityVisible) {
            LedgerIntegrityView(
                ledgerPath: store.ledgerURL.path,
                fallbackRecordCount: store.records.count,
                exportProofBundle: appActions.exportProofBundle
            )
        }
        .sheet(isPresented: $store.notificationDiagnosticsVisible) {
            NotificationDiagnosticsView(openNotificationSettings: appActions.openNotificationSettings)
        }
        .sheet(isPresented: $store.telegramSettingsVisible) {
            TelegramSettingsView()
        }
    }

    private var shouldShowAgentSetupBanner: Bool {
        guard healthStore.lastCheckedAt != nil else {
            return false
        }

        return healthStore.presentation.level == .unknown
            || healthStore.presentation.level == .critical
    }
}

private struct AgentSetupBanner: View {
    let presentation: AgentHealthPresentation
    let installAgent: @MainActor @Sendable () -> Void
    let startAgent: @MainActor @Sendable () -> Void

    var body: some View {
        let content = RecorderSetupBannerContent.content(for: presentation)

        HStack(spacing: AppSpacing.md) {
            IconTile(
                symbolName: "shield.lefthalf.filled.badge.checkmark",
                tintColor: .accentColor,
                size: 28
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(content.title)
                    .font(.callout.weight(.semibold))
                Text(content.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: AppSpacing.md)

            Button {
                switch content.action {
                case .install:
                    installAgent()
                case .start:
                    startAgent()
                }
            } label: {
                Label(content.buttonTitle, systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help(content.help)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.24))
                .frame(height: 1)
        }
    }

}
