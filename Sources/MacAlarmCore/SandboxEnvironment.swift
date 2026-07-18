import Foundation

/// Single source of truth for whether the current process runs under the macOS
/// App Sandbox, and for the uniform phrasing used whenever a capability is
/// unavailable there.
///
/// Every sandbox check and every sandbox-attributed message in MacAlarm flows
/// through this type. That keeps the wording greppable and identical across
/// diagnostic logs, ledger events, config-validation issues, and UI copy, which
/// is the mechanism behind P1 (no unknown behavior): a feature that cannot run
/// under the sandbox fails loudly with one recognizable string, never silently.
public enum SandboxEnvironment {
    /// Environment variable macOS sets on every App-Sandboxed process. Its value
    /// is the container id; its mere presence is the sandbox signal.
    public static let containerEnvironmentKey = "APP_SANDBOX_CONTAINER_ID"

    /// Uniform prefix for every "unavailable under the sandbox" message. Grep for
    /// this exact string to find every attributed-failure surface.
    public static let unavailablePrefix = "unavailable under App Sandbox"

    /// Test override hook. When non-nil, `isSandboxed` returns this value instead
    /// of probing the process environment, so tests can exercise both code paths
    /// deterministically. Production code never sets it; reset to `nil` to
    /// restore real detection.
    ///
    /// Marked `nonisolated(unsafe)` because it is a process-wide test seam
    /// mutated only from single-threaded test setup/teardown.
    nonisolated(unsafe) public static var overrideIsSandboxed: Bool?

    /// True when the process is confined by the macOS App Sandbox.
    public static var isSandboxed: Bool {
        if let overrideIsSandboxed {
            return overrideIsSandboxed
        }
        return ProcessInfo.processInfo.environment[containerEnvironmentKey] != nil
    }

    /// Uniform phrasing for a capability the App Sandbox forbids. Always renders
    /// as `"unavailable under App Sandbox: <detail>"` so logs, ledger events, and
    /// UI share one recognizable string.
    public static func unavailableReason(_ detail: String) -> String {
        "\(unavailablePrefix): \(detail)"
    }

    /// Runs `body` with `overrideIsSandboxed` forced to `value`, restoring the
    /// previous override afterward. Intended for tests; the closure is
    /// synchronous so the override never leaks across suspension points.
    @discardableResult
    public static func withOverride<Result>(_ value: Bool, _ body: () throws -> Result) rethrows -> Result {
        let previous = overrideIsSandboxed
        overrideIsSandboxed = value
        defer { overrideIsSandboxed = previous }
        return try body()
    }
}
