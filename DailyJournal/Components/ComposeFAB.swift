//
//  ComposeFAB.swift
//  DailyJournal
//
//  A floating "pencil" compose button that opens the Spill write screen. Applied
//  to the tabs that aren't the Today hub (River, Patterns, Journal) so there's a
//  consistent way to start writing from anywhere — same destination as the Home
//  write actions.
//

import SwiftUI

private struct ComposeFABModifier: ViewModifier {
    let userId: String
    let onSaved: () -> Void
    @State private var show = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                Button { show = true } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.cream)
                        .frame(width: 60, height: 60)
                        .background(AppTheme.terracotta)
                        .clipShape(Circle())
                        .shadow(color: AppTheme.terracotta.opacity(0.4), radius: 12, x: 0, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 24)
                .padding(.bottom, 28)
                .accessibilityLabel("New entry")
            }
            .fullScreenCover(isPresented: $show, onDismiss: onSaved) {
                SpillWriteView(userId: userId) { onSaved() }
            }
    }
}

extension View {
    /// Adds a floating pencil compose button that presents `SpillWriteView`.
    func composeFAB(userId: String, onSaved: @escaping () -> Void = {}) -> some View {
        modifier(ComposeFABModifier(userId: userId, onSaved: onSaved))
    }
}
