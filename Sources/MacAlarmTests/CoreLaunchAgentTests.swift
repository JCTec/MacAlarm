import Foundation

@testable import MacAlarmCore

#if canImport(Darwin)
    import Darwin
#endif

extension MacAlarmTests {
    static func runCoreLaunchAgentTests(_ runner: TestRunner) async {
        await runner.run("launch agent plist contains agent and config paths") {
            let plist = LaunchAgentPlist(
                executablePath: "/tmp/macalarm-agent",
                configPath: "/tmp/macalarm.json"
            ).xmlString()

            try expect(plist.contains("/tmp/macalarm-agent"), "plist should include agent path")
            try expect(plist.contains("/tmp/macalarm.json"), "plist should include config path")
            try expect(plist.contains("<key>KeepAlive</key>"), "plist should include KeepAlive")
            try expect(
                plist.contains("<key>AssociatedBundleIdentifiers</key>"),
                "plist should associate the background item with the app bundle"
            )
            try expect(plist.contains("dev.jc.macalarm"), "plist should include app bundle identifier")
        }

        await runner.run("launch agent manager builds stable lifecycle commands") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let paths = MacAlarmInstallationPaths(label: "example.agent", homeDirectory: directory, userID: 501)
            try FileManager.default.createDirectory(
                at: paths.plistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try LaunchAgentPlist(executablePath: "/tmp/agent", configPath: "/tmp/config.json")
                .xmlString()
                .write(to: paths.plistURL, atomically: true, encoding: .utf8)

            let recorder = LaunchAgentCommandRecorder(service: paths.launchAgentService)
            let manager = LaunchAgentManager(
                paths: paths,
                launchctlPath: "/bin/launchctl-test",
                initializeSecretIfMissing: { _ in Data("unused-test-key".utf8) },
                runCommand: { executable, arguments in
                    await recorder.run(executable: executable, arguments: arguments)
                }
            )

            let status = await manager.status()
            _ = try await manager.start()
            _ = await manager.stop()

            try expect(status.isLoaded, "status should treat successful print as loaded")
            try expect(status.state == "running", "status should parse launchctl state")
            try expect(status.processID == 42, "status should parse launchctl pid")

            let calls = await recorder.calls
            try expect(
                calls.map(\.arguments) == [
                    ["print", paths.launchAgentService],
                    ["bootstrap", paths.guiDomain, paths.plistURL.path],
                    ["enable", paths.launchAgentService],
                    ["kickstart", "-k", paths.launchAgentService],
                    ["bootout", paths.guiDomain, paths.plistURL.path],
                    ["bootout", paths.launchAgentService],
                ],
                "manager should issue stable launchctl lifecycle commands"
            )
        }

        await runner.run("launch agent status parser extracts state and pid") {
            let output = """
                gui/501/example.agent = {
                    state = running
                    pid = 42
                }
                """

            try expect(
                LaunchAgentManager.firstValue(after: "state =", in: output) == "running",
                "status parser should extract launchctl state"
            )
            try expect(
                LaunchAgentManager.processID(in: output) == 42,
                "status parser should extract launchctl pid"
            )
            try expect(
                LaunchAgentManager.processID(in: "pid = not-a-number") == nil,
                "status parser should reject malformed pid values"
            )
        }

        await runner.run("launch agent command result summary is stable") {
            let stderr = LaunchAgentCommandResult(
                executable: "/bin/launchctl",
                arguments: ["print", "service"],
                terminationStatus: 3,
                standardOutput: "stdout detail",
                standardError: "stderr detail\n"
            )
            let stdout = LaunchAgentCommandResult(
                executable: "/bin/launchctl",
                arguments: ["print", "service"],
                terminationStatus: 4,
                standardOutput: "stdout detail\n",
                standardError: "  "
            )
            let empty = LaunchAgentCommandResult(
                executable: "/bin/launchctl",
                arguments: [],
                terminationStatus: 5,
                standardOutput: "",
                standardError: ""
            )

            try expect(stderr.summary == "stderr detail", "summary should prefer stderr")
            try expect(stdout.summary == "stdout detail", "summary should fall back to stdout")
            try expect(empty.summary == "/bin/launchctl exited 5", "summary should describe empty process output")
        }

        await runner.run("launch agent manager install writes default config, initializes secret, and plist") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let paths = MacAlarmInstallationPaths(label: "example.agent", homeDirectory: directory, userID: 501)
            try createInstalledAgentStub(at: paths)

            let recorder = LaunchAgentCommandRecorder(service: paths.launchAgentService)
            let secretRecorder = LaunchAgentSecretRecorder()
            let manager = LaunchAgentManager(
                paths: paths,
                launchctlPath: "/bin/launchctl-test",
                plutilPath: "/usr/bin/plutil-test",
                initializeSecretIfMissing: { config in
                    await secretRecorder.record(config)
                    return Data("production-test-key".utf8)
                },
                runCommand: { executable, arguments in
                    await recorder.run(executable: executable, arguments: arguments)
                }
            )

            _ = try await manager.install()

            try expect(FileManager.default.fileExists(atPath: paths.configURL.path), "install should create config")
            try expect(FileManager.default.fileExists(atPath: paths.plistURL.path), "install should write plist")
            try expect(paths.configURL.fileMode == Int(S_IRUSR | S_IWUSR), "config should be mode 0600")
            try expect(paths.plistURL.fileMode == 0o644, "plist should be mode 0644")

            let plist = try String(contentsOf: paths.plistURL, encoding: .utf8)
            try expect(plist.contains(paths.agentExecutableURL.path), "plist should point at installed agent")
            try expect(plist.contains(paths.configURL.path), "plist should point at config")

            let calls = await recorder.calls
            try expect(
                calls.map(\.arguments).prefix(4) == [
                    ["-lint", paths.plistURL.path],
                    ["bootstrap", paths.guiDomain, paths.plistURL.path],
                    ["enable", paths.launchAgentService],
                    ["kickstart", "-k", paths.launchAgentService],
                ],
                "install should lint plist then start service"
            )

            let secretConfigs = await secretRecorder.configs
            try expect(secretConfigs.count == 1, "install should initialize configured HMAC secret before start")
            try expect(
                secretConfigs.first?.secrets.hmacKeyAccount == "ledger-hmac-key",
                "secret initializer should receive installed config"
            )
        }

        await runner.run("launch agent manager install disables development fallback after secret init") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let paths = MacAlarmInstallationPaths(label: "example.agent", homeDirectory: directory, userID: 501)
            try createInstalledAgentStub(at: paths)

            var config = MacAlarmConfig(secrets: SecretConfig(allowDevelopmentFallbackKey: true))
            config.storage.ledgerPath = paths.defaultLedgerURL.path
            try config.write(to: paths.configURL)

            let recorder = LaunchAgentCommandRecorder(service: paths.launchAgentService)
            let secretRecorder = LaunchAgentSecretRecorder()
            let manager = LaunchAgentManager(
                paths: paths,
                launchctlPath: "/bin/launchctl-test",
                plutilPath: "/usr/bin/plutil-test",
                initializeSecretIfMissing: { config in
                    await secretRecorder.record(config)
                    return Data("production-test-key".utf8)
                },
                runCommand: { executable, arguments in
                    await recorder.run(executable: executable, arguments: arguments)
                }
            )

            _ = try await manager.install()

            let installedConfig = try MacAlarmConfig.load(from: paths.configURL)
            let secretConfigs = await secretRecorder.configs
            try expect(
                secretConfigs.first?.secrets.allowDevelopmentFallbackKey == true,
                "install should initialize key before hardening config")
            try expect(
                !installedConfig.secrets.allowDevelopmentFallbackKey,
                "install should disable development fallback once a real key exists"
            )
        }

        await runner.run("launch agent manager install drops legacy keychain config field") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let paths = MacAlarmInstallationPaths(label: "example.agent", homeDirectory: directory, userID: 501)
            try createInstalledAgentStub(at: paths)

            var config = MacAlarmConfig(secrets: SecretConfig(allowDevelopmentFallbackKey: false))
            config.storage.ledgerPath = paths.defaultLedgerURL.path
            try writeLegacyKeychainConfig(config, to: paths.configURL)

            let recorder = LaunchAgentCommandRecorder(service: paths.launchAgentService)
            let manager = LaunchAgentManager(
                paths: paths,
                launchctlPath: "/bin/launchctl-test",
                plutilPath: "/usr/bin/plutil-test",
                initializeSecretIfMissing: { _ in Data("production-test-key".utf8) },
                runCommand: { executable, arguments in
                    await recorder.run(executable: executable, arguments: arguments)
                }
            )

            _ = try await manager.install()

            let installedConfig = try String(contentsOf: paths.configURL, encoding: .utf8)
            let decoded = try MacAlarmConfig.load(from: paths.configURL)
            try expect(!installedConfig.contains("keychainService"), "install should drop obsolete Keychain config")
            try expect(
                decoded.storage.ledgerPath == paths.defaultLedgerURL.path, "install should keep supported config")
        }

        await runner.run("launch agent manager archives development fallback ledger before hardening") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let paths = MacAlarmInstallationPaths(label: "example.agent", homeDirectory: directory, userID: 501)
            try createInstalledAgentStub(at: paths)

            var config = MacAlarmConfig(secrets: SecretConfig(allowDevelopmentFallbackKey: true))
            config.storage.ledgerPath = paths.defaultLedgerURL.path
            try config.write(to: paths.configURL)

            let fallbackLedger = try HashChainLedger(
                fileURL: paths.defaultLedgerURL,
                hmacKey: SecretMaterial.developmentHMACKey(identity: config.identity)
            )
            _ = try await fallbackLedger.append(
                AlarmEvent(source: "agent", name: "agent.started", severity: .notice)
            )

            let recorder = LaunchAgentCommandRecorder(service: paths.launchAgentService)
            let manager = LaunchAgentManager(
                paths: paths,
                launchctlPath: "/bin/launchctl-test",
                plutilPath: "/usr/bin/plutil-test",
                initializeSecretIfMissing: { _ in Data("production-test-key".utf8) },
                runCommand: { executable, arguments in
                    await recorder.run(executable: executable, arguments: arguments)
                }
            )

            _ = try await manager.install()

            let activeLedger = try HashChainLedger(
                fileURL: paths.defaultLedgerURL,
                hmacKey: Data("production-test-key".utf8)
            )
            let activeVerification = try await activeLedger.verify()
            try expect(activeVerification.isValid, "active production ledger should verify after migration")
            try expect(activeVerification.recordCount == 0, "active production ledger should start empty")

            let archiveDirectory = paths.defaultLedgerURL
                .deletingLastPathComponent()
                .appendingPathComponent("archives", isDirectory: true)
            let archiveNames = try FileManager.default.contentsOfDirectory(atPath: archiveDirectory.path)
            try expect(archiveNames.count == 1, "install should keep exactly one archived legacy ledger")
            try expect(
                archiveNames[0].contains("development-fallback"),
                "archived legacy ledger should name the fallback migration"
            )

            let archivedLedgerURL = archiveDirectory.appendingPathComponent(archiveNames[0])
            let archivedLedger = try HashChainLedger(
                fileURL: archivedLedgerURL,
                hmacKey: SecretMaterial.developmentHMACKey(identity: config.identity)
            )
            let archivedVerification = try await archivedLedger.verify()
            try expect(archivedVerification.isValid, "archived fallback ledger should still verify")
            try expect(archivedVerification.recordCount == 1, "archived fallback ledger should keep records")
        }

        await runner.run("launch agent archive names avoid collisions") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let archiveDirectory = directory.appendingPathComponent("archives", isDirectory: true)
            try FileManager.default.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)

            let ledgerURL = directory.appendingPathComponent("events.jsonl")
            let now = Date(timeIntervalSince1970: 1_704_067_200)
            let first = LaunchAgentManager.uniqueArchiveURL(
                for: ledgerURL,
                archiveDirectory: archiveDirectory,
                now: now,
                fileManager: .default
            )
            try Data().write(to: first)

            let second = LaunchAgentManager.uniqueArchiveURL(
                for: ledgerURL,
                archiveDirectory: archiveDirectory,
                now: now,
                fileManager: .default
            )

            try expect(
                first.lastPathComponent == "events.jsonl.development-fallback-20240101T000000Z",
                "first archive name should use the stable UTC timestamp"
            )
            try expect(
                second.lastPathComponent == "events.jsonl.development-fallback-20240101T000000Z-2",
                "archive names should increment when timestamp names collide"
            )
        }

        await runner.run("installation paths derive user launch agent locations") {
            let home = URL(fileURLWithPath: "/tmp/macal-test-home", isDirectory: true)
            let paths = MacAlarmInstallationPaths(label: "example.agent", homeDirectory: home, userID: 501)

            try expect(paths.guiDomain == "gui/501", "gui domain should include user id")
            try expect(paths.launchAgentService == "gui/501/example.agent", "service should include label")
            try expect(
                paths.configURL.path == "/tmp/macal-test-home/Library/Application Support/MacAlarm/config.json",
                "config should live in Application Support"
            )
            try expect(
                paths.agentBundleURL.path == "/tmp/macal-test-home/Library/Application Support/MacAlarm/MacAlarm.app",
                "agent bundle should live in Application Support"
            )
            try expect(
                paths.agentExecutableURL.path
                    == "/tmp/macal-test-home/Library/Application Support/MacAlarm/MacAlarm.app/Contents/MacOS/MacAlarm",
                "agent executable should live inside the installed helper app bundle"
            )
            try expect(
                paths.plistURL.path == "/tmp/macal-test-home/Library/LaunchAgents/example.agent.plist",
                "plist should live in user LaunchAgents"
            )
        }
    }
}

private actor LaunchAgentSecretRecorder {
    private(set) var configs: [MacAlarmConfig] = []

    func record(_ config: MacAlarmConfig) {
        configs.append(config)
    }
}

private actor LaunchAgentCommandRecorder {
    struct Call: Sendable {
        var executable: String
        var arguments: [String]
    }

    private let service: String
    private(set) var calls = [Call]()

    init(service: String) {
        self.service = service
    }

    func run(executable: String, arguments: [String]) -> LaunchAgentCommandResult {
        calls.append(Call(executable: executable, arguments: arguments))
        let output =
            arguments == ["print", service]
            ? "\(service) = {\n\tstate = running\n\tpid = 42\n}\n"
            : "ok"

        return LaunchAgentCommandResult(
            executable: executable,
            arguments: arguments,
            terminationStatus: 0,
            standardOutput: output,
            standardError: ""
        )
    }
}

private func createInstalledAgentStub(at paths: MacAlarmInstallationPaths) throws {
    try FileManager.default.createDirectory(
        at: paths.agentExecutableURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    _ = FileManager.default.createFile(atPath: paths.agentExecutableURL.path, contents: Data())
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: paths.agentExecutableURL.path
    )
}

private func writeLegacyKeychainConfig(_ config: MacAlarmConfig, to url: URL) throws {
    let data = try config.prettyPrintedJSON()
    guard
        var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        var secrets = object["secrets"] as? [String: Any]
    else {
        throw TestFailure(description: "config should serialize to a JSON object")
    }

    secrets["keychainService"] = "dev.jc.macalarm.legacy"
    object["secrets"] = secrets

    let legacyData = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try legacyData.write(to: url, options: [.atomic])
}
