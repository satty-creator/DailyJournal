//
//  DividerWithText.swift
//  DailyJournal
//
//  Created on 2026-05-25.
//

import SwiftUI

struct DividerWithText: View {
    let text: String

    var body: some View {
        HStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)

            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)

            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)
        }
    }
}