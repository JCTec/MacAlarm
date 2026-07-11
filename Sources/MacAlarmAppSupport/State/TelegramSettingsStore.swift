import Foundation
import MacAlarmCore

@MainActor
final class TelegramSettingsStore: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage: String?
    @Published var tokenInput = ""
    @Published var tokenStored = false
    @Published var isEditingToken = false
    @Published var pendingChats = [PendingTelegramChat]()
    @Published var config = MacAlarmConfig()

    private let launchAgentLabel: String
    private var loadTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    init(launchAgentLabel: String = "dev.jc.macalarm.agent") {
        self.launchAgentLabel = launchAgentLabel
    }

    deinit {
        loadTask?.cancel()
        saveTask?.cancel()
    }

    var configURL: URL {
        MacAlarmInstallationPaths(label: launchAgentLabel).configURL
    }

    func load() {
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        let configURL = configURL
        loadTask = Task { [weak self] in
            do {
                let loaded = try await MacAlarmBackgroundTask.throwing(priority: .utility) {
                    if FileManager.default.fileExists(atPath: configURL.path) {
                        return try MacAlarmConfig.load(from: configURL)
                    }
                    return MacAlarmConfig()
                }
                let secretStore = FileSecretStore.installedStore(for: loaded)
                let stored = try await MacAlarmBackgroundTask.throwing(priority: .utility) {
                    try secretStore.readSecret(account: loaded.telegram.botTokenAccount) != nil
                }
                let pending = try await PendingTelegramChatStore.installedStore(config: loaded).load()

                guard !Task.isCancelled else { return }
                self?.config = loaded
                self?.tokenStored = stored
                self?.isEditingToken = !stored
                self?.pendingChats = pending
                self?.isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                self?.errorMessage = error.localizedDescription
                self?.isLoading = false
            }
        }
    }

    func save() {
        saveTask?.cancel()
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        let config = config
        let configURL = configURL
        let token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !config.telegram.enabled || tokenStored || !token.isEmpty else {
            errorMessage = "Add a Telegram bot token before enabling Telegram."
            isLoading = false
            return
        }
        saveTask = Task { [weak self] in
            do {
                try await MacAlarmBackgroundTask.throwing(priority: .utility) {
                    try FileManager.default.createDirectory(
                        at: configURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try config.write(to: configURL)
                    if !token.isEmpty {
                        try FileSecretStore.installedStore(for: config).writeSecret(
                            Data(token.utf8),
                            account: config.telegram.botTokenAccount
                        )
                    }
                }
                guard !Task.isCancelled else { return }
                self?.tokenInput = ""
                self?.tokenStored = self?.tokenStored == true || !token.isEmpty
                self?.isEditingToken = !(self?.tokenStored ?? false)
                let applyMessage = await self?.applyRecorderChangesIfActive()
                self?.statusMessage = applyMessage ?? "Telegram settings saved."
                self?.isLoading = false
                self?.load()
            } catch {
                guard !Task.isCancelled else { return }
                self?.errorMessage = error.localizedDescription
                self?.isLoading = false
            }
        }
    }

    func replaceToken() {
        tokenInput = ""
        isEditingToken = true
        statusMessage = nil
        errorMessage = nil
    }

    func cancelTokenEdit() {
        tokenInput = ""
        isEditingToken = !tokenStored
    }

    func deleteToken() {
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        let config = config
        saveTask = Task { [weak self] in
            do {
                try await MacAlarmBackgroundTask.throwing(priority: .utility) {
                    try FileSecretStore.installedStore(for: config).deleteSecret(
                        account: config.telegram.botTokenAccount)
                }
                guard !Task.isCancelled else { return }
                self?.tokenInput = ""
                self?.tokenStored = false
                self?.isEditingToken = true
                let applyMessage = await self?.applyRecorderChangesIfActive()
                self?.statusMessage = applyMessage ?? "Telegram token deleted."
                self?.isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                self?.errorMessage = error.localizedDescription
                self?.isLoading = false
            }
        }
    }

    private func applyRecorderChangesIfActive() async -> String {
        let installer = MacAlarmAgentInstaller(launchAgentLabel: launchAgentLabel)
        let serviceStatus = await installer.serviceManagementStatus()
        let launchAgentStatus = await installer.launchAgentStatus()

        let shouldRestart =
            serviceStatus == .enabled
            || serviceStatus == .requiresApproval
            || launchAgentStatus.isLoaded

        guard shouldRestart else {
            return "Telegram settings saved. They will apply when the recorder is installed or started."
        }

        do {
            let result = try await installer.restartLaunchAgent()
            switch result {
            case .nativeRegistered, .legacyLaunchAgent:
                return "Telegram settings saved and recorder restarted."
            case .nativeRequiresApproval:
                return "Telegram settings saved. Enable MacAlarm in Background Items to apply them."
            }
        } catch {
            return "Telegram settings saved, but MacAlarm could not restart the recorder: \(error.localizedDescription)"
        }
    }

    func approve(_ chat: PendingTelegramChat) {
        config.telegram.approvedChatIDs.appendUnique(chat.chatID)
        config.telegram.deniedChatIDs.removeAll { $0 == chat.chatID }
        pendingChats.removeAll { $0.chatID == chat.chatID }
        save()
    }

    func deny(_ chat: PendingTelegramChat) {
        config.telegram.deniedChatIDs.appendUnique(chat.chatID)
        config.telegram.approvedChatIDs.removeAll { $0 == chat.chatID }
        pendingChats.removeAll { $0.chatID == chat.chatID }
        save()
    }

    func removeApprovedChat(_ chatID: Int64) {
        config.telegram.approvedChatIDs.removeAll { $0 == chatID }
        save()
    }

    func sendTest() {
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        let config = config
        Task { [weak self] in
            do {
                guard config.telegram.enabled else {
                    throw MacAlarmError.invalidConfiguration("Telegram is disabled.")
                }
                guard let chatID = config.telegram.approvedChatIDs.first else {
                    throw MacAlarmError.invalidConfiguration("Approve at least one Telegram chat first.")
                }
                guard
                    let tokenData = try FileSecretStore.installedStore(for: config)
                        .readSecret(account: config.telegram.botTokenAccount),
                    let token = String(data: tokenData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                    !token.isEmpty
                else {
                    throw MacAlarmError.invalidConfiguration("Store a Telegram bot token first.")
                }

                try await TelegramClient(token: token).sendMessage(
                    chatID: chatID,
                    text: "MacAlarm Telegram test"
                )
                self?.statusMessage = "Sent Telegram test message."
                self?.isLoading = false
            } catch {
                self?.errorMessage = error.localizedDescription
                self?.isLoading = false
            }
        }
    }
}

private extension Array where Element: Equatable {
    mutating func appendUnique(_ element: Element) {
        if !contains(element) {
            append(element)
        }
    }
}
