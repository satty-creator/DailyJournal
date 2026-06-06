//
//  AppleSignInButton.swift
//  DailyJournal
//
//  Thin wrapper around Apple's SignInWithAppleButton so the auth screens stay
//  declarative. The nonce + credential handling lives in AuthViewModel.
//

import SwiftUI
import AuthenticationServices

struct AppleSignInButton: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            authViewModel.prepareAppleRequest(request)
        } onCompletion: { result in
            Task { await authViewModel.handleAppleSignIn(result) }
        }
        // Apple's HIG requires the system button; .black reads well on the warm
        // paper background and matches the app's ink palette.
        .signInWithAppleButtonStyle(.black)
        .frame(height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
