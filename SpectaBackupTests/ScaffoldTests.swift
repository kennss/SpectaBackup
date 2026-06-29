//
//  @file        ScaffoldTests.swift
//  @description Placeholder test so the test bundle builds from the start. Real engine safety
//               tests (clone immutability, atomic publish, metadata round-trip, fault injection)
//               land in the dedicated test task.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//

import XCTest
import SwiftUI
@testable import SpectaBackup

final class ScaffoldTests: XCTestCase {
    func testSignatureColorExists() {
        // The signature brand color must stay #F5C400 (wpDesignYellow) across the Specta family.
        _ = Color.wpDesignYellow
    }
}
