import Combine
import Dispatch
import Foundation
import MacAlarmCore

@MainActor
final class TimelineStore: ObservableObject {
    @Published private var recordSet = TimelineRecordSet.empty
    @Published private var derivedTimelineData = DerivedTimelineData.empty
    @Published var ledgerContinuity: LedgerVerification?
    @Published var loadError: String?
    @Published var timelineFilters: [TimelineFilterDefinition] {
        didSet {
            scheduleTimelineFiltersSave()
            scheduleDerivedTimelineUpdate()
        }
    }
    @Published var filterStates: [String: CategoryDisplayState] {
        didSet {
            scheduleFilterStatesSave()
            scheduleDerivedTimelineUpdate()
        }
    }
    @Published var searchText = "" {
        didSet {
            scheduleDerivedTimelineUpdate()
        }
    }
    @Published var selectedID: TimelineRecord.ID?
    @Published var inspectorVisible = false
    @Published var inspectorAutoOpens: Bool {
        didSet {
            preferences.saveInspectorAutoOpens(inspectorAutoOpens)
        }
    }
    @Published var inspectorSummaryHeaderVisible: Bool {
        didSet {
            preferences.saveInspectorSummaryHeaderVisible(inspectorSummaryHeaderVisible)
        }
    }
    @Published var ledgerIntegrityVisible = false
    @Published var notificationDiagnosticsVisible = false
    @Published var telegramSettingsVisible = false
    @Published var timeRange: TimeInterval = 24 * 60 * 60 {
        didSet {
            scheduleDerivedTimelineUpdate()
        }
    }
    @Published var zoom: Double = 1

    let ledgerURL: URL
    var fileSource: DispatchSourceFileSystemObject?
    var fileDescriptor: CInt = -1
    var watchedFilePath: String?
    var watchSetupTask: Task<Void, Never>?
    var reloadTask: Task<Void, Never>?
    var derivedTimelineTask: Task<Void, Never>?
    var timelineFiltersSaveTask: Task<Void, Never>?
    var filterStatesSaveTask: Task<Void, Never>?
    var pasteboardTask: Task<Void, Never>?
    let preferences: TimelinePreferences

    init(
        ledgerURL: URL = PathResolver.fileURL(MacAlarmConfig().storage.ledgerPath),
        preferences: TimelinePreferences = TimelinePreferences()
    ) {
        let filters = preferences.loadTimelineFilters()
        self.ledgerURL = ledgerURL
        self.preferences = preferences
        self.timelineFilters = filters
        self.filterStates = preferences.loadFilterStates(filters: filters)
        self.inspectorAutoOpens = preferences.loadInspectorAutoOpens()
        self.inspectorSummaryHeaderVisible = preferences.loadInspectorSummaryHeaderVisible()
    }

    deinit {
        reloadTask?.cancel()
        watchSetupTask?.cancel()
        derivedTimelineTask?.cancel()
        timelineFiltersSaveTask?.cancel()
        filterStatesSaveTask?.cancel()
        pasteboardTask?.cancel()
        fileSource?.cancel()
        fileSource = nil
        fileDescriptor = -1
        watchedFilePath = nil
    }

    var selectedRecord: TimelineRecord? {
        recordIndex.record(for: selectedID)
    }

    var records: [TimelineRecord] {
        recordSet.records
    }

    var recordIndex: TimelineRecordIndex {
        recordSet.index
    }

    var visibleRecords: [TimelineRecord] {
        derivedTimelineData.visibleRecords
    }

    var visibleDisplayRecords: [TimelineDisplayRecord] {
        derivedTimelineData.visibleDisplayRecords
    }

    var hiddenSearchResults: Set<TimelineRecord.ID> {
        derivedTimelineData.hiddenSearchResults
    }

    var displayRecordsByID: [TimelineRecord.ID: TimelineDisplayRecord] {
        derivedTimelineData.displayRecordsByID
    }

    var enabledFilters: [TimelineFilterDefinition] {
        timelineFilters.filter(\.isEnabled)
    }

    func applyDerivedTimelineData(_ data: DerivedTimelineData) {
        derivedTimelineData = data
    }

    func replaceRecords(_ recordSet: TimelineRecordSet) {
        self.recordSet = recordSet
        clearMissingSelection()
        scheduleDerivedTimelineUpdate()
    }

    func replaceRecords(_ records: [TimelineRecord]) {
        replaceRecords(TimelineRecordSet(records: records))
    }
}
