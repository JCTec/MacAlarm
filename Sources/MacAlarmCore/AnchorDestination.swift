import Foundation

/// Abstraction over `FileManager.url(forUbiquityContainerIdentifier:)` so tests
/// can inject a fake iCloud container (present or absent) without a real iCloud
/// account. The system implementation blocks, so callers resolve off the main
/// thread.
public protocol UbiquityContainerResolving: Sendable {
    func containerURL(forIdentifier identifier: String?) -> URL?
}

public struct SystemUbiquityContainerResolver: UbiquityContainerResolving {
    public init() {}

    public func containerURL(forIdentifier identifier: String?) -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: identifier)
    }
}

/// Resolves the directory a `HashAnchorConfig` targets.
///
/// For `.directory` the configured path is used verbatim. For `.iCloudDrive`:
/// unsandboxed builds resolve the existing CloudDocs folder
/// (`~/Library/Mobile Documents/com~apple~CloudDocs/MacAlarm`); sandboxed builds
/// resolve the app's ubiquity container
/// (`url(forUbiquityContainerIdentifier:)/Documents/MacAlarm`) and throw
/// `MacAlarmError.iCloudUnavailable` when iCloud is signed out or the container
/// is nil — the permanent attributed-failure state, never a fallback write
/// somewhere else.
public struct AnchorDestinationResolver: Sendable {
    public static let iCloudContainerIdentifier = "iCloud.com.jc-tec.macalarm"

    public let config: HashAnchorConfig
    public let ubiquity: any UbiquityContainerResolving

    public init(config: HashAnchorConfig, ubiquity: any UbiquityContainerResolving = SystemUbiquityContainerResolver())
    {
        self.config = config
        self.ubiquity = ubiquity
    }

    /// Resolves the anchor directory. Blocks on the iCloud ubiquity lookup when
    /// sandboxed, so callers must invoke it off the main thread.
    public func resolveDirectory() throws -> URL {
        switch config.destination {
        case .directory:
            return PathResolver.fileURL(config.directory)
        case .iCloudDrive:
            guard SandboxEnvironment.isSandboxed else {
                return PathResolver.fileURL(HashAnchorConfig.defaultDirectory)
            }
            guard let container = ubiquity.containerURL(forIdentifier: Self.iCloudContainerIdentifier) else {
                throw MacAlarmError.iCloudUnavailable(Self.iCloudContainerIdentifier)
            }
            return
                container
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("MacAlarm", isDirectory: true)
        }
    }

    /// Human-readable description of where anchors are targeted, for doctor
    /// output. Never throws — reports the unresolved iCloud state instead.
    public func describeDestination() -> String {
        switch config.destination {
        case .directory:
            return "directory: \(PathResolver.expandedPath(config.directory))"
        case .iCloudDrive:
            if let url = try? resolveDirectory() {
                return "iCloudDrive: \(url.path)"
            }
            return
                "iCloudDrive: \(MacAlarmError.iCloudUnavailable(Self.iCloudContainerIdentifier).errorDescription ?? "unavailable")"
        }
    }
}

/// A `LedgerHashAnchorSink` that resolves its destination on every write via an
/// `AnchorDestinationResolver`, so an iCloud container that becomes unavailable
/// at runtime surfaces as a thrown `MacAlarmError.iCloudUnavailable` (which the
/// pipeline records once as `anchor.write.failed`). Resolution runs off the main
/// thread because the iCloud lookup blocks.
public actor ResolvingLedgerHashAnchorSink: LedgerHashAnchorSink {
    private let resolver: AnchorDestinationResolver

    public init(resolver: AnchorDestinationResolver) {
        self.resolver = resolver
    }

    public func write(_ anchor: LedgerHashAnchor) async throws {
        let resolver = resolver
        let directory = try await Task.detached(priority: .utility) {
            try resolver.resolveDirectory()
        }.value
        try await FileLedgerHashAnchorSink(directory: directory).write(anchor)
    }
}
