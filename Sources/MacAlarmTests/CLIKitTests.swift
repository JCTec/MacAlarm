import Foundation
import MacAlarmCore

@testable import MacAlarmCLIKit

extension MacAlarmTests {
    static func runCLIKitTests(_ runner: TestRunner) async {
        await runner.run("doctor file probes report required and optional states") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let missingURL = directory.appendingPathComponent("missing-tool")
            let toolURL = directory.appendingPathComponent("tool")
            try Data("tool".utf8).write(to: toolURL)

            let missingProbe = FileProbe(url: missingURL, expectsExecutable: true)
            let nonExecutableProbe = FileProbe(url: toolURL, expectsExecutable: true)
            let directoryProbe = FileProbe(url: directory, expectsDirectory: true)
            let snapshot = FileSnapshot(
                agentBinary: missingProbe,
                controlBinary: nonExecutableProbe,
                configFile: FileProbe(url: toolURL),
                plistFile: FileProbe(url: toolURL),
                logDirectory: directoryProbe
            )

            let requiredMissing = snapshot.check(name: "agent binary", file: \.agentBinary, required: true)
            let requiredNotExecutable = snapshot.check(name: "control tool", file: \.controlBinary, required: true)
            let optionalDirectory = snapshot.check(name: "log directory", file: \.logDirectory, required: false)

            try expect(requiredMissing.status == .fail, "missing required file should fail")
            try expect(requiredMissing.message.hasPrefix("missing:"), "missing probe should explain missing path")
            try expect(requiredNotExecutable.status == .fail, "non-executable required tool should fail")
            try expect(
                requiredNotExecutable.message.hasPrefix("not executable:"),
                "non-executable probe should explain executable mismatch"
            )
            try expect(optionalDirectory.status == .pass, "existing directory should pass optional directory check")
        }

        await runner.run("doctor process summary prefers stderr and falls back") {
            let stderr = ProcessExecution(
                executable: "/bin/example",
                arguments: [],
                terminationStatus: 64,
                standardOutput: "stdout detail",
                standardError: "stderr detail\n"
            )
            let stdout = ProcessExecution(
                executable: "/bin/example",
                arguments: [],
                terminationStatus: 65,
                standardOutput: "stdout detail\n",
                standardError: "  "
            )
            let empty = ProcessExecution(
                executable: "/bin/example",
                arguments: [],
                terminationStatus: 66,
                standardOutput: "",
                standardError: ""
            )

            try expect(stderr.summary == "stderr detail", "summary should prefer stderr")
            try expect(stdout.summary == "stdout detail", "summary should fall back to stdout")
            try expect(empty.summary == "/bin/example exited 66", "summary should name empty process exits")
        }

        await runner.run("doctor ledger freshness respects heartbeat threshold") {
            let now = Date(timeIntervalSince1970: 20_000)
            let config = MacAlarmConfig(heartbeat: HeartbeatConfig(enabled: true, intervalSeconds: 60))
            let disabled = MacAlarmConfig(heartbeat: HeartbeatConfig(enabled: false, intervalSeconds: 60))
            let fresh = ledgerDoctorSnapshot(latestEventAt: now.addingTimeInterval(-180))
            let stale = ledgerDoctorSnapshot(latestEventAt: now.addingTimeInterval(-181))

            try expect(
                DoctorLedgerFreshness.staleMessage(snapshot: fresh, config: config, now: now) == nil,
                "fresh ledger should not warn at the exact threshold"
            )
            try expect(
                DoctorLedgerFreshness.staleMessage(snapshot: stale, config: disabled, now: now) == nil,
                "disabled heartbeat should not warn about freshness"
            )

            let staleMessage = DoctorLedgerFreshness.staleMessage(snapshot: stale, config: config, now: now)
            try expect(
                staleMessage == "latest event is 181s old; heartbeat interval is 60s",
                "stale ledger should explain event age and configured interval"
            )
        }

        await runner.run("doctor report renderer includes checks ledger and json") {
            let homeDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: homeDirectory) }

            let paths = MacAlarmInstallationPaths(
                label: "com.jctec.macalarm.tests",
                homeDirectory: homeDirectory,
                userID: 501
            )
            let report = DoctorReport(
                checkedAt: Date(timeIntervalSince1970: 21_000),
                sandboxed: false,
                healthy: false,
                paths: paths,
                configPath: "/tmp/macalarm/config.json",
                ledgerPath: "/tmp/macalarm/events.jsonl",
                checks: [
                    .pass("agent binary", "/tmp/macalarm/macalarm-agent", required: true),
                    .fail("launch agent", "service not found", required: true),
                ],
                launchctl: ProcessExecution(
                    executable: "/bin/launchctl",
                    arguments: ["print", paths.launchAgentService],
                    terminationStatus: 3,
                    standardOutput: "",
                    standardError: "service not found"
                ),
                notification: NotificationAuthorizationSnapshot(
                    authorizationStatus: "authorized",
                    alertSetting: "enabled",
                    soundSetting: "enabled",
                    badgeSetting: "enabled"
                ),
                ledger: ledgerDoctorSnapshot(
                    latestEventAt: Date(timeIntervalSince1970: 20_900),
                    latestEventName: "agent.agent.heartbeat"
                ),
                anchor: AnchorDoctorSnapshot(
                    enabled: true,
                    destination: "iCloudDrive: /tmp/macalarm/anchors",
                    lastStatus: "no anchor written yet"
                )
            )

            let human = DoctorReportRenderer.humanReport(report)
            let json = DoctorReportRenderer.jsonString(report)

            try expect(human.contains("MacAlarm Doctor"), "human report should include title")
            try expect(human.contains("[FAIL] launch agent: service not found"), "human report should include checks")
            try expect(
                human.contains("Latest event: agent.agent.heartbeat"),
                "human report should include latest ledger event"
            )
            try expect(human.contains("Next checks:"), "human report should include remediation commands")
            try expect(human.contains("Sandboxed: false"), "human report should include the sandboxed field")
            try expect(
                human.contains("Destination: iCloudDrive: /tmp/macalarm/anchors"),
                "human report should include the anchor destination")
            try expect(
                human.contains("Last status: no anchor written yet"), "human report should include anchor status")
            try expect(json.contains("\"healthy\" : false"), "json report should include health field")
            try expect(json.contains("\"sandboxed\" : false"), "json report should include the sandboxed field")
            try expect(json.contains("\"launchctl\""), "json report should include launchctl details")
        }
    }

    private static func ledgerDoctorSnapshot(
        latestEventAt: Date?,
        latestEventName: String? = nil
    ) -> LedgerDoctorSnapshot {
        LedgerDoctorSnapshot(
            path: "/tmp/events.jsonl",
            verification: LedgerVerification(
                isValid: true,
                recordCount: latestEventAt == nil ? 0 : 1,
                lastHash: HashChainLedger.zeroHash,
                issues: []
            ),
            latestEventAt: latestEventAt,
            latestEventName: latestEventName
        )
    }
}
