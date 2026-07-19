import Foundation
import MacAlarmCore

private struct FakeUbiquityResolver: UbiquityContainerResolving {
    let url: URL?
    func containerURL(forIdentifier identifier: String?) -> URL? { url }
}

extension MacAlarmTests {
    static func runAnchorDestinationTests(_ runner: TestRunner) async {
        await runner.run("directory destination resolves the configured path verbatim") {
            let config = HashAnchorConfig(directory: "/tmp/macalarm-anchors", destination: .directory)
            let resolver = AnchorDestinationResolver(config: config, ubiquity: FakeUbiquityResolver(url: nil))
            let directory = try resolver.resolveDirectory()
            try expect(directory.path == "/tmp/macalarm-anchors", "directory destination should use config.directory")
        }

        await runner.run("iCloudDrive resolves the CloudDocs path when unsandboxed") {
            let sandboxPrevious = SandboxEnvironment.overrideIsSandboxed
            defer { SandboxEnvironment.overrideIsSandboxed = sandboxPrevious }
            SandboxEnvironment.overrideIsSandboxed = false

            let config = HashAnchorConfig(destination: .iCloudDrive)
            let resolver = AnchorDestinationResolver(config: config, ubiquity: FakeUbiquityResolver(url: nil))
            let directory = try resolver.resolveDirectory()
            try expect(
                directory.path == PathResolver.expandedPath(HashAnchorConfig.defaultDirectory),
                "unsandboxed iCloudDrive should resolve the CloudDocs folder, got \(directory.path)")
        }

        await runner.run("iCloudDrive resolves the ubiquity container when sandboxed") {
            let sandboxPrevious = SandboxEnvironment.overrideIsSandboxed
            defer { SandboxEnvironment.overrideIsSandboxed = sandboxPrevious }
            SandboxEnvironment.overrideIsSandboxed = true

            let container = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            let config = HashAnchorConfig(destination: .iCloudDrive)
            let resolver = AnchorDestinationResolver(config: config, ubiquity: FakeUbiquityResolver(url: container))
            let directory = try resolver.resolveDirectory()
            try expect(
                directory.path == container.appendingPathComponent("Documents/MacAlarm").path,
                "sandboxed iCloudDrive should resolve <container>/Documents/MacAlarm, got \(directory.path)")
        }

        await runner.run("iCloudDrive throws iCloudUnavailable when sandboxed and signed out") {
            let sandboxPrevious = SandboxEnvironment.overrideIsSandboxed
            defer { SandboxEnvironment.overrideIsSandboxed = sandboxPrevious }
            SandboxEnvironment.overrideIsSandboxed = true

            let config = HashAnchorConfig(destination: .iCloudDrive)
            let resolver = AnchorDestinationResolver(config: config, ubiquity: FakeUbiquityResolver(url: nil))
            do {
                _ = try resolver.resolveDirectory()
                throw TestFailure(description: "expected iCloudUnavailable when the container is nil")
            } catch MacAlarmError.iCloudUnavailable(let container) {
                try expect(
                    container == AnchorDestinationResolver.iCloudContainerIdentifier,
                    "error should name the ubiquity container")
            }
        }

        await runner.run("absent destination decodes as directory (legacy compatibility)") {
            let legacyJSON = """
                { "enabled": true, "directory": "/tmp/legacy-anchors", "anchorEveryHeartbeats": 5 }
                """
            let decoded = try JSONDecoder().decode(HashAnchorConfig.self, from: Data(legacyJSON.utf8))
            try expect(
                decoded.destination == .directory, "legacy config without destination should decode as .directory")

            let resolver = AnchorDestinationResolver(config: decoded, ubiquity: FakeUbiquityResolver(url: nil))
            let directory = try resolver.resolveDirectory()
            try expect(
                directory.path == "/tmp/legacy-anchors",
                "legacy config should keep writing to its configured directory")
        }

        await runner.run("freshly created config defaults to iCloudDrive") {
            try expect(HashAnchorConfig().destination == .iCloudDrive, "new config default should be iCloudDrive")
        }

        await runner.run("resolving sink writes to a directory destination") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let config = HashAnchorConfig(directory: directory.path, destination: .directory)
            let sink = ResolvingLedgerHashAnchorSink(resolver: AnchorDestinationResolver(config: config))
            let anchor = LedgerHashAnchor(
                deviceID: "test-device",
                ledgerPath: "/tmp/events.jsonl",
                recordCount: 3,
                lastHash: String(repeating: "a", count: 64),
                isLedgerValid: true,
                reason: "unit-test"
            )
            try await sink.write(anchor)
            let latest = try require(
                FileLedgerHashAnchorSink.readLatest(directory: directory),
                "resolving sink should write anchor-latest.json")
            try expect(latest.lastHash == anchor.lastHash, "written anchor should round-trip")
        }
    }
}
