//
//  @file        RepoCryptoTests.swift
//  @description Tests for the encrypted dedup repo crypto: blob seal/open round-trip, deterministic
//               (dedup-friendly) blob IDs, tamper detection, wrong-key failure, key-slot wrap/unwrap,
//               argon2 stability, and recovery-key round-trip + slot unlock.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//

import XCTest
import CryptoKit
@testable import SpectaBackup

final class RepoCryptoTests: XCTestCase {

    func testBlobSealOpenRoundTrip() throws {
        let cipher = BlobCipher(keys: .generate())
        let plaintext = Data("hello, encrypted world".utf8)
        let (id, ciphertext) = try cipher.seal(plaintext)
        XCTAssertEqual(try cipher.open(blobID: id, ciphertext: ciphertext), plaintext)
    }

    func testDeterministicBlobIDEnablesDedup() throws {
        let cipher = BlobCipher(keys: .generate())
        let plaintext = Data("dedup me".utf8)
        XCTAssertEqual(cipher.blobID(for: plaintext), cipher.blobID(for: plaintext))
        let (id1, _) = try cipher.seal(plaintext)
        let (id2, _) = try cipher.seal(plaintext)
        XCTAssertEqual(id1, id2, "identical content must yield the same blob ID")
    }

    func testTamperIsDetected() throws {
        let cipher = BlobCipher(keys: .generate())
        let (id, ciphertext) = try cipher.seal(Data("secret".utf8))
        var bad = ciphertext
        bad[0] ^= 0xFF
        XCTAssertThrowsError(try cipher.open(blobID: id, ciphertext: bad))
    }

    func testWrongKeyFails() throws {
        let a = BlobCipher(keys: .generate())
        let b = BlobCipher(keys: .generate())
        let (id, ciphertext) = try a.seal(Data("private".utf8))
        XCTAssertThrowsError(try b.open(blobID: id, ciphertext: ciphertext))
    }

    func testKeySlotWrapUnwrap() throws {
        let keys = RepoKeys.generate()
        let kek = SymmetricKey(size: .bits256)
        let wrapped = try KeySlot.wrap(keys, kek: kek)
        XCTAssertEqual(try KeySlot.unwrap(wrapped, kek: kek).serialized(), keys.serialized())
        XCTAssertThrowsError(try KeySlot.unwrap(wrapped, kek: SymmetricKey(size: .bits256)))
    }

    func testArgon2DerivesStableKey() throws {
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...UInt8.max) })
        let password = Data("correct horse battery staple".utf8)
        let params = Argon2KDF.Params(timeCost: 1, memoryKiB: 8 * 1024, parallelism: 1)   // fast for tests
        let k1 = try Argon2KDF.deriveKey(password: password, salt: salt, params: params)
        let k2 = try Argon2KDF.deriveKey(password: password, salt: salt, params: params)
        XCTAssertEqual(k1, k2)
        XCTAssertEqual(k1.count, 32)
    }

    func testRecoveryKeyRoundTripAndSlot() throws {
        let (raw, formatted) = RecoveryKey.generate()
        XCTAssertEqual(RecoveryKey.parse(formatted), raw, "recovery key must survive format → parse")

        // A slot wrapped with the recovery KEK unlocks via the formatted string.
        let keys = RepoKeys.generate()
        let wrapped = try KeySlot.wrap(keys, kek: RecoveryKey.deriveKEK(raw: raw))
        let reparsed = try XCTUnwrap(RecoveryKey.parse(formatted))
        let unwrapped = try KeySlot.unwrap(wrapped, kek: RecoveryKey.deriveKEK(raw: reparsed))
        XCTAssertEqual(unwrapped.serialized(), keys.serialized())
    }
}
