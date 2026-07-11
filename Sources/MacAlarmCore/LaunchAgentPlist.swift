import Foundation

public struct LaunchAgentPlist: Codable, Equatable, Sendable {
    public var label: String
    public var executablePath: String
    public var configPath: String
    public var standardOutPath: String
    public var standardErrorPath: String
    public var keepAlive: Bool
    public var runAtLoad: Bool
    public var associatedBundleIdentifiers: [String]

    public init(
        label: String = "dev.jc.macalarm.agent",
        executablePath: String,
        configPath: String,
        standardOutPath: String = "~/Library/Logs/MacAlarm/agent.out.log",
        standardErrorPath: String = "~/Library/Logs/MacAlarm/agent.err.log",
        keepAlive: Bool = true,
        runAtLoad: Bool = true,
        associatedBundleIdentifiers: [String] = ["dev.jc.macalarm"]
    ) {
        self.label = label
        self.executablePath = executablePath
        self.configPath = configPath
        self.standardOutPath = standardOutPath
        self.standardErrorPath = standardErrorPath
        self.keepAlive = keepAlive
        self.runAtLoad = runAtLoad
        self.associatedBundleIdentifiers = associatedBundleIdentifiers
    }

    public func xmlString() -> String {
        let associatedBundleXML = associatedBundleIdentifiers.map {
            "        <string>\(escape($0))</string>"
        }.joined(separator: "\n")
        let associatedBundleSection =
            associatedBundleIdentifiers.isEmpty
            ? ""
            : """

                    <key>AssociatedBundleIdentifiers</key>
                    <array>
            \(associatedBundleXML)
                    </array>
            """
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>\(escape(label))</string>
            \(associatedBundleSection)
                <key>ProgramArguments</key>
                <array>
                    <string>\(escape(PathResolver.expandedPath(executablePath)))</string>
                    <string>--config</string>
                    <string>\(escape(PathResolver.expandedPath(configPath)))</string>
                </array>
                <key>RunAtLoad</key>
                <\(runAtLoad ? "true" : "false")/>
                <key>KeepAlive</key>
                <\(keepAlive ? "true" : "false")/>
                <key>StandardOutPath</key>
                <string>\(escape(PathResolver.expandedPath(standardOutPath)))</string>
                <key>StandardErrorPath</key>
                <string>\(escape(PathResolver.expandedPath(standardErrorPath)))</string>
                <key>ProcessType</key>
                <string>Background</string>
            </dict>
            </plist>
            """
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
