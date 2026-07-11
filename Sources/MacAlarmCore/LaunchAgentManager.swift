import Foundation

public struct LaunchAgentManager: Sendable {
    public typealias CommandRunner = @Sendable (String, [String]) async -> LaunchAgentCommandResult
    public typealias SecretInitializer = @Sendable (MacAlarmConfig) async throws -> Data

    public let paths: MacAlarmInstallationPaths
    public let launchctlPath: String
    public let plutilPath: String
    private let runCommand: CommandRunner
    private let initializeSecretIfMissing: SecretInitializer

    public init(
        paths: MacAlarmInstallationPaths = MacAlarmInstallationPaths(),
        launchctlPath: String = "/bin/launchctl",
        plutilPath: String = "/usr/bin/plutil",
        initializeSecretIfMissing: @escaping SecretInitializer = Self.ensureInstalledSecretIfMissing
    ) {
        self.init(
            paths: paths,
            launchctlPath: launchctlPath,
            plutilPath: plutilPath,
            initializeSecretIfMissing: initializeSecretIfMissing,
            runCommand: Self.runProcess
        )
    }

    public init(
        paths: MacAlarmInstallationPaths,
        launchctlPath: String = "/bin/launchctl",
        plutilPath: String = "/usr/bin/plutil",
        initializeSecretIfMissing: @escaping SecretInitializer = Self.ensureInstalledSecretIfMissing,
        runCommand: @escaping CommandRunner
    ) {
        self.paths = paths
        self.launchctlPath = launchctlPath
        self.plutilPath = plutilPath
        self.runCommand = runCommand
        self.initializeSecretIfMissing = initializeSecretIfMissing
    }

    public func status() async -> LaunchAgentServiceStatus {
        let result = await runCommand(launchctlPath, ["print", paths.launchAgentService])
        return LaunchAgentServiceStatus(
            label: paths.label,
            service: paths.launchAgentService,
            plistPath: paths.plistURL.path,
            isLoaded: result.succeeded,
            state: Self.firstValue(after: "state =", in: result.standardOutput),
            processID: Self.processID(in: result.standardOutput),
            result: result
        )
    }

    @discardableResult
    public func install(
        agentPath: String? = nil,
        configPath: String? = nil,
        createDefaultConfigIfMissing: Bool = true
    ) async throws -> [LaunchAgentCommandResult] {
        let resolvedAgentPath = agentPath ?? paths.agentExecutableURL.path
        let resolvedConfigPath = configPath ?? paths.configURL.path

        try await prepareInstalledSupport(
            agentPath: resolvedAgentPath,
            configPath: resolvedConfigPath,
            createDefaultConfigIfMissing: createDefaultConfigIfMissing
        )

        let plist = LaunchAgentPlist(executablePath: resolvedAgentPath, configPath: resolvedConfigPath)
        try await Self.writePlist(plist, to: paths.plistURL)

        var results = [LaunchAgentCommandResult]()
        results.append(try await runRequired(plutilPath, ["-lint", paths.plistURL.path]))
        results.append(contentsOf: try await start())
        return results
    }

    @discardableResult
    public func prepareInstalledSupport(
        agentPath: String? = nil,
        configPath: String? = nil,
        createDefaultConfigIfMissing: Bool = true
    ) async throws -> MacAlarmConfig {
        let resolvedAgentPath = agentPath ?? paths.agentExecutableURL.path
        let resolvedConfigPath = configPath ?? paths.configURL.path

        let config = try await Self.prepareInstall(
            paths: paths,
            agentPath: resolvedAgentPath,
            configPath: resolvedConfigPath,
            createDefaultConfigIfMissing: createDefaultConfigIfMissing
        )
        let hmacKey = try await initializeSecretIfMissing(config)
        _ = try await Self.archiveDevelopmentFallbackLedgerIfNeeded(config: config, activeHMACKey: hmacKey)
        try await Self.disableDevelopmentFallbackIfNeeded(config: config, configPath: resolvedConfigPath)
        return config
    }

    @discardableResult
    public func start() async throws -> [LaunchAgentCommandResult] {
        try await Self.requirePlistExists(paths.plistURL)
        var results = [LaunchAgentCommandResult]()
        results.append(try await runRequired(launchctlPath, ["bootstrap", paths.guiDomain, paths.plistURL.path]))
        results.append(try await runRequired(launchctlPath, ["enable", paths.launchAgentService]))
        results.append(try await runRequired(launchctlPath, ["kickstart", "-k", paths.launchAgentService]))
        return results
    }

    @discardableResult
    public func stop() async -> [LaunchAgentCommandResult] {
        [
            await runCommand(launchctlPath, ["bootout", paths.guiDomain, paths.plistURL.path]),
            await runCommand(launchctlPath, ["bootout", paths.launchAgentService]),
        ]
    }

    @discardableResult
    public func restart() async throws -> [LaunchAgentCommandResult] {
        let stopResults = await stop()
        let startResults = try await start()
        return stopResults + startResults
    }

    public func uninstall(removePlist: Bool = true) async throws -> [LaunchAgentCommandResult] {
        let results = await stop()
        if removePlist {
            await Task.detached(priority: .utility) {
                try? FileManager.default.removeItem(at: paths.plistURL)
            }.value
        }
        return results
    }

    private func runRequired(_ executable: String, _ arguments: [String]) async throws -> LaunchAgentCommandResult {
        let result = await runCommand(executable, arguments)
        guard result.succeeded else {
            throw MacAlarmError.invalidConfiguration(result.summary)
        }
        return result
    }
}
