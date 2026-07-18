import Foundation
import MacAlarmCore

extension MacAlarmTests {
    static func runSandboxEnvironmentTests(_ runner: TestRunner) async {
        await runner.run("sandbox override forces both states") {
            let original = SandboxEnvironment.overrideIsSandboxed
            defer { SandboxEnvironment.overrideIsSandboxed = original }

            SandboxEnvironment.overrideIsSandboxed = true
            try expect(SandboxEnvironment.isSandboxed, "override true should report sandboxed")

            SandboxEnvironment.overrideIsSandboxed = false
            try expect(!SandboxEnvironment.isSandboxed, "override false should report not sandboxed")
        }

        await runner.run("sandbox override restores after withOverride") {
            let original = SandboxEnvironment.overrideIsSandboxed
            defer { SandboxEnvironment.overrideIsSandboxed = original }

            SandboxEnvironment.overrideIsSandboxed = false
            let observed = SandboxEnvironment.withOverride(true) { SandboxEnvironment.isSandboxed }
            try expect(observed, "withOverride should apply the value inside the closure")
            try expect(!SandboxEnvironment.isSandboxed, "withOverride should restore the prior override")
        }

        await runner.run("unavailable reason uses uniform phrasing") {
            let reason = SandboxEnvironment.unavailableReason("system-scope unified log query")
            try expect(
                reason == "unavailable under App Sandbox: system-scope unified log query",
                "reason should render the uniform prefix and detail")
            try expect(
                reason.hasPrefix(SandboxEnvironment.unavailablePrefix),
                "reason should start with the greppable prefix constant")
        }

        await runner.run("no test override leaks environment detection") {
            // Absent any override, detection must reflect the process environment
            // rather than a stale test value.
            let original = SandboxEnvironment.overrideIsSandboxed
            SandboxEnvironment.overrideIsSandboxed = nil
            defer { SandboxEnvironment.overrideIsSandboxed = original }

            let expected = ProcessInfo.processInfo.environment[SandboxEnvironment.containerEnvironmentKey] != nil
            try expect(
                SandboxEnvironment.isSandboxed == expected,
                "detection without override should match the process environment")
        }
    }
}
