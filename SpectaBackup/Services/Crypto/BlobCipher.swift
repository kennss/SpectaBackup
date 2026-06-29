//
//  @file        BlobCipher.swift
//  @description Per-blob content-addressed encryption for the dedup repo. The blob ID is a KEYED
//               hash (HMAC) so dedup still works while the provider can't fingerprint content; the
//               data key is derived per-blob from its ID, so a fixed nonce is safe — distinct
//               content never shares (key, nonce), eliminating GCM nonce-reuse with no coordination.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//

import CryptoKit
import Foundation

struct BlobCipher: Sendable {
    private let masterEncKey: SymmetricKey
    private let chunkIDKey: SymmetricKey

    // Fixed 96-bit zero nonce: safe because objectKey is unique per distinct content (see above).
    private static let zeroNonce = try! AES.GCM.Nonce(data: Data(count: 12))
    private static let tagLength = 16

    init(keys: RepoKeys) {
        masterEncKey = keys.masterEncKey
        chunkIDKey = keys.chunkIDKey
    }

    /// Content-addressed, keyed blob ID.
    func blobID(for plaintext: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: plaintext, using: chunkIDKey))
    }

    /// Encrypt a blob; returns its ID and `ciphertext‖tag` (fixed nonce, so it isn't stored).
    func seal(_ plaintext: Data) throws -> (blobID: Data, ciphertext: Data) {
        let id = blobID(for: plaintext)
        let box = try AES.GCM.seal(plaintext, using: objectKey(for: id), nonce: Self.zeroNonce)
        // box.ciphertext is a SLICE of CryptoKit's combined nonce‖ct‖tag buffer (startIndex = nonce
        // offset, not 0), and Data's `+` preserves the left operand's startIndex. Re-base to a fresh
        // 0-based Data so the returned blob can be absolutely subscripted/persisted safely.
        return (id, Data(box.ciphertext) + box.tag)
    }

    /// Decrypt and verify (AES-GCM tag AND blobID == keyedHash(plaintext)).
    func open(blobID id: Data, ciphertext: Data) throws -> Data {
        guard ciphertext.count >= Self.tagLength else { throw RepoCryptoError.integrityCheckFailed }
        let ct = ciphertext.prefix(ciphertext.count - Self.tagLength)
        let tag = ciphertext.suffix(Self.tagLength)
        do {
            let box = try AES.GCM.SealedBox(nonce: Self.zeroNonce, ciphertext: ct, tag: tag)
            let plaintext = try AES.GCM.open(box, using: objectKey(for: id))
            guard blobID(for: plaintext) == id else { throw RepoCryptoError.integrityCheckFailed }
            return plaintext
        } catch let error as RepoCryptoError {
            throw error
        } catch {
            throw RepoCryptoError.integrityCheckFailed
        }
    }

    /// Per-blob data key derived from the master key and the blob ID.
    private func objectKey(for blobID: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: masterEncKey, info: blobID, outputByteCount: 32)
    }
}
