import AppKit
import Foundation
import MacAlarmCore

@testable import MacAlarmAppSupport

extension MacAlarmTests {
    static func runAppSupportTests(_ runner: TestRunner) async {
        await runner.run("main menu exposes enabled proof export command") {
            try await MainActor.run {
                let delegate = MacAlarmApplicationDelegate()
                delegate.configureMainMenu()
                defer {
                    NSApplication.shared.mainMenu = nil
                }

                let mainMenu = try require(NSApplication.shared.mainMenu, "main menu should exist")
                let topMenuTitles = mainMenu.items.compactMap(\.submenu?.title)
                try expect(
                    topMenuTitles == ["MacAlarm", "File", "Edit", "View", "Timeline", "Notifications", "Recorder"],
                    "main menu builder should keep stable top-level menu order"
                )

                let fileMenu = try require(
                    mainMenu.items.compactMap(\.submenu).first { $0.title == "File" },
                    "file menu should exist"
                )
                let exportItem = try require(
                    fileMenu.item(withTitle: "Export Proof Bundle..."),
                    "file menu should contain proof export"
                )

                try expect(!fileMenu.autoenablesItems, "file menu should not auto-disable proof export")
                try expect(exportItem.isEnabled, "proof export menu item should be enabled")
                try expect(exportItem.target === delegate, "proof export should target the app delegate")
                try expect(
                    exportItem.action == #selector(MacAlarmApplicationDelegate.exportProofBundle(_:)),
                    "proof export should call exportProofBundle"
                )

                let viewMenu = try require(
                    mainMenu.items.compactMap(\.submenu).first { $0.title == "View" },
                    "view menu should exist"
                )
                let integrityItem = try require(
                    viewMenu.item(withTitle: "Show Ledger Integrity"),
                    "view menu should contain ledger integrity"
                )

                try expect(integrityItem.isEnabled, "ledger integrity menu item should be enabled")
                try expect(integrityItem.target === delegate, "ledger integrity should target the app delegate")
                try expect(viewMenu.delegate === delegate, "view menu delegate should target the app delegate")
                try expect(
                    integrityItem.action == #selector(MacAlarmApplicationDelegate.showLedgerIntegrity(_:)),
                    "ledger integrity should call showLedgerIntegrity"
                )

                let editMenu = try require(
                    mainMenu.items.compactMap(\.submenu).first { $0.title == "Edit" },
                    "edit menu should exist"
                )
                let copySelectedItem = try require(
                    editMenu.item(withTitle: "Copy Selected Event as CSV"),
                    "edit menu should contain selected CSV copy"
                )
                let copyVisibleItem = try require(
                    editMenu.item(withTitle: "Copy Visible Events as CSV"),
                    "edit menu should contain visible CSV copy"
                )

                try expect(
                    copySelectedItem.action == #selector(MacAlarmApplicationDelegate.copySelectedCSV(_:)),
                    "selected CSV copy should call copySelectedCSV"
                )
                try expect(
                    copyVisibleItem.action == #selector(MacAlarmApplicationDelegate.copyVisibleCSV(_:)),
                    "visible CSV copy should call copyVisibleCSV"
                )

                let timelineMenu = try require(
                    mainMenu.items.compactMap(\.submenu).first { $0.title == "Timeline" },
                    "timeline menu should exist"
                )
                let last24HoursItem = try require(
                    timelineMenu.item(withTitle: "Last 24 Hours"),
                    "timeline menu should contain 24-hour range"
                )
                let last7DaysItem = try require(
                    timelineMenu.item(withTitle: "Last 7 Days"),
                    "timeline menu should contain 7-day range"
                )
                let zoomInItem = try require(
                    timelineMenu.item(withTitle: "Zoom In"),
                    "timeline menu should contain zoom in"
                )

                try expect(
                    last24HoursItem.action == #selector(MacAlarmApplicationDelegate.showLast24Hours(_:)),
                    "24-hour range should call showLast24Hours"
                )
                try expect(
                    last7DaysItem.action == #selector(MacAlarmApplicationDelegate.showLast7Days(_:)),
                    "7-day range should call showLast7Days"
                )
                try expect(
                    zoomInItem.action == #selector(MacAlarmApplicationDelegate.zoomIn(_:)),
                    "zoom in should call zoomIn"
                )

                let notificationsMenu = try require(
                    mainMenu.items.compactMap(\.submenu).first { $0.title == "Notifications" },
                    "notifications menu should exist"
                )
                let statusItem = try require(
                    notificationsMenu.item(withTitle: "Notification Status"),
                    "notifications menu should contain status"
                )
                let testItem = try require(
                    notificationsMenu.item(withTitle: "Send Test Notification"),
                    "notifications menu should contain test notification"
                )
                let settingsItem = try require(
                    notificationsMenu.item(withTitle: "Open System Notification Settings"),
                    "notifications menu should contain settings"
                )

                try expect(statusItem.isEnabled, "notification status menu item should be enabled")
                try expect(testItem.isEnabled, "test notification menu item should be enabled")
                try expect(settingsItem.isEnabled, "notification settings menu item should be enabled")
                try expect(
                    statusItem.action == #selector(MacAlarmApplicationDelegate.showNotificationDiagnostics(_:)),
                    "notification status should call showNotificationDiagnostics"
                )
                try expect(
                    testItem.action == #selector(MacAlarmApplicationDelegate.sendTestNotification(_:)),
                    "test notification should call sendTestNotification"
                )
                try expect(
                    settingsItem.action == #selector(MacAlarmApplicationDelegate.openNotificationSettings(_:)),
                    "notification settings should call openNotificationSettings"
                )

                let recorderMenu = try require(
                    mainMenu.items.compactMap(\.submenu).first { $0.title == "Recorder" },
                    "recorder menu should exist"
                )
                let startOrRestartItem = try require(
                    recorderMenu.item(withTitle: "Start or Restart Recorder"),
                    "recorder menu should expose a start or restart action"
                )
                try expect(
                    startOrRestartItem.action == #selector(MacAlarmApplicationDelegate.restartAgent(_:)),
                    "start or restart recorder should use the restart control path"
                )
            }
        }

        await runner.run("time range presets are stable and selectable") {
            let presets = TimeRangePreset.toolbarPresets
            let expectedDurations: [TimeInterval] = [
                15 * 60,
                60 * 60,
                6 * 60 * 60,
                24 * 60 * 60,
                7 * 24 * 60 * 60,
            ]

            try expect(
                presets.map(\.id) == ["15m", "1h", "6h", "24h", "7d"],
                "toolbar presets should keep stable order"
            )
            try expect(
                presets.map(\.seconds) == expectedDurations,
                "toolbar presets should keep expected durations"
            )
            try expect(TimeRangePreset.last24Hours.isSelected(24 * 60 * 60 + 0.25), "preset should tolerate drift")
            try expect(
                !TimeRangePreset.last24Hours.isSelected(24 * 60 * 60 + 0.5),
                "preset selection tolerance should be strict at the boundary"
            )
            try expect(TimeRangePreset.last7Days.menuTitle == "Last 7 Days", "7-day menu title should be stable")
        }

        await runner.run("agent status message formats loaded and unloaded states") {
            let loaded = AgentStatusMessage(
                service: "gui/501/dev.jc.macalarm.agent",
                plistPath: "/Users/test/Library/LaunchAgents/dev.jc.macalarm.agent.plist",
                isLoaded: true,
                state: "running",
                processID: 123,
                detail: "unused"
            )
            let unloaded = AgentStatusMessage(
                service: "gui/501/dev.jc.macalarm.agent",
                plistPath: "/Users/test/Library/LaunchAgents/dev.jc.macalarm.agent.plist",
                isLoaded: false,
                state: nil,
                processID: nil,
                detail: "service not found"
            )

            try expect(loaded.text.contains("Loaded: yes"), "loaded status should include positive loaded state")
            try expect(loaded.text.contains("Recorder: running"), "loaded status should include plain readiness")
            try expect(loaded.text.contains("Next: No action needed."), "running status should not ask for action")
            try expect(loaded.text.contains("State: running"), "loaded status should include launchctl state")
            try expect(loaded.text.contains("PID: 123"), "loaded status should include process id")
            try expect(!loaded.text.contains("Detail:"), "loaded status should not show launchctl detail")
            try expect(unloaded.text.contains("Loaded: no"), "unloaded status should include negative loaded state")
            try expect(
                unloaded.text.contains("Recorder: not running"),
                "unloaded status should include plain readiness"
            )
            try expect(
                unloaded.text.contains("Detail: service not found"),
                "unloaded status should include launchctl detail"
            )

            let serviceManaged = AgentStatusMessage(
                service: "gui/501/dev.jc.macalarm.agent",
                plistPath: "/Users/test/Library/LaunchAgents/dev.jc.macalarm.agent.plist",
                isLoaded: true,
                state: "running",
                processID: 456,
                detail: "unused",
                serviceManagementStatusText: ServiceManagementAgentStatus.enabled.displayText
            )
            try expect(
                serviceManaged.text.contains("Registration: MacAlarm background item enabled"),
                "service-managed status should include native registration state"
            )
            try expect(
                serviceManaged.text.contains(
                    "Bundled helper: MacAlarm.app/Contents/Library/LoginItems/MacAlarm Recorder.app"),
                "service-managed status should point at the app-bundled login item"
            )
            try expect(
                serviceManaged.text.contains("Fallback plist: MacAlarm.app/Contents/Library/LaunchAgents"),
                "service-managed status should point at the fallback app-bundled plist"
            )

            let requiresApproval = AgentStatusMessage(
                service: "gui/501/dev.jc.macalarm.agent",
                plistPath: "/Users/test/Library/LaunchAgents/dev.jc.macalarm.agent.plist",
                isLoaded: false,
                state: nil,
                processID: nil,
                detail: "service not found",
                serviceManagementStatusText: ServiceManagementAgentStatus.requiresApproval.displayText
            )
            try expect(
                requiresApproval.text.contains("Recorder: needs Background Items approval"),
                "approval status should be obvious before technical details"
            )
            try expect(
                requiresApproval.text.contains("Next: Enable MacAlarm in System Settings"),
                "approval status should include recovery guidance"
            )

            let registeredWaiting = AgentStatusMessage(
                service: "gui/501/dev.jc.macalarm.agent",
                plistPath: "/Users/test/Library/LaunchAgents/dev.jc.macalarm.agent.plist",
                isLoaded: false,
                state: nil,
                processID: nil,
                detail: "service not found",
                serviceManagementStatusText: ServiceManagementAgentStatus.enabled.displayText
            )
            try expect(
                registeredWaiting.text.contains("Recorder > Start or Restart Recorder"),
                "registered waiting status should point at the renamed menu item"
            )
        }

        await runner.run("recorder approval result preserves System Settings recovery path") {
            try expect(
                MacAlarmRecorderInstallResult.nativeRequiresApproval.requiresBackgroundItemsApproval,
                "native approval result should remain actionable"
            )
            try expect(
                !MacAlarmRecorderInstallResult.nativeRegistered.requiresBackgroundItemsApproval,
                "native registered result should not ask for approval"
            )
            try expect(
                !MacAlarmRecorderInstallResult.legacyLaunchAgent.requiresBackgroundItemsApproval,
                "legacy fallback result should not ask for Background Items approval"
            )
            try expect(
                MacAlarmSystemSettings.backgroundItemsURLs.contains {
                    $0.absoluteString.contains("LoginItems-Settings")
                },
                "background settings opener should target Login Items settings before falling back"
            )
        }

        await runner.run("recorder install copy keeps primary setup app-native") {
            try expect(
                RecorderInstallCopy.confirmationTitle == "Install MacAlarm Recorder?",
                "recorder install title should stay user-facing"
            )
            try expect(
                RecorderInstallCopy.confirmationButtonTitle == "Install & Start",
                "recorder install button should describe the app action"
            )
            try expect(
                RecorderInstallCopy.confirmationMessage.contains("visible macOS background item named MacAlarm"),
                "setup copy should name the native Background Items behavior"
            )
            try expect(
                RecorderInstallCopy.confirmationMessage.contains("No admin password or Keychain access is required."),
                "setup copy should explain the important permission boundary"
            )

            let technicalFragments = [
                "~/Library",
                "Application Support",
                "LaunchAgent",
                "SMAppService",
                "macalarmctl",
                "plist",
            ]
            for fragment in technicalFragments {
                try expect(
                    !RecorderInstallCopy.confirmationMessage.contains(fragment),
                    "primary setup prompt should not expose technical fragment: \(fragment)"
                )
            }
        }

        await runner.run("recorder install location protects packaged app registration") {
            try expect(
                MacAlarmApplicationLocation(
                    bundleURL: URL(fileURLWithPath: "/Applications/MacAlarm.app")
                ).recorderInstallIssue == nil,
                "system Applications install should be allowed"
            )
            try expect(
                MacAlarmApplicationLocation(
                    bundleURL: URL(fileURLWithPath: "/Users/test/Applications/MacAlarm.app")
                ).recorderInstallIssue == nil,
                "user Applications install should be allowed"
            )
            try expect(
                MacAlarmApplicationLocation(
                    bundleURL: URL(fileURLWithPath: "/Users/test/project/.build/debug/MacAlarm.app")
                ).recorderInstallIssue == nil,
                "development build should remain installable for local testing"
            )
            try expect(
                MacAlarmApplicationLocation(
                    bundleURL: URL(fileURLWithPath: "/Volumes/MacAlarm/MacAlarm.app")
                ).recorderInstallIssue == .diskImage(path: "/Volumes/MacAlarm/MacAlarm.app"),
                "app running from mounted DMG should be blocked"
            )
            try expect(
                MacAlarmApplicationLocation(
                    bundleURL: URL(fileURLWithPath: "/Users/test/Downloads/MacAlarm.app")
                ).recorderInstallIssue == .outsideApplications(path: "/Users/test/Downloads/MacAlarm.app"),
                "packaged app outside Applications should be blocked"
            )
        }

        await runner.run("menu item factory wires targets and shift command shortcuts") {
            try await MainActor.run {
                let delegate = MacAlarmApplicationDelegate()
                let factory = MacAlarmMenuItemFactory(target: delegate)
                let item = factory.shiftCommand(
                    title: "Copy Visible Events as CSV",
                    action: #selector(MacAlarmApplicationDelegate.copyVisibleCSV(_:)),
                    keyEquivalent: "E"
                )

                try expect(item.target === delegate, "menu item factory should preserve target")
                try expect(
                    item.action == #selector(MacAlarmApplicationDelegate.copyVisibleCSV(_:)), "action should match")
                try expect(item.keyEquivalent == "e", "shift command helper should normalize key equivalent")
                try expect(
                    item.keyEquivalentModifierMask == [.command, .shift],
                    "shift command helper should apply command-shift modifiers"
                )
            }
        }

        await runner.run("app notification service builds diagnostic alarm") {
            let alarm = MacAlarmNotificationService.testAlarm(message: "hello")
            try expect(alarm.ruleID == "manual-notification-test", "diagnostic alarm should use manual rule")
            try expect(alarm.message == "hello", "diagnostic alarm should preserve message")
            try expect(alarm.event.source == "manual", "diagnostic alarm should use manual source")
            try expect(alarm.event.name == "notification.test", "diagnostic alarm should use notification test event")
            try expect(
                alarm.event.metadata["command"] == "MacAlarm.app notification diagnostics",
                "diagnostic alarm should identify app origin"
            )
        }

        await runner.run("notification diagnostics header state maps status levels") {
            let waiting = NotificationDiagnosticsHeaderState(snapshot: nil, isLoading: false)
            try expect(waiting.subtitle == "Waiting for notification status", "missing snapshot should wait")
            try expect(waiting.level == .unknown, "missing snapshot should use unknown level")

            let loading = NotificationDiagnosticsHeaderState(snapshot: nil, isLoading: true)
            try expect(loading.subtitle == "Checking notification path", "loading state should explain refresh")
            try expect(loading.level == .unknown, "loading state should use neutral level")

            let authorized = NotificationDiagnosticsHeaderState(
                snapshot: NotificationAuthorizationSnapshot(
                    authorizationStatus: "authorized",
                    alertSetting: "enabled",
                    soundSetting: "enabled",
                    badgeSetting: "enabled"
                ),
                isLoading: false
            )
            try expect(authorized.subtitle == "authorized", "authorized status should be shown verbatim")
            try expect(authorized.level == .ready, "authorized status should be ready")

            let denied = NotificationDiagnosticsHeaderState(
                snapshot: NotificationAuthorizationSnapshot(
                    authorizationStatus: "denied",
                    alertSetting: "disabled",
                    soundSetting: "disabled",
                    badgeSetting: "disabled"
                ),
                isLoading: false
            )
            try expect(denied.level == .denied, "denied status should be elevated")

            let fallback = NotificationDiagnosticsHeaderState(
                snapshot: NotificationAuthorizationSnapshot(
                    authorizationStatus: "unavailable-unbundled-executable",
                    alertSetting: "unavailable",
                    soundSetting: "unavailable",
                    badgeSetting: "unavailable"
                ),
                isLoading: false
            )
            try expect(fallback.level == .fallback, "unbundled executable should show fallback warning")
        }

        await runner.run("app installer helper copy replaces helpers with executable mode") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let sourceDirectory = directory.appendingPathComponent("source", isDirectory: true)
            let homeDirectory = directory.appendingPathComponent("home", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)

            let sourceAgent = sourceDirectory.appendingPathComponent("macalarm-agent")
            let sourceControl = sourceDirectory.appendingPathComponent("macalarmctl")
            let sourceIcon = sourceDirectory.appendingPathComponent("MacAlarm.icns")
            try Data("agent-v1".utf8).write(to: sourceAgent)
            try Data("control-v1".utf8).write(to: sourceControl)
            try Data("icon-v1".utf8).write(to: sourceIcon)

            let paths = MacAlarmInstallationPaths(
                label: "dev.jc.macalarm.tests.\(UUID().uuidString)",
                homeDirectory: homeDirectory,
                userID: 501
            )
            let legacyAgent = paths.binDirectory.appendingPathComponent("macalarm-agent")
            try FileManager.default.createDirectory(at: paths.binDirectory, withIntermediateDirectories: true)
            try Data("legacy-agent".utf8).write(to: legacyAgent)

            try MacAlarmAgentInstaller.copyBundledHelpers(
                agent: sourceAgent,
                control: sourceControl,
                paths: paths,
                icon: sourceIcon
            )
            let installedAgent = try String(contentsOf: paths.agentExecutableURL, encoding: .utf8)
            let installedControl = try String(contentsOf: paths.controlExecutableURL, encoding: .utf8)
            let infoPlistURL = paths.agentBundleURL
                .appendingPathComponent("Contents")
                .appendingPathComponent("Info.plist")
            let installedIconURL = paths.agentBundleURL
                .appendingPathComponent("Contents")
                .appendingPathComponent("Resources")
                .appendingPathComponent("MacAlarm.icns")
            let infoPlist = try String(contentsOf: infoPlistURL, encoding: .utf8)
            let installedIcon = try String(contentsOf: installedIconURL, encoding: .utf8)

            try expect(installedAgent == "agent-v1", "agent helper should be copied")
            try expect(installedControl == "control-v1", "control helper should be copied")
            try expect(infoPlist.contains("<string>MacAlarm</string>"), "agent helper should have app display name")
            try expect(
                infoPlist.contains("<string>MacAlarm</string>"),
                "agent helper should name its bundled executable"
            )
            try expect(infoPlist.contains("<key>LSBackgroundOnly</key>"), "agent helper should be background-only")
            try expect(installedIcon == "icon-v1", "agent helper should receive the app icon")
            try expect(paths.agentExecutableURL.fileMode == 0o755, "agent helper should be executable")
            try expect(paths.controlExecutableURL.fileMode == 0o755, "control helper should be executable")
            try expect(
                !FileManager.default.fileExists(atPath: legacyAgent.path),
                "legacy raw agent should be removed from bin"
            )

            try Data("agent-v2".utf8).write(to: sourceAgent)
            try MacAlarmAgentInstaller.copyBundledHelpers(agent: sourceAgent, control: sourceControl, paths: paths)
            let replacedAgent = try String(contentsOf: paths.agentExecutableURL, encoding: .utf8)
            try expect(replacedAgent == "agent-v2", "agent helper should be replaced on reinstall")
        }

        await runner.run("finder reveal target prepares directories and resolves files off-main") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let logsDirectory = directory.appendingPathComponent("logs", isDirectory: true)
            let prepared = try await FinderRevealTarget.preparedDirectory(logsDirectory)
            try expect(prepared == .open(logsDirectory), "prepared directory should open the directory")
            var isDirectory: ObjCBool = false
            try expect(
                FileManager.default.fileExists(atPath: logsDirectory.path, isDirectory: &isDirectory)
                    && isDirectory.boolValue,
                "prepared directory should exist"
            )

            let ledgerURL = directory.appendingPathComponent("events.jsonl")
            let missing = await FinderRevealTarget.resolving(
                fileURL: ledgerURL,
                fallbackDirectory: directory
            )
            try expect(missing == .open(directory), "missing file should open the fallback directory")

            try Data("ledger".utf8).write(to: ledgerURL)
            let existing = await FinderRevealTarget.resolving(
                fileURL: ledgerURL,
                fallbackDirectory: directory
            )
            try expect(existing == .select(ledgerURL), "existing file should be selected in Finder")
        }

        await runner.run("background task helper propagates cancellation to detached work") {
            let task = Task {
                await MacAlarmBackgroundTask.value(priority: .utility) {
                    while !Task.isCancelled {
                        Thread.sleep(forTimeInterval: 0.001)
                    }
                    return Task.isCancelled
                }
            }
            await Task.yield()
            task.cancel()

            let observedCancellation = await task.value
            try expect(observedCancellation, "background task helper should cancel the detached worker")
        }

    }
}
