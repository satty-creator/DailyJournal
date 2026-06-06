//
//  GoogleSignInButton.swift
//  DailyJournal
//
//  Created on 2026-05-25.
//

import SwiftUI

struct GoogleSignInButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .foregroundColor(.primary)

                Text("Continue with Google")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
    }
}