import Foundation

public struct TelegramUser: Codable, Equatable, Sendable {
    public var id: Int64
    public var isBot: Bool?
    public var firstName: String?
    public var lastName: String?
    public var username: String?

    enum CodingKeys: String, CodingKey {
        case id
        case isBot = "is_bot"
        case firstName = "first_name"
        case lastName = "last_name"
        case username
    }
}

public struct TelegramChat: Codable, Equatable, Sendable {
    public var id: Int64
    public var type: String
    public var title: String?
    public var username: String?
    public var firstName: String?
    public var lastName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case username
        case firstName = "first_name"
        case lastName = "last_name"
    }
}

public struct TelegramMessage: Codable, Equatable, Sendable {
    public var messageID: Int
    public var from: TelegramUser?
    public var chat: TelegramChat
    public var date: Int
    public var text: String?

    enum CodingKeys: String, CodingKey {
        case messageID = "message_id"
        case from
        case chat
        case date
        case text
    }
}

public struct TelegramUpdate: Codable, Equatable, Sendable {
    public var updateID: Int
    public var message: TelegramMessage?

    enum CodingKeys: String, CodingKey {
        case updateID = "update_id"
        case message
    }
}

public struct TelegramAPIResponse<T: Codable & Sendable>: Codable, Sendable {
    public var ok: Bool
    public var result: T?
    public var description: String?
}

public struct PendingTelegramChat: Codable, Equatable, Sendable, Identifiable {
    public var id: Int64 { chatID }
    public var chatID: Int64
    public var firstSeenAt: Date
    public var lastSeenAt: Date
    public var username: String?
    public var displayName: String?
    public var lastMessage: String?

    public init(
        chatID: Int64,
        firstSeenAt: Date = .now,
        lastSeenAt: Date = .now,
        username: String? = nil,
        displayName: String? = nil,
        lastMessage: String? = nil
    ) {
        self.chatID = chatID
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.username = username
        self.displayName = displayName
        self.lastMessage = lastMessage
    }
}

public actor PendingTelegramChatStore {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func installedStore(config: MacAlarmConfig) -> PendingTelegramChatStore {
        let directory = PathResolver.fileURL(config.storage.runtimeDirectory)
            .appendingPathComponent("telegram", isDirectory: true)
        return PendingTelegramChatStore(fileURL: directory.appendingPathComponent("pending-chats.json"))
    }

    public func record(_ chat: PendingTelegramChat) throws {
        var chats = try load()
        if let index = chats.firstIndex(where: { $0.chatID == chat.chatID }) {
            var existing = chats[index]
            existing.lastSeenAt = chat.lastSeenAt
            existing.username = chat.username ?? existing.username
            existing.displayName = chat.displayName ?? existing.displayName
            existing.lastMessage = chat.lastMessage ?? existing.lastMessage
            chats[index] = existing
        } else {
            chats.append(chat)
        }
        try save(chats.sorted { $0.lastSeenAt > $1.lastSeenAt })
    }

    public func load() throws -> [PendingTelegramChat] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([PendingTelegramChat].self, from: Data(contentsOf: fileURL))
    }

    public func remove(chatID: Int64) throws {
        try save(try load().filter { $0.chatID != chatID })
    }

    private func save(_ chats: [PendingTelegramChat]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(chats).write(to: fileURL, options: [.atomic])
        chmod(fileURL.path, S_IRUSR | S_IWUSR)
    }
}

public struct TelegramClient: Sendable {
    private let token: String
    private let session: URLSession
    private let baseURL: URL

    public init(token: String, session: URLSession = .shared, baseURL: URL = URL(string: "https://api.telegram.org")!) {
        self.token = token
        self.session = session
        self.baseURL = baseURL
    }

    public func sendMessage(chatID: Int64, text: String) async throws {
        _ = try await post(
            method: "sendMessage",
            body: [
                "chat_id": String(chatID),
                "text": String(text.prefix(3900)),
                "disable_web_page_preview": "true",
            ],
            responseType: TelegramMessage.self
        )
    }

    public func getUpdates(offset: Int?, limit: Int, timeout: Int) async throws -> [TelegramUpdate] {
        var body = [
            "limit": String(max(1, min(limit, 100))),
            "timeout": String(max(0, timeout)),
            "allowed_updates": "[\"message\"]",
        ]
        if let offset {
            body["offset"] = String(offset)
        }
        let response = try await post(method: "getUpdates", body: body, responseType: [TelegramUpdate].self)
        return response
    }

    private func post<T: Codable & Sendable>(method: String, body: [String: String], responseType: T.Type) async throws
        -> T
    {
        let url = baseURL.appendingPathComponent("bot\(token)").appendingPathComponent(method)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MacAlarmError.invalidConfiguration("Telegram \(method) HTTP \(http.statusCode)")
        }

        let decoded = try CanonicalJSON.decoder.decode(TelegramAPIResponse<T>.self, from: data)
        guard decoded.ok, let result = decoded.result else {
            throw MacAlarmError.invalidConfiguration("Telegram \(method) failed: \(decoded.description ?? "unknown error")")
        }
        return result
    }
}

public struct TelegramAlarmFilter: Sendable {
    public var config: TelegramConfig

    public init(config: TelegramConfig) {
        self.config = config
    }

    public func shouldSend(_ alarm: Alarm) -> Bool {
        guard alarm.severity >= config.minimumSeverity else {
            return false
        }
        if !config.includedRuleIDs.isEmpty, !config.includedRuleIDs.contains(alarm.ruleID) {
            return false
        }
        if !config.includedEventSources.isEmpty, !config.includedEventSources.contains(alarm.event.source) {
            return false
        }
        return true
    }
}

public actor TelegramNotifier: AlarmNotifier {
    public nonisolated let channel = "telegram"
    private let client: TelegramClient
    private let config: TelegramConfig
    private let filter: TelegramAlarmFilter

    public init(client: TelegramClient, config: TelegramConfig) {
        self.client = client
        self.config = config
        self.filter = TelegramAlarmFilter(config: config)
    }

    public func send(_ alarm: Alarm) async throws -> NotificationDelivery {
        guard config.enabled else {
            return NotificationDelivery(channel: channel, succeeded: false, detail: "telegram disabled")
        }
        guard filter.shouldSend(alarm) else {
            return NotificationDelivery(channel: channel, succeeded: true, detail: "telegram filter skipped alarm")
        }
        guard !config.approvedChatIDs.isEmpty else {
            return NotificationDelivery(channel: channel, succeeded: false, detail: "no approved Telegram chats")
        }

        var sent = 0
        var failures = [String]()
        for chatID in config.approvedChatIDs where !config.deniedChatIDs.contains(chatID) {
            do {
                try await client.sendMessage(chatID: chatID, text: Self.message(for: alarm))
                sent += 1
            } catch {
                failures.append("\(chatID): \(error)")
            }
        }

        return NotificationDelivery(
            channel: channel,
            succeeded: failures.isEmpty && sent > 0,
            detail: failures.isEmpty ? "sent to \(sent) Telegram chat(s)" : failures.joined(separator: "; ")
        )
    }

    static func message(for alarm: Alarm) -> String {
        """
        MacAlarm \(alarm.severity.rawValue.uppercased())
        \(alarm.message)

        Event: \(alarm.event.source).\(alarm.event.name)
        Rule: \(alarm.ruleID)
        Time: \(ISO8601DateFormatter().string(from: alarm.raisedAt))
        Host: \(alarm.event.host)
        """
    }
}

public enum TelegramCommandProcessor {
    public static func response(
        text: String,
        records: [LedgerRecord],
        config: MacAlarmConfig,
        now: Date = .now
    ) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let command = parts.first?.lowercased() else {
            return helpText
        }

        switch command {
        case "/help", "/commands", "/start":
            return helpText
        case "/status", "/appinfo":
            return appInfo(config: config, records: records, now: now)
        case "/latest":
            let limit = parts.dropFirst().compactMap(Int.init).first ?? 5
            let query = parts.dropFirst().first(where: { Int($0) == nil })
            return format(records: latest(records: records, query: query, limit: limit))
        case "/search":
            return search(parts: parts, records: records)
        default:
            return "MacAlarm only accepts commands. Send /help to list supported commands."
        }
    }

    public static let helpText = """
        MacAlarm Telegram commands:
        /help - list commands
        /status - app and ledger summary
        /latest [type] [count] - latest events, optionally by source/name
        /search YYYY-MM-DD YYYY-MM-DD [type] - events in a date range

        This bot does not accept free-form chat.
        """

    private static func appInfo(config: MacAlarmConfig, records: [LedgerRecord], now: Date) -> String {
        let last = records.last.map { ISO8601DateFormatter().string(from: $0.event.observedAt) } ?? "none"
        return """
            MacAlarm status
            Device: \(config.identity.displayName)
            Records: \(records.count)
            Last event: \(last)
            Checked: \(ISO8601DateFormatter().string(from: now))
            """
    }

    private static func latest(records: [LedgerRecord], query: String?, limit: Int) -> [LedgerRecord] {
        records
            .filter { matches($0.event, query: query) }
            .suffix(max(1, min(limit, 20)))
            .reversed()
    }

    private static func search(parts: [String], records: [LedgerRecord]) -> String {
        guard parts.count >= 3,
            let start = Self.dayFormatter.date(from: parts[1]),
            let endStart = Self.dayFormatter.date(from: parts[2])
        else {
            return "Usage: /search YYYY-MM-DD YYYY-MM-DD [type]"
        }

        let end = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: endStart) ?? endStart
        let query = parts.count >= 4 ? parts[3] : nil
        return format(
            records: records
                .filter { $0.event.observedAt >= start && $0.event.observedAt < end }
                .filter { matches($0.event, query: query) }
                .suffix(20)
                .reversed()
        )
    }

    private static func matches(_ event: AlarmEvent, query: String?) -> Bool {
        guard let query, !query.isEmpty else {
            return true
        }
        let normalized = query.lowercased()
        return event.source.lowercased().contains(normalized)
            || event.name.lowercased().contains(normalized)
            || "\(event.source).\(event.name)".lowercased().contains(normalized)
    }

    private static func format(records: some Sequence<LedgerRecord>) -> String {
        let lines = records.map { record in
            let event = record.event
            return "\(Self.shortDateFormatter.string(from: event.observedAt)) \(event.severity.rawValue) \(event.source).\(event.name)"
        }
        guard !lines.isEmpty else {
            return "No matching MacAlarm events."
        }
        return lines.joined(separator: "\n")
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

public actor TelegramCommandPoller {
    private let client: TelegramClient
    private let config: MacAlarmConfig
    private let pendingStore: PendingTelegramChatStore
    private var nextOffset: Int?

    public init(client: TelegramClient, config: MacAlarmConfig, pendingStore: PendingTelegramChatStore) {
        self.client = client
        self.config = config
        self.pendingStore = pendingStore
    }

    public func pollOnce() async throws {
        let updates = try await client.getUpdates(
            offset: nextOffset,
            limit: config.telegram.updateLimit,
            timeout: 0
        )
        if let last = updates.last {
            nextOffset = last.updateID + 1
        }

        for update in updates {
            guard let message = update.message, let text = message.text else {
                continue
            }
            try await handle(message: message, text: text)
        }
    }

    private func handle(message: TelegramMessage, text: String) async throws {
        let chatID = message.chat.id
        if config.telegram.deniedChatIDs.contains(chatID) {
            return
        }

        guard config.telegram.approvedChatIDs.contains(chatID) else {
            try await pendingStore.record(
                PendingTelegramChat(
                    chatID: chatID,
                    username: message.from?.username ?? message.chat.username,
                    displayName: displayName(message),
                    lastMessage: text
                )
            )
            try? await client.sendMessage(
                chatID: chatID,
                text:
                    "This MacAlarm bot only accepts commands from approved chats. Your chat was recorded as pending for the Mac owner."
            )
            return
        }

        guard config.telegram.commandsEnabled, text.hasPrefix("/") else {
            try await client.sendMessage(chatID: chatID, text: "MacAlarm only accepts commands. Send /help.")
            return
        }

        let records = try LedgerFileReader.readDataWithSharedLock(fileURL: PathResolver.fileURL(config.storage.ledgerPath))
        let decoded = try decodeRecords(records)
        let response = TelegramCommandProcessor.response(text: text, records: decoded, config: config)
        try await client.sendMessage(chatID: chatID, text: response)
    }

    private func decodeRecords(_ data: Data) throws -> [LedgerRecord] {
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
            return []
        }
        return try text.split(separator: "\n").map { try CanonicalJSON.decoder.decode(LedgerRecord.self, from: Data($0.utf8)) }
    }

    private func displayName(_ message: TelegramMessage) -> String? {
        if let title = message.chat.title {
            return title
        }
        let parts = [message.from?.firstName, message.from?.lastName].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
