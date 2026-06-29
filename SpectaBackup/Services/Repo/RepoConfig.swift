//
//  @file        RepoConfig.swift
//  @description The encrypted repo's `config` object: format version, chunker parameters, and the
//               argon2 KDF parameters. Stored (plaintext, no secrets) as a backend object; loaded to
//               drive chunking and key derivation. Backward-compatible decoding so older repos load.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-30
//  @lastUpdated 2026-06-30
//

import Foundation

struct RepoConfig: Codable, Sendable {
    var formatVersion: Int
    var chunkerMinSize: Int
    var chunkerAvgSize: Int
    var chunkerMaxSize: Int
    var argon2: Argon2KDF.Params

    init(formatVersion: Int = 1,
         chunkerMinSize: Int = 512 * 1024,
         chunkerAvgSize: Int = 1024 * 1024,
         chunkerMaxSize: Int = 8 * 1024 * 1024,
         argon2: Argon2KDF.Params = .default) {
        self.formatVersion = formatVersion
        self.chunkerMinSize = chunkerMinSize
        self.chunkerAvgSize = chunkerAvgSize
        self.chunkerMaxSize = chunkerMaxSize
        self.argon2 = argon2
    }

    var chunker: FastCDC {
        FastCDC(minSize: chunkerMinSize, avgSize: chunkerAvgSize, maxSize: chunkerMaxSize)
    }

    // Backward-compatible decoding: missing fields fall back to current defaults.
    enum CodingKeys: String, CodingKey {
        case formatVersion, chunkerMinSize, chunkerAvgSize, chunkerMaxSize, argon2
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        chunkerMinSize = try c.decodeIfPresent(Int.self, forKey: .chunkerMinSize) ?? 512 * 1024
        chunkerAvgSize = try c.decodeIfPresent(Int.self, forKey: .chunkerAvgSize) ?? 1024 * 1024
        chunkerMaxSize = try c.decodeIfPresent(Int.self, forKey: .chunkerMaxSize) ?? 8 * 1024 * 1024
        argon2 = try c.decodeIfPresent(Argon2KDF.Params.self, forKey: .argon2) ?? .default
    }
}
