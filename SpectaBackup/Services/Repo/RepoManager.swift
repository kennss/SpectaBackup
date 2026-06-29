//
//  @file        RepoManager.swift
//  @description Creates and unlocks an encrypted dedup repo on a Backend. `create` generates the
//               master keys, wraps them into a password slot and a recovery-key slot, and writes
//               `config` + `keys/*`. `unlock` (password) / `unlockWithRecovery` re-derive the KEK and
//               unwrap the master keys into RepoKeys (→ BlobCipher).
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-30
//  @lastUpdated 2026-06-30
//

import CryptoKit
import Foundation

/// A persisted key slot: wrapped master keys + the KDF inputs needed to re-derive the KEK.
struct StoredKeySlot: Codable, Sendable {
    var kdf: String                 // "argon2id" (password) or "recovery"
    var salt: Data
    var argon2: Argon2KDF.Params
    var wrapped: Data               // KeySlot.wrap output
}

enum RepoManagerError: Error, CustomStringConvertible {
    case alreadyInitialized
    case notInitialized
    case slotMissing(String)
    var description: String {
        switch self {
        case .alreadyInitialized: return "repo already initialized"
        case .notInitialized: return "repo not initialized"
        case let .slotMissing(s): return "key slot missing: \(s)"
        }
    }
}

enum RepoManager {
    static let configKey = "config"
    static func slotKey(_ id: String) -> String { "keys/\(id)" }

    static func isInitialized(_ backend: Backend) async -> Bool {
        ((try? await backend.stat(key: configKey)) ?? nil) != nil
    }

    /// Initialize a new encrypted repo. Returns the unlocked keys and the recovery key (show ONCE).
    static func create(backend: Backend, password: Data,
                       config: RepoConfig = RepoConfig()) async throws -> (config: RepoConfig, keys: RepoKeys, recoveryKey: String) {
        if await isInitialized(backend) { throw RepoManagerError.alreadyInitialized }

        let keys = RepoKeys.generate()

        // Password slot.
        let salt = randomBytes(16)
        let pwKEK = try Argon2KDF.deriveKey(password: password, salt: salt, params: config.argon2)
        let pwSlot = StoredKeySlot(kdf: "argon2id", salt: salt, argon2: config.argon2,
                                   wrapped: try KeySlot.wrap(keys, kek: SymmetricKey(data: pwKEK)))

        // Recovery slot (high-entropy → HKDF KEK, no argon2).
        let (recoveryRaw, recoveryStr) = RecoveryKey.generate()
        let recoverySlot = StoredKeySlot(kdf: "recovery", salt: Data(), argon2: config.argon2,
                                         wrapped: try KeySlot.wrap(keys, kek: RecoveryKey.deriveKEK(raw: recoveryRaw)))

        try await backend.put(key: configKey, data: try JSONEncoder().encode(config))
        try await backend.put(key: slotKey("password"), data: try JSONEncoder().encode(pwSlot))
        try await backend.put(key: slotKey("recovery"), data: try JSONEncoder().encode(recoverySlot))

        return (config, keys, recoveryStr)
    }

    static func unlock(backend: Backend, password: Data) async throws -> (config: RepoConfig, keys: RepoKeys) {
        let config = try await loadConfig(backend)
        let slot = try await loadSlot(backend, "password")
        let kek = try Argon2KDF.deriveKey(password: password, salt: slot.salt, params: slot.argon2)
        let keys = try KeySlot.unwrap(slot.wrapped, kek: SymmetricKey(data: kek))
        return (config, keys)
    }

    static func unlockWithRecovery(backend: Backend, recoveryKey: String) async throws -> (config: RepoConfig, keys: RepoKeys) {
        guard let raw = RecoveryKey.parse(recoveryKey) else { throw RepoCryptoError.malformedKeyMaterial }
        let config = try await loadConfig(backend)
        let slot = try await loadSlot(backend, "recovery")
        let keys = try KeySlot.unwrap(slot.wrapped, kek: RecoveryKey.deriveKEK(raw: raw))
        return (config, keys)
    }

    // MARK: - Helpers

    private static func loadConfig(_ backend: Backend) async throws -> RepoConfig {
        guard let data = try? await backend.get(key: configKey) else { throw RepoManagerError.notInitialized }
        return try JSONDecoder().decode(RepoConfig.self, from: data)
    }

    private static func loadSlot(_ backend: Backend, _ id: String) async throws -> StoredKeySlot {
        guard let data = try? await backend.get(key: slotKey(id)) else { throw RepoManagerError.slotMissing(id) }
        return try JSONDecoder().decode(StoredKeySlot.self, from: data)
    }

    private static func randomBytes(_ count: Int) -> Data {
        var data = Data(count: count)
        data.withUnsafeMutableBytes { _ = SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        return data
    }
}
