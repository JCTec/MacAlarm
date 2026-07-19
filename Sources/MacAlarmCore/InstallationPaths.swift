import Foundation

#if canImport(Darwin)
    import Darwin
#endif

public struct MacAlarmInstallationPaths: Codable, Equatable, Sendable {
    public var label: String
    public var userID: UInt32
    public var homeDirectory: URL
    public var installDirectory: URL
    public var binDirectory: URL
    public var agentBundleURL: URL
    public var agentExecutableURL: URL
    public var controlExecutableURL: URL
    public var configURL: URL
    public var defaultLedgerURL: URL
    public var plistURL: URL
    public var logDirectory: URL
    public var standardOutputURL: URL
    public var standardErrorURL: URL

    public init(
        label: String = "com.jctec.macalarm.agent",
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        userID: UInt32 = MacAlarmInstallationPaths.currentUserID()
    ) {
        self.label = label
        self.userID = userID
        self.homeDirectory = homeDirectory

        let base = MacAlarmInstallationPaths.resolveBaseDirectories(homeDirectory: homeDirectory)
        let installDirectory = base.install
        let binDirectory = installDirectory.appendingPathComponent("bin", isDirectory: true)
        let logDirectory = base.logs

        self.installDirectory = installDirectory
        self.binDirectory = binDirectory
        self.agentBundleURL = installDirectory.appendingPathComponent("MacAlarm.app", isDirectory: true)
        self.agentExecutableURL =
            agentBundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent("MacAlarm")
        self.controlExecutableURL = binDirectory.appendingPathComponent("macalarmctl")
        self.configURL = installDirectory.appendingPathComponent("config.json")
        self.defaultLedgerURL = installDirectory.appendingPathComponent("events.jsonl")
        self.plistURL = base.launchAgents.appendingPathComponent("\(label).plist")
        self.logDirectory = logDirectory
        self.standardOutputURL = logDirectory.appendingPathComponent("agent.out.log")
        self.standardErrorURL = logDirectory.appendingPathComponent("agent.err.log")
    }

    private struct BaseDirectories {
        var install: URL
        var logs: URL
        var launchAgents: URL
    }

    /// Resolves the base directories for install support, logs, and LaunchAgents.
    ///
    /// Unsandboxed builds keep the historical `~/Library` layout unchanged. Under
    /// the sandbox every path moves into the App Group container so the viewer
    /// app, recorder helper, and macalarmctl resolve identical files. When the
    /// container cannot be resolved while sandboxed we never fall back to the
    /// private container: we log the attributed failure and return an
    /// obviously-invalid sentinel base so any I/O fails loudly. Install and agent
    /// startup guard the container explicitly (throwing
    /// `MacAlarmError.appGroupUnavailable`) before real work begins.
    private static func resolveBaseDirectories(homeDirectory: URL) -> BaseDirectories {
        guard SandboxEnvironment.isSandboxed else {
            let library = homeDirectory.appendingPathComponent("Library", isDirectory: true)
            return BaseDirectories(
                install:
                    library
                    .appendingPathComponent("Application Support", isDirectory: true)
                    .appendingPathComponent("MacAlarm", isDirectory: true),
                logs:
                    library
                    .appendingPathComponent("Logs", isDirectory: true)
                    .appendingPathComponent("MacAlarm", isDirectory: true),
                launchAgents: library.appendingPathComponent("LaunchAgents", isDirectory: true)
            )
        }

        guard let container = try? MacAlarmSharedContainer.containerURL() else {
            let sentinel = MacAlarmSharedContainer.unresolvedSentinelDirectory
            return BaseDirectories(
                install: sentinel.appendingPathComponent("MacAlarm", isDirectory: true),
                logs: sentinel.appendingPathComponent("Logs", isDirectory: true),
                launchAgents: sentinel.appendingPathComponent("LaunchAgents", isDirectory: true)
            )
        }

        let support = container.appendingPathComponent("Application Support", isDirectory: true)
        return BaseDirectories(
            install: support.appendingPathComponent("MacAlarm", isDirectory: true),
            logs:
                container
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Logs", isDirectory: true)
                .appendingPathComponent("MacAlarm", isDirectory: true),
            launchAgents:
                container
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("LaunchAgents", isDirectory: true)
        )
    }

    public var guiDomain: String {
        "gui/\(userID)"
    }

    public var launchAgentService: String {
        "\(guiDomain)/\(label)"
    }

    public static func currentUserID() -> UInt32 {
        #if canImport(Darwin)
            getuid()
        #else
            0
        #endif
    }
}
