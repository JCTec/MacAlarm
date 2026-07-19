import Foundation
import MacAlarmCore

#if canImport(ServiceManagement)
    import ServiceManagement
#endif

enum ServiceManagementAgentRegistrationResult: Equatable, Sendable {
    case registered
    case requiresApproval
    case unavailable(String)
}

enum ServiceManagementAgentStatus: Equatable, Sendable {
    case enabled
    case requiresApproval
    case notRegistered
    case notFound
    case unavailable(String)

    var displayText: String {
        switch self {
        case .enabled:
            "MacAlarm background item enabled"
        case .requiresApproval:
            "MacAlarm background item requires Background Items approval"
        case .notRegistered:
            "MacAlarm background item not registered"
        case .notFound:
            "MacAlarm background item not found"
        case .unavailable(let reason):
            "MacAlarm background item unavailable: \(reason)"
        }
    }
}

struct MacAlarmServiceManagementAgentRegistrar: Sendable {
    static let bundledPlistName = "com.jc-tec.macalarm.agent.plist"
    static let loginItemBundleName = "MacAlarm Recorder.app"
    static let loginItemBundleIdentifier = "com.jc-tec.macalarm.recorder"

    var plistName: String = Self.bundledPlistName
    var loginItemBundleIdentifier: String = Self.loginItemBundleIdentifier

    func registerIfPackaged() async throws -> ServiceManagementAgentRegistrationResult {
        let plistName = plistName
        let loginItemBundleIdentifier = loginItemBundleIdentifier

        #if canImport(ServiceManagement)
            return try await MacAlarmBackgroundTask.throwing(priority: .utility) {
                if Self.bundledLoginItemExists(identifier: loginItemBundleIdentifier) {
                    MacAlarmLog.installer.debug("Registering via bundled login item")
                    return try Self.register(service: SMAppService.loginItem(identifier: loginItemBundleIdentifier))
                }

                guard Self.bundledPlistExists(plistName: plistName) else {
                    MacAlarmLog.installer.notice(
                        "No bundled login item or LaunchAgent plist (unpackaged build?); SMAppService unavailable")
                    return .unavailable("Bundled ServiceManagement LaunchAgent plist is not present.")
                }

                MacAlarmLog.installer.debug("Registering via app-bundled LaunchAgent plist")
                return try Self.register(service: SMAppService.agent(plistName: plistName))
            }
        #else
            return .unavailable("ServiceManagement is unavailable on this platform.")
        #endif
    }

    func unregisterIfPackaged() async {
        let plistName = plistName
        let loginItemBundleIdentifier = loginItemBundleIdentifier

        #if canImport(ServiceManagement)
            await MacAlarmBackgroundTask.value(priority: .utility) {
                if Self.bundledLoginItemExists(identifier: loginItemBundleIdentifier) {
                    let service = SMAppService.loginItem(identifier: loginItemBundleIdentifier)
                    try? Self.unregisterIgnoringMissing(service)
                }

                guard Self.bundledPlistExists(plistName: plistName) else {
                    return
                }

                let service = SMAppService.agent(plistName: plistName)
                try? Self.unregisterIgnoringMissing(service)
            }
        #endif
    }

    func status() async -> ServiceManagementAgentStatus {
        let plistName = plistName
        let loginItemBundleIdentifier = loginItemBundleIdentifier

        #if canImport(ServiceManagement)
            return await MacAlarmBackgroundTask.value(priority: .utility) {
                if Self.bundledLoginItemExists(identifier: loginItemBundleIdentifier) {
                    return Self.status(for: SMAppService.loginItem(identifier: loginItemBundleIdentifier))
                }

                guard Self.bundledPlistExists(plistName: plistName) else {
                    return .unavailable("Bundled ServiceManagement LaunchAgent plist is not present.")
                }

                return Self.status(for: SMAppService.agent(plistName: plistName))
            }
        #else
            return .unavailable("ServiceManagement is unavailable on this platform.")
        #endif
    }

    private static func bundledPlistExists(plistName: String) -> Bool {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
            .appendingPathComponent(plistName)
        return FileManager.default.fileExists(atPath: url.path)
    }

    private static func bundledLoginItemExists(identifier: String) -> Bool {
        let infoPlistURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Library")
            .appendingPathComponent("LoginItems")
            .appendingPathComponent(loginItemBundleName)
            .appendingPathComponent("Contents")
            .appendingPathComponent("Info.plist")
        guard
            let info = NSDictionary(contentsOf: infoPlistURL),
            let bundleIdentifier = info["CFBundleIdentifier"] as? String
        else {
            return false
        }
        return bundleIdentifier == identifier
    }

    #if canImport(ServiceManagement)
        private static func register(service: SMAppService) throws -> ServiceManagementAgentRegistrationResult {
            if service.status == .requiresApproval {
                return .requiresApproval
            }

            if service.status == .enabled {
                try unregisterIgnoringMissing(service)
            }

            do {
                try service.register()
            } catch {
                let nsError = error as NSError
                MacAlarmLog.installer.notice(
                    """
                    SMAppService register threw \(nsError.domain, privacy: .public) \
                    code \(nsError.code, privacy: .public): \
                    \(nsError.localizedDescription, privacy: .public)
                    """)
                if isAlreadyRegistered(nsError) {
                    MacAlarmLog.installer.debug("Already registered; unregistering and retrying")
                    try unregisterIgnoringMissing(service)
                    try service.register()
                } else if isUserApprovalRequired(nsError) {
                    return .requiresApproval
                } else if isFallbackEligible(nsError) {
                    MacAlarmLog.installer.notice("Register error is fallback-eligible; legacy install will be used")
                    return .unavailable(nsError.localizedDescription)
                } else {
                    MacAlarmLog.installer.error(
                        "Register error is NOT fallback-eligible; install will fail with this error")
                    throw error
                }
            }

            switch service.status {
            case .enabled:
                return .registered
            case .requiresApproval:
                return .requiresApproval
            case .notFound:
                return .unavailable("ServiceManagement could not find the bundled recorder.")
            case .notRegistered:
                return .unavailable("ServiceManagement did not register the bundled recorder.")
            @unknown default:
                return .registered
            }
        }

        private static func status(for service: SMAppService) -> ServiceManagementAgentStatus {
            switch service.status {
            case .enabled:
                return .enabled
            case .requiresApproval:
                return .requiresApproval
            case .notRegistered:
                return .notRegistered
            case .notFound:
                return .notFound
            @unknown default:
                return .unavailable("Unknown ServiceManagement status.")
            }
        }

        private static func unregisterIgnoringMissing(_ service: SMAppService) throws {
            do {
                try service.unregister()
            } catch {
                let nsError = error as NSError
                guard isMissingJob(nsError) else {
                    throw error
                }
            }
        }

        private static func isAlreadyRegistered(_ error: NSError) -> Bool {
            isServiceManagementError(error) && error.code == Int(kSMErrorAlreadyRegistered)
        }

        private static func isMissingJob(_ error: NSError) -> Bool {
            isServiceManagementError(error) && error.code == Int(kSMErrorJobNotFound)
        }

        private static func isUserApprovalRequired(_ error: NSError) -> Bool {
            isServiceManagementError(error) && error.code == Int(kSMErrorLaunchDeniedByUser)
        }

        private static func isFallbackEligible(_ error: NSError) -> Bool {
            guard isServiceManagementError(error) else {
                return false
            }

            return [
                Int(kSMErrorInvalidSignature),
                Int(kSMErrorToolNotValid),
                Int(kSMErrorJobNotFound),
                Int(kSMErrorJobPlistNotFound),
                Int(kSMErrorInvalidPlist),
            ].contains(error.code)
        }

        private static func isServiceManagementError(_ error: NSError) -> Bool {
            error.domain.localizedCaseInsensitiveContains("ServiceManagement")
                || error.domain.localizedCaseInsensitiveContains("SMAppService")
        }
    #endif
}
