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
        label: String = "dev.jc.macalarm.agent",
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        userID: UInt32 = MacAlarmInstallationPaths.currentUserID()
    ) {
        self.label = label
        self.userID = userID
        self.homeDirectory = homeDirectory

        let installDirectory =
            homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("MacAlarm")
        let binDirectory = installDirectory.appendingPathComponent("bin", isDirectory: true)
        let logDirectory =
            homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
            .appendingPathComponent("MacAlarm", isDirectory: true)

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
        self.plistURL =
            homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
            .appendingPathComponent("\(label).plist")
        self.logDirectory = logDirectory
        self.standardOutputURL = logDirectory.appendingPathComponent("agent.out.log")
        self.standardErrorURL = logDirectory.appendingPathComponent("agent.err.log")
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
