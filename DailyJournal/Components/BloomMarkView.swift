//
//  BloomMarkView.swift
//  DailyJournal
//
//  The "bloom" mark — a small three-petal flower with a bright core — used
//  wherever Spilr's identity needs a mark instead of an avatar: the dark
//  invitation card, and the chat header. Pure SwiftUI shapes, no assets,
//  following `MascotView`'s no-assets precedent.
//
//  Geometry mirrors the Spilr Redesign mockup exactly: three petal capsules
//  offset from center and rotated 120° apart (so each petal's long axis
//  points radially outward, like a three-petal flower), with a small round
//  core on top. Default colours assume a dark surface (rose/terracotta
//  petals, sun core); pass `petalColors`/`coreColor` to recolour for a
//  light surface.
//

import SwiftUI

struct BloomMarkView: View {
    var size: CGFloat = 32
    /// Three petal colours, applied in ring order (index 0, 1, 2 → 0°, 120°, 240°).
    /// Repeats if fewer than 3 are given, matching the mockup's rose/terracotta/rose.
    var petalColors: [Color] = [AppTheme.rose, AppTheme.terracotta, AppTheme.rose]
    var coreColor: Color = AppTheme.sun

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(petalColors[i % petalColors.count])
                    .frame(width: size * (11.0 / 32.0), height: size * (19.0 / 32.0))
                    .offset(y: -size * (7.0 / 32.0))
                    .rotationEffect(.degrees(Double(i) * 120))
            }
            Circle()
                .fill(coreColor)
                .frame(width: size * (11.0 / 32.0), height: size * (11.0 / 32.0))
        }
        .frame(width: size, height: size)
    }
}
