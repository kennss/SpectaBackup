//
//  @file        KeychainStorage.swift
//  @description macOS Keychain wrapper for encrypted-job repo passwords. The password is kept ONLY in
//               the Keychain (a generic-password item keyed by job UUID) — never in config.json — so
//               backups can unlock their repo unattended without persisting the secret in plaintext.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-30
//  @lastUpdated 2026-06-30
//

import Foundation
import Security

enum KeychainStorage {
    private static let service = "ai.calidalab.spectabackup.repo-password"

    /// Store (or replace) the repo password for a job.
    @discardableResult
    static func setPassword(_ password: String, for jobID: UUID) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: jobID.uuidString,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(password.utf8)
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func password(for jobID: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: jobID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func removePassword(for jobID: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: jobID.uuidString,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
