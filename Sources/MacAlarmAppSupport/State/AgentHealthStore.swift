import Combine
import Foundation
import MacAlarmCore

@MainActor
final class AgentHealthStore: ObservableObject {
    @Published private(set) var snapshot: AgentStatusSnapshot?
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var loadError: String?

    private let statusURL: URL
    private let refreshInterval: TimeInterval
    private var refreshTask: Task<Void, Never>?

    init(
        statusURL: URL = PathResolver.fileURL(MacAlarmConfig().storage.runtimeDirectory)
            .appendingPathComponent("status.json"),
        refreshInterval: TimeInterval = 5
    ) {
        self.statusURL = statusURL
        self.refreshInterval = refreshInterval
    }

    deinit {
        refreshTask?.cancel()
    }

    func start() {
        guard refreshTask == nil else {
            return
        }

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .milliseconds(Int((self?.refreshInterval ?? 5) * 1_000)))
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh(now: Date = .now) async {
        let statusURL = self.statusURL
        let result = await MacAlarmBackgroundTask.value(priority: .utility) {
            Result<AgentStatusSnapshot?, Error> {
                guard FileManager.default.fileExists(atPath: statusURL.path) else {
                    return nil
                }
                return try AgentStatusStore.load(from: statusURL)
            }
        }

        guard !Task.isCancelled else {
            return
        }

        lastCheckedAt = now
        switch result {
        case .success(let snapshot):
            self.snapshot = snapshot
            loadError = nil
        case .failure(let error):
            snapshot = nil
            loadError = String(describing: error)
        }
    }

    var presentation: AgentHealthPresentation {
        Self.presentation(
            snapshot: snapshot,
            loadError: loadError,
            now: lastCheckedAt ?? .now
        )
    }

    nonisolated static func presentation(
        snapshot: AgentStatusSnapshot?,
        loadError: String?,
        now: Date
    ) -> AgentHealthPresentation {
        AgentHealthPresenter.presentation(snapshot: snapshot, loadError: loadError, now: now)
    }
}
