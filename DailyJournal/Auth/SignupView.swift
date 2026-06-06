//
//  SignupView.swift
//  DailyJournal
//
//  Created on 2026-05-25.
//

import SwiftUI

struct SignupView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    var onSwitchToLogin: () -> Void

    @State private var email = ""
    @State private var displayName = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @FocusState private var focusedField: Field?

    enum Field { case email, displayName, password, confirmPassword }

    private var passwordsMatch: Bool {
        password == confirmPassword || confirmPassword.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {

                // Header
                VStack(spacing: 8) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 60))
                        .foregroundColor(AppTheme.primary)

                    Text("Start Your Journey")
                        .font(.largeTitle.bold())

                    Text("Create an account to begin")
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
                    .onSubmit { focusedField = .displayName }

                    CustomTextField(
                        placeholder: "Display name (optional)",
                        text: $displayName,
                        systemImage: "person"
                    )
                    .focused($focusedField, equals: .displayName)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }

                    CustomTextField(
                        placeholder: "Password",
                        text: $password,
                        isSecure: true,
                        systemImage: "lock"
                    )
                    .focused($focusedField, equals: .password)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .confirmPassword }

                    VStack(alignment: .leading, spacing: 4) {
                        CustomTextField(
                            placeholder: "Confirm Password",
                            text: $confirmPassword,
                            isSecure: true,
                            systemImage: "lock.fill"
                        )
                        .focused($focusedField, equals: .confirmPassword)
                        .submitLabel(.done)

                        if !passwordsMatch {
                            Text("Passwords do not match")
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.leading, 4)
                        }
                    }
                }

                // Error Message
                if let error = authViewModel.errorMessage {
                    ErrorBanner(message: error)
                }

                // Signup Button
                PrimaryButton(
                    title: "Create Account",
                    isLoading: authViewModel.isLoading,
                    isDisabled: !passwordsMatch
                ) {
                    Task { await authViewModel.signUp(email: email, password: password, displayName: displayName) }
                }

                // Divider
                DividerWithText(text: "or continue with")

                // Apple Sign In
                AppleSignInButton()

                // Google Sign In
                GoogleSignInButton {
                    Task { await authViewModel.signInWithGoogle() }
                }

                // Switch to Login
                HStack {
                    Text("Already have an account?")
                        .foregroundColor(.secondary)
                    Button("Sign In") { onSwitchToLogin() }
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