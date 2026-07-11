import Foundation

extension MacAlarmTests {
    static func runCoreTests(_ runner: TestRunner) async {
        await runCoreLedgerTests(runner)
        await runCoreRuleTests(runner)
        await runCoreConfigSecretTests(runner)
        await runCoreOperationsTests(runner)
        await runCoreLaunchAgentTests(runner)
    }
}
