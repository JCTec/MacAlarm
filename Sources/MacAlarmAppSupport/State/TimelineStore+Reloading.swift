import Foundation

extension TimelineStore {
    func start() {
        reload()
        startWatchingLedgerPath()
    }

    func reload() {
        let ledgerURL = ledgerURL
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            let result = await MacAlarmBackgroundTask.value(priority: .userInitiated) {
                Result {
                    try TimelineLedgerLoader.load(from: ledgerURL)
                }
            }

            guard !Task.isCancelled else {
                return
            }

            switch result {
            case .success(let snapshot):
                self?.replaceRecords(snapshot.recordSet)
                self?.ledgerContinuity = snapshot.continuity
                self?.loadError = nil
            case .failure(let error):
                self?.loadError = String(describing: error)
            }
        }
    }
}
