import Foundation
import MacAlarmCore

#if canImport(Darwin)
    import Darwin
#endif

extension MacAlarmTests {
    static func runCoreConfigSecretTests(_ runner: TestRunner) async {
        await runner.run("default config encodes and validates") {
            let config = MacAlarmConfig()
            let data = try config.prettyPrintedJSON()
            let json = String(decoding: data, as: UTF8.self)
            let decoded = try JSONDecoder().decode(MacAlarmConfig.self, from: data)
            let validation = ConfigValidator.validate(decoded)

            try expect(decoded.schemaVersion == 1, "schema version should be 1")
            try expect(!json.contains("keychainService"), "default config should not expose unused Keychain settings")
            try expect(
                !decoded.secrets.allowDevelopmentFallbackKey,
                "default config should require a real HMAC key"
            )
            try expect(validation.isValid, "default config should be valid")
        }

        await runner.run("legacy keychain config field decodes and is dropped") {
            let legacyJSON = """
                {
                  "schemaVersion": 1,
                  "identity": {
                    "deviceID": "legacy-device",
                    "displayName": "Legacy Device"
                  },
                  "storage": {
                    "ledgerPath": "~/Library/Application Support/MacAlarm/events.jsonl",
                    "outboxDirectory": "~/Library/Application Support/MacAlarm/outbox",
                    "runtimeDirectory": "~/Library/Application Support/MacAlarm/runtime"
                  },
                  "secrets": {
                    "keychainService": "dev.jc.macalarm.ledger",
                    "hmacKeyAccount": "ledger-hmac-key",
                    "allowDevelopmentFallbackKey": false
                  },
                  "heartbeat": {
                    "enabled": true,
                    "intervalSeconds": 60,
                    "checkpointEveryHeartbeats": 5
                  },
                  "session": {
                    "enabled": true,
                    "includeApplicationEvents": true
                  },
                  "filesystem": {
                    "watchedPaths": []
                  },
                  "unifiedLog": {
                    "enabled": true,
                    "pollIntervalSeconds": 300,
                    "queries": []
                  },
                  "notifications": {
                    "console": true,
                    "localNotification": true,
                    "appleScriptFallback": true,
                    "sound": true
                  },
                  "remoteCheckpoint": {
                    "enabled": false,
                    "endpointURL": null,
                    "outboxOnly": true
                  },
                  "rules": []
                }
                """
            let decoded = try JSONDecoder().decode(MacAlarmConfig.self, from: Data(legacyJSON.utf8))
            let reencoded = String(decoding: try decoded.prettyPrintedJSON(), as: UTF8.self)

            try expect(decoded.secrets.hmacKeyAccount == "ledger-hmac-key", "legacy secret account should decode")
            try expect(!reencoded.contains("keychainService"), "legacy Keychain field should be dropped on write")
        }

        await runner.run("config validation warns on development fallback key") {
            let config = MacAlarmConfig(secrets: SecretConfig(allowDevelopmentFallbackKey: true))
            let validation = ConfigValidator.validate(config)

            try expect(validation.isValid, "development fallback warning should not block local testing")
            try expect(
                validation.issues.contains {
                    $0.message.contains("allowDevelopmentFallbackKey") && $0.severity == .warning
                },
                "validation should warn when development fallback is enabled"
            )
        }

        await runner.run("agent factory requires key unless development fallback is explicit") {
            let strictConfig = MacAlarmConfig(
                identity: AgentIdentity(deviceID: "unit-device", displayName: "Unit Device"),
                secrets: SecretConfig(allowDevelopmentFallbackKey: false)
            )
            let emptyStore = MemorySecretStore()

            do {
                _ = try AgentFactory.hmacKey(for: strictConfig, secretStore: emptyStore)
                throw TestFailure(description: "strict config should require a stored key")
            } catch MacAlarmError.missingHMACKey {
                // Expected.
            }

            let fallbackConfig = MacAlarmConfig(
                identity: AgentIdentity(deviceID: "unit-device", displayName: "Unit Device"),
                secrets: SecretConfig(allowDevelopmentFallbackKey: true)
            )
            let fallbackKey = try AgentFactory.hmacKey(for: fallbackConfig, secretStore: emptyStore)
            try expect(
                fallbackKey == SecretMaterial.developmentHMACKey(identity: fallbackConfig.identity),
                "explicit development fallback should still be available for tests"
            )
        }

        await runner.run("agent factory initializes missing hmac key once") {
            let config = MacAlarmConfig(secrets: SecretConfig(allowDevelopmentFallbackKey: false))
            let store = MemorySecretStore()

            let first = try AgentFactory.ensureHMACKey(for: config, secretStore: store)
            let second = try AgentFactory.ensureHMACKey(for: config, secretStore: store)
            let resolved = try AgentFactory.hmacKey(for: config, secretStore: store)

            try expect(first.count == 32, "initialized HMAC key should be 32 bytes")
            try expect(second == first, "second initialization should preserve existing key")
            try expect(resolved == first, "runtime key resolution should use stored key")
        }

        await runner.run("secret material random key validates byte count") {
            do {
                _ = try SecretMaterial.randomKey(byteCount: 0)
                throw TestFailure(description: "zero-length random key should be rejected")
            } catch MacAlarmError.invalidConfiguration {
                // Expected.
            }
        }

        await runner.run("secret material random key propagates provider failure") {
            do {
                _ = try SecretMaterial.randomKey(byteCount: 32) { _ in
                    throw MacAlarmError.randomGenerationFailed(status: -1)
                }
                throw TestFailure(description: "random provider failure should be propagated")
            } catch MacAlarmError.randomGenerationFailed(let status) {
                try expect(status == -1, "random failure status should be preserved")
            }
        }

        await runner.run("secret material random key rejects short provider output") {
            do {
                _ = try SecretMaterial.randomKey(byteCount: 32) { _ in
                    Data(repeating: 1, count: 31)
                }
                throw TestFailure(description: "short random provider output should be rejected")
            } catch MacAlarmError.invalidConfiguration(let message) {
                try expect(message.contains("expected 32"), "short random output error should name expected count")
            }
        }

        await runner.run("file secret store round-trips hmac key with private permissions") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let store = FileSecretStore(directory: directory)
            let key = Data("file-secret-test-key".utf8)

            try store.writeSecret(key, account: "ledger-hmac-key")
            let resolved = try require(
                try store.readSecret(account: "ledger-hmac-key"),
                "file secret should be readable after write"
            )

            try expect(resolved == key, "file secret should round-trip raw key material")
            try expect(directory.fileMode == 0o700, "secret directory should be mode 0700")
            try expect(
                directory.appendingPathComponent("ledger-hmac-key").fileMode == 0o600,
                "secret file should be mode 0600"
            )
        }

        await runner.run("file secret store percent-encodes custom account names into one file") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let store = FileSecretStore(directory: directory)
            try store.writeSecret(Data("custom-key".utf8), account: "audio/detector")

            let fileNames = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            let resolved = try store.readSecret(account: "audio/detector")
            try expect(fileNames == ["audio%2Fdetector"], "custom account should not create nested paths")
            try expect(
                resolved == Data("custom-key".utf8),
                "encoded custom account should read back"
            )
        }

        await runner.run("file secret store rejects path traversal account names") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let store = FileSecretStore(directory: directory)

            for account in [".", ".."] {
                do {
                    try store.writeSecret(Data("bad-key".utf8), account: account)
                    throw TestFailure(description: "account \(account) should not be accepted")
                } catch MacAlarmError.invalidConfiguration {
                    // Expected.
                }
            }

            try expect(
                !FileManager.default.fileExists(atPath: directory.path),
                "rejected accounts should not create a secret directory"
            )
        }

        await runner.run("file secret store rejects symlink secret directory") {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: root) }

            let target = root.appendingPathComponent("target", isDirectory: true)
            let link = root.appendingPathComponent("secrets", isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

            let store = FileSecretStore(directory: link)
            do {
                try store.writeSecret(Data("bad-key".utf8), account: "ledger-hmac-key")
                throw TestFailure(description: "symlink secret directory should be rejected")
            } catch MacAlarmError.invalidConfiguration(let message) {
                try expect(message.contains("not a directory"), "symlink directory should fail closed")
            }

            let targetContents = try FileManager.default.contentsOfDirectory(atPath: target.path)
            try expect(targetContents.isEmpty, "symlink target should not receive secret material")
        }

        await runner.run("file secret store rejects non-regular secret path") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent("ledger-hmac-key", isDirectory: true),
                withIntermediateDirectories: true
            )

            let store = FileSecretStore(directory: directory)
            do {
                _ = try store.readSecret(account: "ledger-hmac-key")
                throw TestFailure(description: "directory secret path should be rejected on read")
            } catch MacAlarmError.invalidConfiguration(let message) {
                try expect(message.contains("not a regular file"), "directory secret path should fail closed")
            }
        }

        await runner.run("file secret store rejects insecure secret file permissions on read") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let store = FileSecretStore(directory: directory)
            try store.writeSecret(Data("key".utf8), account: "ledger-hmac-key")

            let secretURL = directory.appendingPathComponent("ledger-hmac-key")
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: secretURL.path)

            do {
                _ = try store.readSecret(account: "ledger-hmac-key")
                throw TestFailure(description: "world-readable secret file should be rejected")
            } catch MacAlarmError.invalidConfiguration(let message) {
                try expect(message.contains("0600"), "insecure file mode should name required mode")
            }

            try store.writeSecret(Data("repaired-key".utf8), account: "ledger-hmac-key")
            try expect(secretURL.fileMode == 0o600, "write should repair regular secret file permissions")
        }

        await runner.run("config validation rejects unsafe hmac key account") {
            var config = MacAlarmConfig()
            config.secrets.hmacKeyAccount = ".."
            let validation = ConfigValidator.validate(config)

            try expect(!validation.isValid, "unsafe hmac account should make config invalid")
            try expect(
                validation.issues.contains {
                    $0.message.contains("hmacKeyAccount") && $0.severity == .critical
                },
                "validation should report the unsafe hmac account as critical"
            )
        }

        await runner.run("installed secret initializer uses ledger-adjacent file secret") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            var config = MacAlarmConfig(secrets: SecretConfig(allowDevelopmentFallbackKey: false))
            config.storage.ledgerPath = directory.appendingPathComponent("events.jsonl").path

            let initialized = try await LaunchAgentManager.ensureInstalledSecretIfMissing(config: config)
            let resolved = try require(
                try FileSecretStore.installedStore(for: config).readSecret(account: config.secrets.hmacKeyAccount),
                "installed secret initializer should write configured account"
            )

            try expect(initialized == resolved, "installed secret initializer should return stored key")
            try expect(
                FileSecretStore.installedSecretDirectory(for: config).fileMode == 0o700,
                "installed secret directory should be private"
            )
        }

    }
}

private final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private var values: [String: Data]
    private let lock = NSLock()

    init(values: [String: Data] = [:]) {
        self.values = values
    }

    func readSecret(account: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[account]
    }

    func writeSecret(_ secret: Data, account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values[account] = secret
    }

    func deleteSecret(account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: account)
    }
}
