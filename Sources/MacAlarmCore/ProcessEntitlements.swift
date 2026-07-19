import Foundation

#if canImport(Security)
    import Security
#endif

/// Reads the current process's own code-signing entitlements.
///
/// Used to attribute capability gaps: e.g. Telegram delivery under the sandbox
/// requires `com.apple.security.network.client`, and if a build ships without
/// it we want a loud, attributed failure rather than a silent network error
/// (P1). Reading uses the public `SecCode` signing-information API so no private
/// SPI is involved.
public enum ProcessEntitlements {
    /// Test seam. When non-nil, `hasNetworkClient` returns this instead of
    /// reading the real signature, so both branches can be exercised
    /// deterministically. Reset to `nil` to restore real detection.
    nonisolated(unsafe) public static var overrideNetworkClient: Bool?

    public static let networkClientKey = "com.apple.security.network.client"

    /// Whether this process is entitled to make outbound network connections.
    public static var hasNetworkClient: Bool {
        if let overrideNetworkClient {
            return overrideNetworkClient
        }
        return bool(networkClientKey) ?? false
    }

    /// Reads a boolean entitlement value from the running binary's signature.
    /// Returns nil when the entitlement is absent or the signature cannot be
    /// inspected (e.g. an unsigned build).
    public static func bool(_ key: String) -> Bool? {
        #if canImport(Security)
            guard let entitlements = signedEntitlements() else {
                return nil
            }
            return entitlements[key] as? Bool
        #else
            return nil
        #endif
    }

    #if canImport(Security)
        private static func signedEntitlements() -> [String: Any]? {
            var code: SecCode?
            guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else {
                return nil
            }

            var staticCode: SecStaticCode?
            guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode else {
                return nil
            }

            var information: CFDictionary?
            let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
            guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
                let dictionary = information as? [String: Any]
            else {
                return nil
            }

            return dictionary[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        }
    #endif
}
