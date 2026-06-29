//
//  @file        RepoKeys.swift
//  @description The encrypted repo's long-lived master keys (generated once, stored only wrapped),
//               plus key-slot wrapping: the master keys are sealed under a KEK derived from a
//               password or recovery key, so multiple secrets can unlock the same repo.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//

import CryptoKit
import Foundation

enum RepoCryptoError: Error, CustomStringConvertible {
    case malformedKeyMaterial
    case integrityCheckFailed
    case sealFailed

    var description: String {
        switch self {
        case .malformedKeyMaterial: return "malformed key material"
        case .integrityCheckFailed: return "integrity check failed (tampered or wrong key)"
        case .sealFailed: return "failed to seal data"
        }
    }
}

/// Repo master keys: `masterEncKey` derives per-blob data keys; `chunkIDKey` keys the content hash.
struct RepoKeys: Sendable {
    let masterEncKey: SymmetricKey   // 256-bit
    let chunkIDKey: SymmetricKey     // 256-bit

    static func generate() -> RepoKeys {
        RepoKeys(masterEncKey: SymmetricKey(size: .bits256),
                 chunkIDKey: SymmetricKey(size: .bits256))
    }

    /// 64-byte serialization (masterEncKey ‖ chunkIDKey) for wrapping.
    func serialized() -> Data {
        var data = Data()
        masterEncKey.withUnsafeBytes { data.append(contentsOf: $0) }
        chunkIDKey.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }

    static func deserialize(_ data: Data) throws -> RepoKeys {
        guard data.count == 64 else { throw RepoCryptoError.malformedKeyMaterial }
        return RepoKeys(masterEncKey: SymmetricKey(data: data.prefix(32)),
                        chunkIDKey: SymmetricKey(data: data.suffix(32)))
    }
}

/// A key slot wraps the master keys under a KEK (from a password or recovery key). Each slot is one
/// repo object (`keys/<slotID>`); adding/removing a slot never touches data objects.
enum KeySlot {
    /// Seal the master keys under `kek`. AES-GCM with a fresh random nonce (the combined blob carries
    /// it) — safe here because each wrap is a one-off under a distinct KEK.
    static func wrap(_ keys: RepoKeys, kek: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.seal(keys.serialized(), using: kek)
        guard let combined = sealed.combined else { throw RepoCryptoError.sealFailed }
        return combined
    }

    static func unwrap(_ wrapped: Data, kek: SymmetricKey) throws -> RepoKeys {
        do {
            let box = try AES.GCM.SealedBox(combined: wrapped)
            let data = try AES.GCM.open(box, using: kek)
            return try RepoKeys.deserialize(data)
        } catch let error as RepoCryptoError {
            throw error
        } catch {
            throw RepoCryptoError.integrityCheckFailed   // wrong KEK or tampered slot
        }
    }
}
