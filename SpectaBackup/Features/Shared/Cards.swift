//
//  @file        Cards.swift
//  @description Reusable dashboard building blocks: a card surface modifier, a labeled StatCard, and
//               a StorageGauge bar. Shared across the JobDetail dashboard for a consistent look.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//

import SwiftUI

extension View {
    /// Standard card background: subtle filled rounded rect with a hairline border.
    func cardSurface(cornerRadius: CGFloat = 12) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}

/// A compact stat tile: small caption + large value, with an optional tinted icon.
struct StatCard: View {
    let title: String
    let value: String
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage).foregroundStyle(tint)
                }
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(value).font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardSurface()
    }
}

/// A horizontal usage bar (0…1) with a caption, tinted with the brand amber.
struct StorageGauge: View {
    let label: String
    let usedFraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(Color.wpDesignYellow)
                        .frame(width: max(0, min(1, usedFraction)) * geo.size.width)
                }
            }
            .frame(height: 10)
        }
        .padding(14)
        .cardSurface()
    }
}
