import Foundation

extension MacAlarmTests {
    static func runTimelineTests(_ runner: TestRunner) async {
        await runAppSupportTests(runner)
        await runTimelineStateTests(runner)
        await runTimelineLayoutTests(runner)
        await runTimelineStoreTests(runner)
    }
}
