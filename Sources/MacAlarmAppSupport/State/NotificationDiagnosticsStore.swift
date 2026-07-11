import Foundation
import MacAlarmCore

@MainActor
final class NotificationDiagnosticsStore: ObservableObject {
    @Published private(set) var snapshot: NotificationAuthorizationSnapshot?
    @Published private(set) var lastResult: NotificationTestResult?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let service = MacAlarmNotificationService()
    private var task: Task<Void, Never>?

    deinit {
        task?.cancel()
    }

    func refresh() {
        task?.cancel()
        isLoading = true
        errorMessage = nil

        let service = service
        task = Task { [weak self] in
            let snapshot = await service.authorizationSnapshot()

            guard !Task.isCancelled else {
                return
            }

            self?.snapshot = snapshot
            self?.isLoading = false
        }
    }

    func sendTestNotification() {
        task?.cancel()
        isLoading = true
        errorMessage = nil

        let service = service
        task = Task { [weak self] in
            let result: Result<NotificationTestResult, Error>
            do {
                result = .success(try await service.sendTestNotification())
            } catch {
                result = .failure(error)
            }

            guard !Task.isCancelled else {
                return
            }

            switch result {
            case .success(let testResult):
                self?.snapshot = testResult.after
                self?.lastResult = testResult
            case .failure(let error):
                self?.errorMessage = String(describing: error)
            }
            self?.isLoading = false
        }
    }
}
