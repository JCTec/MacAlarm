import Foundation
import MacAlarmCore

@testable import MacAlarmAppSupport

struct TestFailure: Error, CustomStringConvertible {
    var description: String
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw TestFailure(description: message)
    }
}

func require<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else {
        throw TestFailure(description: message)
    }
    return value
}

func withIsolatedTimelineStore(
    inspectorAutoOpens: Bool = false,
    _ body: @MainActor (TimelineStore) throws -> Void
) async throws {
    let suiteName = "MacAlarmTests.\(UUID().uuidString)"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    let ledgerURL = directory.appendingPathComponent("events.jsonl")
    try await MainActor.run {
        let defaults = try require(UserDefaults(suiteName: suiteName), "suite should be created")
        let preferences = TimelinePreferences(defaults: defaults)
        preferences.saveInspectorAutoOpens(inspectorAutoOpens)
        let store = TimelineStore(ledgerURL: ledgerURL, preferences: preferences)
        try body(store)
    }
}

func timelineRecord(index: Int, event: AlarmEvent) -> TimelineRecord {
    TimelineRecord(
        index: index,
        record: LedgerRecord(
            event: event, previousHash: HashChainLedger.zeroHash, hash: String(repeating: "\(index)", count: 64)),
        category: TimelineCategory.category(for: event)
    )
}

func timelineDisplayRecord(
    index: Int,
    event: AlarmEvent,
    displayState: CategoryDisplayState
) -> TimelineDisplayRecord {
    let record = timelineRecord(index: index, event: event)
    return TimelineDisplayRecord(
        record: record,
        presentation: TimelineDerivedState.presentation(for: record, matches: [], filterStates: [:]),
        displayState: displayState,
        hiddenBySearch: false
    )
}

final class TestRunner {
    private var failures = 0

    func run(_ name: String, body: @Sendable () async throws -> Void) async {
        do {
            try await body()
            print("PASS \(name)")
        } catch {
            failures += 1
            print("FAIL \(name): \(error)")
        }
    }

    func finish() -> Never {
        if failures == 0 {
            print("All Swift tests passed.")
            Foundation.exit(0)
        } else {
            print("\(failures) Swift test(s) failed.")
            Foundation.exit(1)
        }
    }
}

extension URL {
    var fileMode: Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
            let value = attributes[.posixPermissions] as? NSNumber
        else {
            return nil
        }

        return value.intValue
    }
}
