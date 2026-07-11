import Foundation
import MacAlarmCore

extension MacAlarmTests {
    static func runCoreRuleTests(_ runner: TestRunner) async {
        await runner.run("event matching covers source, name, severity, and metadata") {
            let event = AlarmEvent(
                source: "session",
                name: "screen.unlocked",
                severity: .critical,
                metadata: ["bundleIdentifier": "com.apple.loginwindow"]
            )

            let match = EventMatch(
                source: "session",
                name: "screen.unlocked",
                minimumSeverity: .warning,
                metadataEquals: ["bundleIdentifier": "com.apple.loginwindow"]
            )

            try expect(match.matches(event), "match should accept event")
        }

        await runner.run("rule cooldown suppresses repeated alarms") {
            let engine = RuleEngine(
                rules: [
                    AlarmRule(
                        id: "unlock",
                        match: EventMatch(source: "session", name: "screen.unlocked"),
                        severity: .critical,
                        message: "Screen unlocked",
                        cooldownSeconds: 60
                    )
                ]
            )
            let event = AlarmEvent(source: "session", name: "screen.unlocked")

            let first = await engine.evaluate(event, now: Date(timeIntervalSince1970: 100))
            let second = await engine.evaluate(event, now: Date(timeIntervalSince1970: 110))
            let third = await engine.evaluate(event, now: Date(timeIntervalSince1970: 161))

            try expect(first.count == 1, "first event should alarm")
            try expect(second.isEmpty, "second event should be in cooldown")
            try expect(third.count == 1, "third event should alarm after cooldown")
        }

        await runner.run("threshold requires multiple events inside window") {
            let engine = RuleEngine(
                rules: [
                    AlarmRule(
                        id: "sudo-burst",
                        match: EventMatch(source: "unifiedLog", name: "auth.failure"),
                        severity: .critical,
                        message: "Repeated auth failures",
                        threshold: Threshold(count: 3, intervalSeconds: 60)
                    )
                ]
            )
            let event = AlarmEvent(source: "unifiedLog", name: "auth.failure")

            let first = await engine.evaluate(event, now: Date(timeIntervalSince1970: 1))
            let second = await engine.evaluate(event, now: Date(timeIntervalSince1970: 2))
            let third = await engine.evaluate(event, now: Date(timeIntervalSince1970: 3))

            try expect(first.isEmpty, "first event should not alarm")
            try expect(second.isEmpty, "second event should not alarm")
            try expect(third.count == 1, "third event should satisfy threshold")
        }

    }
}
