import Foundation
import Security

/// Small secrets kept by name: the manage tokens that let this iPhone look up and cancel its
/// appointments, and the ones bookings not yet confirmed were sent with. Each token is the only
/// copy (the server keeps just its hash), so a store must either keep it or say it couldn't.
protocol SecretStore: AnyObject {
    /// The secret saved under `account`, or `nil` if there's none.
    /// - Throws: when the store can't be read right now (e.g. the phone hasn't been unlocked
    ///   since it restarted). That's not the same as "there's none".
    func secret(for account: String) throws -> String?
    func setSecret(_ secret: String, for account: String) throws
    /// Removing one that isn't there is fine.
    func removeSecret(for account: String) throws
}

/// The Keychain, as generic passwords under one service name. Items are readable after the first
/// unlock (so the app can check appointments when it opens) and move to a new iPhone with an
/// encrypted backup, like the appointments themselves.
final class KeychainSecretStore: SecretStore {
    struct Failure: Error, Equatable {
        let status: OSStatus
    }

    let service: String

    init(service: String) {
        self.service = service
    }

    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func secret(for account: String) throws -> String? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw Failure(status: status)
        }
    }

    func setSecret(_ secret: String, for account: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(secret.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        var status = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = query(account).merging(attributes) { _, new in new }
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    func removeSecret(for account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
}

/// Secrets in memory only: for UI tests (every launch starts empty, and nothing is left in the
/// simulator's Keychain) and unit tests, which can also make it fail on purpose.
final class InMemorySecretStore: SecretStore {
    struct Failure: Error {}

    private(set) var secrets: [String: String] = [:]
    /// Makes `setSecret` throw, like a Keychain that won't take the item.
    var failsWrites = false
    /// Makes `secret(for:)` throw, like a locked Keychain.
    var failsReads = false

    init(secrets: [String: String] = [:]) {
        self.secrets = secrets
    }

    func secret(for account: String) throws -> String? {
        if failsReads { throw Failure() }
        return secrets[account]
    }

    func setSecret(_ secret: String, for account: String) throws {
        if failsWrites { throw Failure() }
        secrets[account] = secret
    }

    func removeSecret(for account: String) throws {
        secrets[account] = nil
    }
}
