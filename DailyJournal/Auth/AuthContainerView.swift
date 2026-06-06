//
//  AuthContainerView.swift
//  DailyJournal
//
//  Created on 2026-05-25.
//

import SwiftUI

struct AuthContainerView: View {
    @State private var showingLogin = true

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            if showingLogin {
                LoginView(onSwitchToSignup: { showingLogin = false })
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading),
                        removal: .move(edge: .trailing)
                    ))
            } else {
                SignupView(onSwitchToLogin: { showingLogin = true })
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showingLogin)
    }
}