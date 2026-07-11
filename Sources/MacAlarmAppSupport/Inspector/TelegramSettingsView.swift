import MacAlarmCore
import SwiftUI

struct TelegramSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = TelegramSettingsStore()

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                title: "Telegram",
                subtitle: store.config.telegram.enabled ? "Optional alarm delivery enabled" : "Optional alarm delivery disabled",
                symbolName: "paperplane.fill",
                tintColor: store.config.telegram.enabled ? .blue : .secondary
            ) {
                HStack(spacing: AppSpacing.sm) {
                    ToolbarIconButton(
                        symbolName: "arrow.clockwise",
                        helpText: "Reload Telegram settings",
                        isEnabled: !store.isLoading
                    ) {
                        store.load()
                    }
                    ToolbarIconButton(symbolName: "xmark", helpText: "Close Telegram settings") {
                        dismiss()
                    }
                }
            }

            AppSeparator()

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    setupSection
                    filtersSection
                    commandSection
                    pendingSection
                    approvedSection

                    if let status = store.statusMessage {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    if let error = store.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
                .padding(18)
            }

            AppSeparator()

            HStack {
                Button("Send Test") {
                    store.sendTest()
                }
                .disabled(store.isLoading || !store.config.telegram.enabled || store.config.telegram.approvedChatIDs.isEmpty)

                Spacer()

                Button("Save") {
                    store.save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(store.isLoading)
            }
            .padding(14)
        }
        .frame(width: 640, height: 680)
        .background(MacAlarmBackground())
        .task {
            store.load()
        }
    }

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Toggle("Enable Telegram", isOn: $store.config.telegram.enabled)
            Toggle("Receive commands by polling", isOn: $store.config.telegram.pollingEnabled)
            Toggle("Allow commands from approved chats", isOn: $store.config.telegram.commandsEnabled)

            tokenRow

            Text("Create a user-owned bot with BotFather. MacAlarm stores the token in a private local secret file, not in config.json.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sectionPanel(title: "Setup")
    }

    private var tokenRow: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if store.tokenStored, !store.isEditingToken {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bot token stored")
                            .font(.caption.weight(.semibold))
                        Text(store.config.telegram.botTokenAccount)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button("Replace") {
                        store.replaceToken()
                    }
                    Button("Delete", role: .destructive) {
                        store.deleteToken()
                    }
                }
            } else {
                SecureField("Bot token", text: $store.tokenInput)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Text(store.tokenStored ? "Enter a new token to replace the stored one." : "No bot token stored yet.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if store.tokenStored {
                        Button("Cancel") {
                            store.cancelTokenEdit()
                        }
                    }
                }
            }
        }
    }

    private var filtersSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Picker("Minimum severity", selection: $store.config.telegram.minimumSeverity) {
                ForEach(AlarmSeverity.allCases, id: \.self) { severity in
                    Text(severity.rawValue.capitalized).tag(severity)
                }
            }
            .pickerStyle(.segmented)

            TextField(
                "Included rule IDs, comma separated",
                text: bindingList($store.config.telegram.includedRuleIDs)
            )
            .textFieldStyle(.roundedBorder)

            TextField(
                "Included event sources, comma separated",
                text: bindingList($store.config.telegram.includedEventSources)
            )
            .textFieldStyle(.roundedBorder)

            Text("Leave rule IDs or sources empty to report every matching alarm at the selected severity.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sectionPanel(title: "Reported Alarms")
    }

    private var commandSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Stepper(
                "Poll every \(Int(store.config.telegram.pollingIntervalSeconds))s",
                value: $store.config.telegram.pollingIntervalSeconds,
                in: 5...120,
                step: 5
            )
            Stepper(
                "Read up to \(store.config.telegram.updateLimit) updates",
                value: $store.config.telegram.updateLimit,
                in: 1...100
            )
            Text("/help, /status, /latest [type] [count], /search YYYY-MM-DD YYYY-MM-DD [type]. Free-form chat is rejected.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sectionPanel(title: "Commands")
    }

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if store.pendingChats.isEmpty {
                Text("No pending chats.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.pendingChats) { chat in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chat.displayName ?? chat.username ?? String(chat.chatID))
                                .font(.caption.weight(.semibold))
                            Text("Chat ID \(chat.chatID)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Deny") { store.deny(chat) }
                        Button("Approve") { store.approve(chat) }
                    }
                }
            }
        }
        .sectionPanel(title: "Pending Chats")
    }

    private var approvedSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if store.config.telegram.approvedChatIDs.isEmpty {
                Text("No approved chats yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.config.telegram.approvedChatIDs, id: \.self) { chatID in
                    HStack {
                        Text("Chat ID \(chatID)")
                            .font(.caption)
                        Spacer()
                        Button("Remove") {
                            store.removeApprovedChat(chatID)
                        }
                    }
                }
            }
        }
        .sectionPanel(title: "Approved Chats")
    }

    private func bindingList(_ values: Binding<[String]>) -> Binding<String> {
        Binding(
            get: { values.wrappedValue.joined(separator: ", ") },
            set: { newValue in
                values.wrappedValue = newValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }
}

private struct SectionPanelModifier: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: AppRadius.card))
    }
}

private extension View {
    func sectionPanel(title: String) -> some View {
        modifier(SectionPanelModifier(title: title))
    }
}
