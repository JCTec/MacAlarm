import Foundation
import MacAlarmCore

#if canImport(Darwin)
    import Darwin
#endif

struct AgentStatusReport: Codable, Sendable {
    var checkedAt: Date
    var configPath: String
    var statusPath: String
    var statusFileExists: Bool
    var statusAgeSeconds: TimeInterval?
    var heartbeatAgeSeconds: TimeInterval?
    var expectedHeartbeatAgeSeconds: TimeInterval?
    var launchAgentLoaded: Bool
    var launchAgentProcessID: Int32?
    var statusMatchesLaunchAgent: Bool?
    var processRunning: Bool?
    var isHeartbeatFresh: Bool
    var isCurrent: Bool
    var snapshot: AgentStatusSnapshot?
}

struct AgentStatusReportBuilder {
    var configPath: String?

    func build(checkedAt: Date = .now) async -> AgentStatusReport {
        let paths = MacAlarmInstallationPaths()
        let configURL = URL(fileURLWithPath: configPath ?? paths.configURL.path)
        let config = await loadConfig(from: configURL)
        let runtimeDirectory =
            config.map { PathResolver.fileURL($0.storage.runtimeDirectory) }
            ?? paths.installDirectory.appendingPathComponent("runtime", isDirectory: true)
        let statusURL = runtimeDirectory.appendingPathComponent("status.json")
        let status = await loadStatus(from: statusURL)
        let launchAgentStatus = await LaunchAgentManager(paths: paths).status()
        let processRunning = status.map { Self.processIsRunning(processID: $0.processID) }
        let statusAgeSeconds = status.map { checkedAt.timeIntervalSince($0.generatedAt) }
        let heartbeatAgeSeconds = status?.latestHeartbeatAt.map { checkedAt.timeIntervalSince($0) }
        let expectedHeartbeatAgeSeconds = status?.heartbeatIntervalSeconds.map { max($0 * 2, 180) }
        let isHeartbeatFresh =
            if let heartbeatAgeSeconds, let expectedHeartbeatAgeSeconds {
                heartbeatAgeSeconds <= expectedHeartbeatAgeSeconds
            } else {
                status?.heartbeatIntervalSeconds == nil
            }
        let statusMatchesLaunchAgent =
            if let status, let launchAgentProcessID = launchAgentStatus.processID {
                status.processID == launchAgentProcessID
            } else {
                Optional<Bool>.none
            }

        let isCurrent =
            status != nil
            && status?.state == .running
            && processRunning == true
            && isHeartbeatFresh
            && statusMatchesLaunchAgent != false

        return AgentStatusReport(
            checkedAt: checkedAt,
            configPath: configURL.path,
            statusPath: statusURL.path,
            statusFileExists: status != nil,
            statusAgeSeconds: statusAgeSeconds,
            heartbeatAgeSeconds: heartbeatAgeSeconds,
            expectedHeartbeatAgeSeconds: expectedHeartbeatAgeSeconds,
            launchAgentLoaded: launchAgentStatus.isLoaded,
            launchAgentProcessID: launchAgentStatus.processID,
            statusMatchesLaunchAgent: statusMatchesLaunchAgent,
            processRunning: processRunning,
            isHeartbeatFresh: isHeartbeatFresh,
            isCurrent: isCurrent,
            snapshot: status
        )
    }

    private func loadConfig(from url: URL) async -> MacAlarmConfig? {
        await Task.detached(priority: .utility) {
            try? MacAlarmConfig.load(from: url)
        }.value
    }

    private func loadStatus(from url: URL) async -> AgentStatusSnapshot? {
        await Task.detached(priority: .utility) {
            try? AgentStatusStore.load(from: url)
        }.value
    }

    private static func processIsRunning(processID: Int32) -> Bool {
        guard processID > 0 else {
            return false
        }

        #if canImport(Darwin)
            return kill(processID, 0) == 0 || errno == EPERM
        #else
            return true
        #endif
    }
}
