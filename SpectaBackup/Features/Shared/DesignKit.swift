//
//  @file        DesignKit.swift
//  @description SpectaBackup design tokens. Brand colors shared across the Specta product family
//               (Spectalo / SpectaLing / SpectaBackup). Signature amber is #F5C400 (wpDesignYellow).
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//
//  Notes:
//  - Color naming follows the family convention (`wp` prefix) so tokens match the sibling apps.
//  - Values are sRGB 0–1 components of the documented hex codes.
//

import SwiftUI

public extension Color {
    /// Signature brand amber (#F5C400) — primary accent, shared across the Specta product family.
    static let wpDesignYellow = Color(red: 245 / 255, green: 196 / 255, blue: 0 / 255)
    /// Secondary highlight — iOS Yellow (#FFD60A).
    static let wpYellow = Color(red: 255 / 255, green: 214 / 255, blue: 10 / 255)
    /// Destructive / error — iOS Red (#FF3B30).
    static let wpRed = Color(red: 255 / 255, green: 59 / 255, blue: 48 / 255)
    /// Ink — primary text (#0A0B0D).
    static let wpInk = Color(red: 10 / 255, green: 11 / 255, blue: 13 / 255)
}
