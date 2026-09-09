import Foundation
import RightKitShared
import Security

/// Only the host reads credentials, and only when an action is explicitly run.
/// Finder's shared catalog contains variable IDs, never secret values.
struct ScriptSecretStore {
    private let service = "com.rightkit.custom-actions"

    func read(actionID: UUID, variableID: UUID) throws -> String? {
        var query = identity(actionID: actionID, variableID: variableID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw CustomActionError.message(Strings.Custom.keychainError(Strings.Custom.invalidConfiguration))
        }
        return value
    }

    func write(_ value: String, actionID: UUID, variableID: UUID, label: String) throws {
        var query = identity(actionID: actionID, variableID: variableID)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrLabel as String] = "RightKit · \(label)"
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        // Edited secrets get new variable IDs before the catalog is committed. We
        // never overwrite a credential still referenced by the saved configuration.
        try check(SecItemAdd(query as CFDictionary, nil))
    }

    func delete(actionID: UUID, variableID: UUID) throws {
        let status = SecItemDelete(identity(actionID: actionID, variableID: variableID) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private func identity(actionID: UUID, variableID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(actionID.uuidString).\(variableID.uuidString)"
        ]
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            let reason = SecCopyErrorMessageString(status, nil) as String? ?? String(status)
            throw CustomActionError.message(Strings.Custom.keychainError(reason))
        }
    }
}
