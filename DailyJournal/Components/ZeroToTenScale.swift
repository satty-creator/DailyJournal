//
//  ZeroToTenScale.swift
//  DailyJournal
//
//  A row of tappable 0–10 self-rating buttons, tinted along the app's
//  canonical valence gradient. Extracted from `TemplateRunnerView`'s original
//  `scaleControl` (which only ever showed six buttons: 0,2,4,6,8,10) so it
//  can also render the full 0...10 range for onboarding's baseline and
//  before/after ratings, where a coarser six-button scale would lose
//  resolution on someone's very first rating.
//

import SwiftUI

struct ZeroToTenScale: View {
    let values: [Int]
    @Binding var selected: Int?
    /// Shown under the row. Defaults to the same wording `TemplateRunnerView`
    /// has always used; onboarding steps pass their own.
    var helperText: String = "Use an approximate number. The point is comparison, not precision."

    init(values: [Int] = [0, 2, 4, 6, 8, 10], selected: Binding<Int?>, helperText: String? = nil) {
        self.values = values
        self._selected = selected
        if let helperText { self.helperText = helperText }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 0...10 (11 buttons) needs a tighter grid than a row to stay
            // legible at phone width; the original six-button spacing still
            // fits comfortably in one row.
            let columns = values.count > 6
                ? Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)
                : Array(repeating: GridItem(.flexible(), spacing: 6), count: values.count)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(values, id: \.self) { v in
                    let isSelected = selected == v
                    // Maps 0…10 onto the app's canonical -3…+3 valence gradient.
                    let tint = AppTheme.valenceColor(v / 2 - 3)
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { selected = v }
                    } label: {
                        Text("\(v)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(isSelected ? tint.opacity(0.85) : AppTheme.cream.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(isSelected ? tint : AppTheme.inkSoft.opacity(0.15), lineWidth: 1.5)
                            )
                            .foregroundStyle(isSelected ? AppTheme.ink : AppTheme.inkSoft)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(v) out of 10")
                    .accessibilityIdentifier("scale.\(v)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            if !helperText.isEmpty {
                Text(helperText)
                    .font(AppTheme.editorialBody(size: 12))
                    .foregroundStyle(AppTheme.inkSoft)
            }
        }
    }
}
