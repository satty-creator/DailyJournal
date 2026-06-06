//
//  LoginView.swift
//  DailyJournal
//
//  Created on 2026-05-25.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    var onSwitchToSignup: () -> Void

    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    enum Field { case email, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {

                // Header
                VStack(spacing: 8) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 60))
                        .foregroundColor(AppTheme.primary)

                    Text("Welcome Back")
                        .font(.largeTitle.bold())

                    Text("Continue your journey")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 60)

                // Form
                VStack(spacing: 16) {
                    CustomTextField(
                        placeholder: "Email",
                        text: $email,
                        keyboardType: .emailAddress,
                        systemImage: "envelope"
                    )
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }

                    CustomTextField(
                        placeholder: "Password",
                        text: $password,
                        isSecure: true,
                        systemImage: "lock"
                    )
                    .focused($focusedField, equals: .password)
                    .submitLabel(.done)
                    .onSubmit { Task { await authViewModel.signIn(email: email, password: password) } }
                }

                // Error Message
                if let error = authViewModel.errorMessage {
                    ErrorBanner(message: error)
                }

                // Login Button
                PrimaryButton(
                    title: "Sign In",
                    isLoading: authViewModel.isLoading
                ) {
                    Task { await authViewModel.signIn(email: email, password: password) }
                }

                // Divider
                DividerWithText(text: "or continue with")

                // Apple Sign In
                AppleSignInButton()

                // Google Sign In
                GoogleSignInButton {
                    Task { await authViewModel.signInWithGoogle() }
                }

                // Switch to Signup
                HStack {
                    Text("Don't have an account?")
                        .foregroundColor(.secondary)
                    Button("Sign Up") { onSwitchToSignup() }
                        .foregroundColor(AppTheme.primary)
                        .fontWeight(.semibold)
                }
                .font(.subheadline)

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 24)
        }
    }
}