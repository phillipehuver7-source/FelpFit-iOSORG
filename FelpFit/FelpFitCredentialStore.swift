import Foundation
import Security

struct FelpFitSavedCredential {
    let username: String
    let password: String
}

final class FelpFitCredentialStore {
    static let shared = FelpFitCredentialStore()

    private let server = "felpfit.pages.dev"
    private init() {}

    func load() -> FelpFitSavedCredential? {
        var query = baseQuery()
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let dictionary = result as? [String: Any],
              let username = dictionary[kSecAttrAccount as String] as? String,
              let data = dictionary[kSecValueData as String] as? Data,
              let password = String(data: data, encoding: .utf8),
              !username.isEmpty,
              !password.isEmpty else { return nil }

        return FelpFitSavedCredential(username: username, password: password)
    }

    @discardableResult
    func save(username: String, password: String) -> Bool {
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanUsername.isEmpty, !password.isEmpty else { return false }

        var query = baseQuery()
        query[kSecAttrAccount as String] = cleanUsername
        let values: [String: Any] = [
            kSecValueData as String: Data(password.utf8),
            kSecAttrLabel as String: "FelpFit",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        values.forEach { query[$0.key] = $0.value }
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: server,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
            kSecAttrAuthenticationType as String: kSecAttrAuthenticationTypeDefault
        ]
    }
}
