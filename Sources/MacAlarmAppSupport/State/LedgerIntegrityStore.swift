import Foundation
import MacAlarmCore

@MainActor
final class LedgerIntegrityStore: ObservableObject {
    @Published private(set) var snapshot: LedgerIntegritySnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let proofService: MacAlarmProofService
    private var refreshTask: Task<Void, Never>?

    init(launchAgentLabel: String = "com.jc-tec.macalarm.agent") {
        self.proofService = MacAlarmProofService(launchAgentLabel: launchAgentLabel)
    }

    deinit {
        refreshTask?.cancel()
    }

    func refresh() {
        refreshTask?.cancel()
        isLoading = true
        errorMessage = nil

        let proofService = proofService
        refreshTask = Task { [weak self] in
            let result: Result<LedgerIntegritySnapshot, Error>
            do {
                result = .success(try await proofService.inspectLedger())
            } catch {
                result = .failure(error)
            }

            guard !Task.isCancelled else {
                return
            }

            switch result {
            case .success(let snapshot):
                self?.snapshot = snapshot
                self?.errorMessage = nil
            case .failure(let error):
                self?.errorMessage = error.localizedDescription
            }
            self?.isLoading = false
        }
    }
}
