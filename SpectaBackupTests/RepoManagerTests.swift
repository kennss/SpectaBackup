//
//  @file        RepoManagerTests.swift
//  @description Tests for repo init/unlock: create → unlock with password, create → unlock with the
//               recovery key, wrong password fails, double-create fails, and RepoConfig backward-
//               compatible decoding. Uses fast argon2 params so the suite stays quick.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-30
//  @lastUpdated 2026-06-30
//

import XCTest
import CryptoKit
@testable import SpectaBackup

final class RepoManagerTests: XCTestCase {

    private var tmp: URL!
    private let fastConfig = RepoConfig(argon2: Argon2KDF.Params(timeCost: 1, memoryKiB: 8 * 1024, parallelism: 1))

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sbk-repo-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testCreateThenUnlockWithPassword() async throws {
        let backend = try LocalBackend(root: tmp)
        let created = try await RepoManager.create(backend: backend, password: Data("hunter2".utf8), config: fastConfig)
        let unlocked = try await RepoManager.unlock(backend: backend, password: Data("hunter2".utf8))
        XCTAssertEqual(unlocked.keys.serialized(), created.keys.serialized())
    }

    func testUnlockWithRecoveryKey() async throws {
        let backend = try LocalBackend(root: tmp)
        let created = try await RepoManager.create(backend: backend, password: Data("hunter2".utf8), config: fastConfig)
        let unlocked = try await RepoManager.unlockWithRecovery(backend: backend, recoveryKey: created.recoveryKey)
        XCTAssertEqual(unlocked.keys.serialized(), created.keys.serialized())
    }

    func testWrongPasswordFails() async throws {
        let backend = try LocalBackend(root: tmp)
        _ = try await RepoManager.create(backend: backend, password: Data("hunter2".utf8), config: fastConfig)
        do {
            _ = try await RepoManager.unlock(backend: backend, password: Data("wrong".utf8))
            XCTFail("unlock with wrong password should throw")
        } catch { /* expected */ }
    }

    func testDoubleCreateFails() async throws {
        let backend = try LocalBackend(root: tmp)
        _ = try await RepoManager.create(backend: backend, password: Data("pw".utf8), config: fastConfig)
        do {
            _ = try await RepoManager.create(backend: backend, password: Data("pw".utf8), config: fastConfig)
            XCTFail("creating over an existing repo should throw")
        } catch { /* expected */ }
    }

    func testConfigBackwardCompatDecoding() throws {
        let json = Data(#"{"formatVersion":1}"#.utf8)
        let config = try JSONDecoder().decode(RepoConfig.self, from: json)
        XCTAssertEqual(config.chunkerAvgSize, 1024 * 1024)                       // default filled in
        XCTAssertEqual(config.argon2.memoryKiB, Argon2KDF.Params.default.memoryKiB)
    }
}
