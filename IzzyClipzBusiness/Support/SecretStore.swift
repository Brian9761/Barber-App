import Foundation
import Security

/// Where the owner key is kept between launches.
@MainActor
protocol SecretStore: AnyObject {
    func read() throws -> String?
    func save(_ secret: String) throws
    func delete() throws
}

/// Something went wrong with the keychain.
struct KeychainError: Error, Equatable, LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        "This iPhone's keychain couldn't keep the owner key (error \(status)). Restart the iPhone and try again."
    }
}

/// The owner key in the iOS keychain: this device only (never synced to
/// iCloud or restored onto another phone), readable only while the phone is
/// unlocked.
@MainActor
final class KeychainSecretStore: SecretStore {
    let service: String
    let account: String

    init(service: String = "com.izzyclipz.business", account: String = "owner-key") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let text = String(data: data, encoding: .utf8) else { return nil }
            return text
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    func save(_ secret: String) throws {
        let data = Data(secret.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var query = baseQuery
            query.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        default:
            throw KeychainError(status: updateStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

/// A store that forgets everything when the app quits: UI tests, previews and
/// unit tests, so they never read or leave a real key behind.
@MainActor
final class InMemorySecretStore: SecretStore {
    private var secret: String?

    init(secret: String? = nil) {
        self.secret = secret
    }

    func read() throws -> String? { secret }
    func save(_ secret: String) throws { self.secret = secret }
    func delete() throws { secret = nil }
}
