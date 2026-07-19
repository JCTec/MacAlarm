import Foundation

extension MacAlarmTests {
    static func runCoreTests(_ runner: TestRunner) async {
        await runSandboxEnvironmentTests(runner)
        await runSharedContainerTests(runner)
        await runAnchorDestinationTests(runner)
        await runCoreLedgerTests(runner)
        await runCoreRuleTests(runner)
        await runCoreConfigSecretTests(runner)
        await runCoreOperationsTests(runner)
        await runCoreLaunchAgentTests(runner)
    }
}
