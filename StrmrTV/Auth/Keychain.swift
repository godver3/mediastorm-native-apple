import Foundation
import Security

/// Minimal generic-password Keychain wrapper for the session token.
enum Keychain {
    private static let service = (Bundle.main.bundleIdentifier ?? "com.strmr.app.nx") + ".session"

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// A read that tells a missing item apart from one that couldn't be read. The second
    /// (e.g. `errSecInteractionNotAllowed` before data protection is available) says nothing
    /// about whether the item exists, so callers must not treat it as "nothing saved".
    enum Lookup {
        case found(Data)
        case notFound
        case failed(OSStatus)
    }

    static func lookup(_ account: String) -> Lookup {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return .failed(errSecDecode) }
            return .found(data)
        case errSecItemNotFound:
            return .notFound
        default:
            return .failed(status)
        }
    }

    /// The item's data, or nil when it is missing or unreadable (see `lookup` to tell which).
    static func read(_ account: String) -> Data? {
        if case let .found(data) = lookup(account) { return data }
        return nil
    }

    @discardableResult
    static func write(_ data: Data, account: String) -> Bool {
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(query(account) as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var add = query(account)
        add.merge(update) { $1 }
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
