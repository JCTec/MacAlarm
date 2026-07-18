import AppKit
import Foundation
import MacAlarmCore
import OSLog

@main
struct MacAlarmProbe {
    static func main() async throws {
        let arguments = ProbeArguments(CommandLine.arguments.dropFirst())

        if arguments.help {
            print(Self.helpText)
            return
        }

        if arguments.selfTest {
            try await runSelfTest(duration: arguments.duration)
            return
        }

        if arguments.session {
            await runSessionProbe(duration: arguments.duration, postSelfTest: arguments.postSessionSelfTest)
            return
        }

        if let watchPath = arguments.watchPath {
            try await runFileProbe(path: watchPath, duration: arguments.duration)
            return
        }

        if arguments.logs {
            try runLogProbe()
            return
        }

        print(Self.helpText)
    }

    private static func runSelfTest(duration: TimeInterval) async throws {
        printSection("environment")
        print("swift=\(swiftVersionFallback())")
        print("macOS=\(ProcessInfo.processInfo.operatingSystemVersionString)")

        printSection("ledger")
        let stateDirectory = URL(fileURLWithPath: ".state", isDirectory: true)
        let ledgerURL = stateDirectory.appendingPathComponent("events.jsonl")
        try? FileManager.default.removeItem(at: ledgerURL)

        let ledger = try HashChainLedger(
            fileURL: ledgerURL,
            hmacKey: Data("development-only-self-test-key".utf8)
        )
        let ledgerEvent = AlarmEvent(source: "probe", name: "ledger.selfTest", severity: .notice)
        let record = try await ledger.append(ledgerEvent)
        let verification = try await ledger.verify()
        printJSON(record)
        printJSON(verification)

        printSection("rules")
        let engine = RuleEngine(
            rules: [
                AlarmRule(
                    id: "probe-critical",
                    match: EventMatch(source: "probe", name: "rule.selfTest"),
                    severity: .critical,
                    message: "Probe rule fired",
                    cooldownSeconds: 30
                ),
                AlarmRule(
                    id: "probe-threshold",
                    match: EventMatch(source: "probe", name: "threshold.selfTest"),
                    severity: .warning,
                    message: "Probe threshold fired",
                    threshold: Threshold(count: 2, intervalSeconds: 10)
                ),
            ]
        )
        let edgeAlarms = await engine.evaluate(AlarmEvent(source: "probe", name: "rule.selfTest"))
        let thresholdFirst = await engine.evaluate(AlarmEvent(source: "probe", name: "threshold.selfTest"))
        let thresholdSecond = await engine.evaluate(AlarmEvent(source: "probe", name: "threshold.selfTest"))
        printJSON(edgeAlarms)
        printJSON(thresholdFirst + thresholdSecond)

        printSection("session")
        await runSessionProbe(duration: min(duration, 2), postSelfTest: true)

        printSection("filesystem")
        let canaryURL = stateDirectory.appendingPathComponent("canary.txt")
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: canaryURL.path, contents: Data("initial\n".utf8))
        try await runFileProbe(path: canaryURL.path, duration: min(duration, 2), mutatePath: true)

        printSection("unified-log")
        try runLogProbe()
    }

    @MainActor
    private static func runSessionProbe(duration: TimeInterval, postSelfTest: Bool) async {
        var events = [AlarmEvent]()
        let source = SessionEventSource { event in
            events.append(event)
            printJSON(event)
        }

        printJSON(
            AlarmEvent(
                source: "session",
                name: "probe.started",
                metadata: source.currentFrontmostApplicationMetadata()
            )
        )

        source.start()
        if postSelfTest {
            source.postSelfTest()
        }
        runCurrentRunLoop(for: duration)
        source.stop()

        printJSON(
            AlarmEvent(
                source: "session",
                name: "probe.finished",
                metadata: ["eventsObserved": String(events.count)]
            )
        )
    }

    @MainActor
    private static func runFileProbe(path: String, duration: TimeInterval, mutatePath: Bool = false) async throws {
        let source = FileEventSource(path: path)
        try source.start { fileEvent in
            printJSON(fileEvent.alarmEvent)
        }

        if mutatePath {
            try? await Task.sleep(for: .milliseconds(250))
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("mutated\n".utf8))
        }

        try? await Task.sleep(for: .milliseconds(Int(duration * 1_000)))
        source.stop()
    }

    private static func runLogProbe() throws {
        let subsystem = "com.jctec.macalarm"
        let logger = Logger(subsystem: subsystem, category: "probe")
        logger.error("macalarm OSLogStore self-test")

        Thread.sleep(forTimeInterval: 1)

        let reader = UnifiedLogReader()
        let query = UnifiedLogQuery(
            scope: .currentProcess,
            since: Date().addingTimeInterval(-120),
            predicateFormat: "subsystem == '\(subsystem)'",
            limit: 10
        )
        let events = try reader.readEvents(query: query)
        for event in events {
            printJSON(event)
        }
        printJSON(
            AlarmEvent(source: "unifiedLog", name: "probe.finished", metadata: ["eventsObserved": String(events.count)])
        )
    }

    @MainActor
    private static func runCurrentRunLoop(for duration: TimeInterval) {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
    }

    private static func printSection(_ name: String) {
        print("\n== \(name) ==")
    }

    private static func printJSON<T: Encodable>(_ value: T) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(value)
            print(String(decoding: data, as: UTF8.self))
        } catch {
            print("{\"encodingError\":\"\(error)\"}")
        }
    }

    private static func swiftVersionFallback() -> String {
        #if swift(>=6.3)
            "6.3+"
        #elseif swift(>=6.2)
            "6.2"
        #elseif swift(>=6.1)
            "6.1"
        #elseif swift(>=6.0)
            "6.0"
        #else
            "pre-6.0"
        #endif
    }

    private static let helpText = """
        macalarm-probe

        Safe native macOS hook probe.

        Usage:
          swift run macalarm-probe --self-test
          swift run macalarm-probe --session --post-session-self-test --duration 5
          swift run macalarm-probe --watch /path/to/canary --duration 10
          swift run macalarm-probe --logs

        Flags:
          --self-test                Run safe ledger/rule/session/file/log checks.
          --session                  Observe NSWorkspace and distributed session notifications.
          --post-session-self-test   Post a local distributed notification for session probe validation.
          --watch PATH               Watch a single file or directory with DispatchSource.
          --logs                     Emit and read a current-process OSLog event.
          --duration SECONDS         Probe duration. Default: 3.
          --help                     Show help.
        """
}

private struct ProbeArguments {
    var help = false
    var selfTest = false
    var session = false
    var postSessionSelfTest = false
    var logs = false
    var watchPath: String?
    var duration: TimeInterval = 3

    init(_ arguments: ArraySlice<String>) {
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--help", "-h":
                help = true
            case "--self-test":
                selfTest = true
            case "--session":
                session = true
            case "--post-session-self-test":
                postSessionSelfTest = true
            case "--logs":
                logs = true
            case "--watch":
                watchPath = iterator.next()
            case "--duration":
                if let value = iterator.next(), let parsed = TimeInterval(value) {
                    duration = parsed
                }
            default:
                continue
            }
        }
    }
}
