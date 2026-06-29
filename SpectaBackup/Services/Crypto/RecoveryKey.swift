//
//  @file        RecoveryKey.swift
//  @description A high-entropy (256-bit) recovery key that unlocks its own key slot, so a forgotten
//               password or a dead Mac can still recover the repo. High entropy ⇒ HKDF directly to
//               a KEK (no argon2 needed). Shown once at repo creation; the user must save it.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//
//  Format: RFC 4648 base32 (no padding), upper-case, grouped in 4-char blocks with dashes for
//  readability, e.g. "A2BC-DEF3-…". `parse` is dash/space/case tolerant.
//

import CryptoKit
import Foundation

enum RecoveryKey {

    /// Generate a fresh recovery key; returns raw bytes and the display string.
    static func generate() -> (raw: Data, formatted: String) {
        var raw = Data(count: 32)
        raw.withUnsafeMutableBytes { _ = SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        return (raw, format(raw))
    }

    /// Derive the slot KEK from the raw recovery key (no argon2 — input is already high-entropy).
    static func deriveKEK(raw: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: raw),
                               info: Data("spectabackup.recovery.v1".utf8),
                               outputByteCount: 32)
    }

    static func format(_ data: Data) -> String {
        let encoded = base32Encode(data)
        var out = ""
        for (i, ch) in encoded.enumerated() {
            if i > 0 && i % 4 == 0 { out.append("-") }
            out.append(ch)
        }
        return out
    }

    static func parse(_ formatted: String) -> Data? {
        let cleaned = String(formatted.uppercased().filter { $0 != "-" && !$0.isWhitespace })
        return base32Decode(cleaned)
    }

    // MARK: - base32 (RFC 4648)

    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    private static func base32Encode(_ data: Data) -> String {
        var result = ""
        var bits = 0, value = 0
        for byte in data {
            value = (value << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                result.append(alphabet[(value >> (bits - 5)) & 0x1F])
                bits -= 5
            }
        }
        if bits > 0 { result.append(alphabet[(value << (5 - bits)) & 0x1F]) }
        return result
    }

    private static func base32Decode(_ string: String) -> Data? {
        var lookup = [Character: Int]()
        for (index, char) in alphabet.enumerated() { lookup[char] = index }
        var bits = 0, value = 0
        var out = Data()
        for char in string {
            guard let v = lookup[char] else { return nil }
            value = (value << 5) | v
            bits += 5
            if bits >= 8 {
                out.append(UInt8((value >> (bits - 8)) & 0xFF))
                bits -= 8
            }
        }
        return out
    }
}
