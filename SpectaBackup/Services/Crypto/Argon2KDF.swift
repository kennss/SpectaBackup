//
//  @file        Argon2KDF.swift
//  @description Password-based key derivation using argon2id (vendored libargon2). Turns a
//               low-entropy password + per-slot salt into a 32-byte key-encryption key (KEK) that
//               wraps the repo master keys. Memory-hard → resistant to GPU/ASIC brute force.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//
//  Notes:
//  - Parameters (timeCost / memoryKiB / parallelism) are stored in the repo `config` so they can be
//    raised over time; older repos still verify with their recorded params.
//  - Defaults: 3 passes, 64 MiB, 4 lanes — a reasonable interactive-ish baseline; tune before ship.
//

import Foundation

enum Argon2KDF {

    struct Params: Codable, Sendable, Hashable {
        // Matches the Specta family standard (SpectaloWhisper VAULT_DESIGN.md): m≥256MiB, t≥3, p=1.
        var timeCost: UInt32 = 3
        var memoryKiB: UInt32 = 256 * 1024   // 256 MiB (memory-hard)
        var parallelism: UInt32 = 1
        static let `default` = Params()
    }

    enum KDFError: Error, CustomStringConvertible {
        case argon2(Int32)
        var description: String { "argon2id failed (code \(self)) " }
    }

    /// Derive `keyLength` bytes from `password` + `salt` using argon2id.
    static func deriveKey(password: Data, salt: Data, keyLength: Int = 32,
                          params: Params = .default) throws -> Data {
        var out = Data(count: keyLength)
        let rc: Int32 = out.withUnsafeMutableBytes { outBuf in
            password.withUnsafeBytes { pwdBuf in
                salt.withUnsafeBytes { saltBuf in
                    argon2id_hash_raw(params.timeCost, params.memoryKiB, params.parallelism,
                                      pwdBuf.baseAddress, password.count,
                                      saltBuf.baseAddress, salt.count,
                                      outBuf.baseAddress, keyLength)
                }
            }
        }
        guard rc == 0 else { throw KDFError.argon2(rc) }   // ARGON2_OK == 0
        return out
    }
}
