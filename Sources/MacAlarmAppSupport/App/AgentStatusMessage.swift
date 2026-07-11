import MacAlarmCore

struct AgentStatusMessage: Equatable, Sendable {
    var service: String
    var plistPath: String
    var isLoaded: Bool
    var state: String?
    var processID: Int32?
    var detail: String
    var serviceManagementStatusText: String?

    init(
        service: String,
        plistPath: String,
        isLoaded: Bool,
        state: String?,
        processID: Int32?,
        detail: String,
        serviceManagementStatusText: String? = nil
    ) {
        self.service = service
        self.plistPath = plistPath
        self.isLoaded = isLoaded
        self.state = state
        self.processID = processID
        self.detail = detail
        self.serviceManagementStatusText = serviceManagementStatusText
    }

    init(status: LaunchAgentServiceStatus, serviceManagementStatus: ServiceManagementAgentStatus? = nil) {
        self.init(
            service: status.service,
            plistPath: status.plistPath,
            isLoaded: status.isLoaded,
            state: status.state,
            processID: status.processID,
            detail: status.result.summary,
            serviceManagementStatusText: serviceManagementStatus?.displayText
        )
    }

    var text: String {
        var lines = [
            "Recorder: \(readinessTitle)",
            "Next: \(nextStep)",
            "",
            "Service: \(service)",
            "Loaded: \(isLoaded ? "yes" : "no")",
        ]
        if let serviceManagementStatusText {
            lines.append("Registration: \(serviceManagementStatusText)")
            lines.append("Bundled helper: MacAlarm.app/Contents/Library/LoginItems/MacAlarm Recorder.app")
            lines.append("Fallback plist: MacAlarm.app/Contents/Library/LaunchAgents/dev.jc.macalarm.agent.plist")
            lines.append("Legacy user plist: \(plistPath)")
        } else {
            lines.append("Plist: \(plistPath)")
        }
        if let state {
            lines.append("State: \(state)")
        }
        if let processID {
            lines.append("PID: \(processID)")
        }
        if !isLoaded {
            lines.append("Detail: \(detail)")
        }
        return lines.joined(separator: "\n")
    }

    private var readinessTitle: String {
        if serviceManagementStatusText == ServiceManagementAgentStatus.requiresApproval.displayText {
            return "needs Background Items approval"
        }

        if isLoaded {
            if state == "running" || processID != nil {
                return "running"
            }
            return "loaded"
        }

        if serviceManagementStatusText == ServiceManagementAgentStatus.enabled.displayText {
            return "registered, waiting to run"
        }

        return "not running"
    }

    private var nextStep: String {
        if serviceManagementStatusText == ServiceManagementAgentStatus.requiresApproval.displayText {
            return "Enable MacAlarm in System Settings > Login Items & Extensions."
        }

        if isLoaded {
            if state == "running" || processID != nil {
                return "No action needed."
            }
            return "Wait a moment, then check status again or choose Recorder > Start or Restart Recorder."
        }

        if serviceManagementStatusText == ServiceManagementAgentStatus.enabled.displayText {
            return "Wait a moment, then check status again or choose Recorder > Start or Restart Recorder."
        }

        return "Choose Recorder > Install Recorder at Login... to start recording."
    }
}
