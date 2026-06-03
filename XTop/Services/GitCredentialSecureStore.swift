import Foundation
import Security

enum GitCredentialSecretKind: String, Sendable {
    case httpsToken
    case sshPassphrase
}

struct GitCredentialSecretKey: Hashable, Sendable {
    let profileID: UUID
    let kind: GitCredentialSecretKind

    nonisolated var accountKey: String {
        "\(profileID.uuidString):\(kind.rawValue)"
    }
}

protocol GitCredentialSecureStore: Sendable {
    func saveSecret(_ secret: String, for key: GitCredentialSecretKey) async throws
    func readSecret(for key: GitCredentialSecretKey) async throws -> String?
    func deleteSecret(for key: GitCredentialSecretKey) async throws
    func deleteSecrets(for profileID: UUID) async throws
}

enum GitCredentialSecureStoreError: Error {
    case encodingFailed
    case keychainError(OSStatus)
}

actor KeychainGitCredentialSecureStore: GitCredentialSecureStore {
    private let service: String

    nonisolated init(service: String = "com.xtop.git-monitor.credentials") {
        self.service = service
    }

    func saveSecret(_ secret: String, for key: GitCredentialSecretKey) async throws {
        guard let valueData = secret.data(using: .utf8) else {
            throw GitCredentialSecureStoreError.encodingFailed
        }

        let baseQuery = baseQuery(for: key)
        let attributes: [String: Any] = [kSecValueData as String: valueData]

        let status = SecItemCopyMatching(baseQuery as CFDictionary, nil)
        if status == errSecSuccess {
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw GitCredentialSecureStoreError.keychainError(updateStatus)
            }
            return
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = valueData

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw GitCredentialSecureStoreError.keychainError(addStatus)
        }
    }

    func readSecret(for key: GitCredentialSecretKey) async throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw GitCredentialSecureStoreError.keychainError(status)
        }

        guard let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func deleteSecret(for key: GitCredentialSecretKey) async throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GitCredentialSecureStoreError.keychainError(status)
        }
    }

    func deleteSecrets(for profileID: UUID) async throws {
        try await deleteSecret(for: GitCredentialSecretKey(profileID: profileID, kind: .httpsToken))
        try await deleteSecret(for: GitCredentialSecretKey(profileID: profileID, kind: .sshPassphrase))
    }

    private func baseQuery(for key: GitCredentialSecretKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.accountKey
        ]
    }
}

actor InMemoryGitCredentialSecureStore: GitCredentialSecureStore {
    private var values: [String: String] = [:]

    func saveSecret(_ secret: String, for key: GitCredentialSecretKey) async throws {
        values[key.accountKey] = secret
    }

    func readSecret(for key: GitCredentialSecretKey) async throws -> String? {
        values[key.accountKey]
    }

    func deleteSecret(for key: GitCredentialSecretKey) async throws {
        values.removeValue(forKey: key.accountKey)
    }

    func deleteSecrets(for profileID: UUID) async throws {
        let prefix = "\(profileID.uuidString):"
        values = values.filter { !$0.key.hasPrefix(prefix) }
    }
}
