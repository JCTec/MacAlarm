import AppKit
import Foundation
import MacAlarmCore

extension MacAlarmApplicationDelegate {
    @objc func installAgent(_ sender: Any?) {
        guard validateRecorderInstallLocation() else {
            return
        }

        guard
            confirm(
                title: RecorderInstallCopy.confirmationTitle,
                message: RecorderInstallCopy.confirmationMessage,
                confirmButtonTitle: RecorderInstallCopy.confirmationButtonTitle
            )
        else {
            return
        }

        let installer = agentInstaller
        Task { @MainActor in
            do {
                let result = try await installer.installAndStartAgent()
                await refreshRecorderHealthAfterControlAction()
                showRecorderInstallResult(result, title: "MacAlarm Recorder Installed")
            } catch {
                MacAlarmLog.installer.error(
                    "Install failed: \(String(describing: error), privacy: .public)")
                showError(title: "Install Failed", error: error)
            }
        }
    }

    @objc func showAgentStatus(_ sender: Any?) {
        let installer = agentInstaller
        Task { @MainActor in
            async let launchStatus = installer.launchAgentStatus()
            async let serviceStatus = installer.serviceManagementStatus()
            let status = await launchStatus
            let serviceManagementStatus = await serviceStatus
            let message = AgentStatusMessage(
                status: status,
                serviceManagementStatus: serviceManagementStatus
            ).text
            showInfo(title: "MacAlarm Recorder Status", message: message)
        }
    }

    @objc func restartAgent(_ sender: Any?) {
        guard validateRecorderInstallLocation() else {
            return
        }

        startOrRestartAgent(failureTitle: "Restart Failed", successTitle: "MacAlarm Recorder Restarted")
    }

    func startAgentFromBanner() {
        guard validateRecorderInstallLocation() else {
            return
        }

        startOrRestartAgent(failureTitle: "Start Failed", successTitle: "MacAlarm Recorder Started")
    }

    private func startOrRestartAgent(failureTitle: String, successTitle: String) {
        let installer = agentInstaller
        Task { @MainActor in
            do {
                let result = try await installer.restartLaunchAgent()
                await refreshRecorderHealthAfterControlAction()
                showRecorderInstallResult(result, title: successTitle)
            } catch {
                showError(title: failureTitle, error: error)
            }
        }
    }

    @objc func stopAgent(_ sender: Any?) {
        let installer = agentInstaller
        runAgentOperation(
            failureTitle: "Stop Failed",
            successTitle: "MacAlarm Recorder Stopped",
            successMessage:
                "The background recorder has been stopped. Use the Start Recorder banner or Recorder > Start or Restart Recorder to start it again."
        ) {
            await installer.stopLaunchAgent()
            await self.refreshRecorderHealthAfterControlAction()
        }
    }

    @objc func uninstallAgent(_ sender: Any?) {
        guard
            confirm(
                title: "Uninstall MacAlarm Recorder?",
                message:
                    "This stops the background recorder and removes its registration. Your ledger, config, logs, and installed helper files are kept.",
                confirmButtonTitle: "Uninstall"
            )
        else {
            return
        }

        let installer = agentInstaller
        runAgentOperation(
            failureTitle: "Uninstall Failed",
            successTitle: "MacAlarm Recorder Uninstalled",
            successMessage: "The background recorder registration was removed. Local MacAlarm data was preserved."
        ) {
            try await installer.uninstallAgent()
            await self.refreshRecorderHealthAfterControlAction()
        }
    }

    @objc func openAgentLogs(_ sender: Any?) {
        let logDirectory = agentInstaller.logDirectory
        Task { @MainActor in
            do {
                let target = try await FinderRevealTarget.preparedDirectory(logDirectory)
                if !target.openInFinder() {
                    showInfo(
                        title: "Could Not Open Logs",
                        message: "Finder did not open the recorder log directory.\n\nPath: \(logDirectory.path)"
                    )
                }
            } catch {
                showError(title: "Open Logs Failed", error: error)
            }
        }
    }

    @objc func revealLedger(_ sender: Any?) {
        let ledgerURL = agentInstaller.installDirectory.appendingPathComponent("events.jsonl")
        let installDirectory = agentInstaller.installDirectory
        Task { @MainActor in
            let target = await FinderRevealTarget.resolving(
                fileURL: ledgerURL,
                fallbackDirectory: installDirectory
            )
            if !target.openInFinder() {
                showInfo(
                    title: "Could Not Reveal Ledger",
                    message: "Finder did not open the ledger location.\n\nPath: \(ledgerURL.path)"
                )
            }
        }
    }

    private func runAgentOperation(
        failureTitle: String,
        successTitle: String,
        successMessage: String,
        operation: @escaping @Sendable () async throws -> Void
    ) {
        Task { @MainActor in
            do {
                try await operation()
                showInfo(title: successTitle, message: successMessage)
            } catch {
                showError(title: failureTitle, error: error)
            }
        }
    }

    private func showRecorderInstallResult(_ result: MacAlarmRecorderInstallResult, title: String) {
        if result.requiresBackgroundItemsApproval {
            let shouldOpenSettings = showInfoWithAction(
                title: "Approve MacAlarm Recorder",
                message:
                    """
                    macOS registered MacAlarm, but Background Items approval is required before the recorder can run.

                    Open System Settings, then enable MacAlarm in Login Items & Extensions.
                    """,
                actionButtonTitle: "Open System Settings"
            )
            if shouldOpenSettings {
                MacAlarmSystemSettings.openBackgroundItems()
            }
            return
        }

        showInfo(title: title, message: recorderInstallSuccessMessage(result))
    }

    private func recorderInstallSuccessMessage(_ result: MacAlarmRecorderInstallResult) -> String {
        switch result {
        case .nativeRegistered:
            "MacAlarm is installed as a visible macOS background item and should keep recording while your user session is active."
        case .nativeRequiresApproval:
            "MacAlarm needs Background Items approval before recording can start."
        case .legacyLaunchAgent:
            "MacAlarm is running with the legacy user LaunchAgent fallback and should keep recording while your user session is active."
        }
    }

    private func validateRecorderInstallLocation(
        location: MacAlarmApplicationLocation = .current()
    ) -> Bool {
        guard let issue = location.recorderInstallIssue else {
            return true
        }

        let shouldOpenApplications = showInfoWithAction(
            title: issue.title,
            message: issue.message,
            actionButtonTitle: "Open Applications"
        )
        if shouldOpenApplications {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
        }
        return false
    }

    private func refreshRecorderHealthAfterControlAction() async {
        await healthStore.refresh()
        scheduleRecorderHealthFollowUpRefreshes()
    }

    private func scheduleRecorderHealthFollowUpRefreshes() {
        for delay in [Duration.seconds(1), .seconds(4), .seconds(9)] {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else {
                    return
                }
                await self?.healthStore.refresh()
            }
        }
    }
}
