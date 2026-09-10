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

    // Forgot-password flow
    @State private var showForgotPassword = false
    @State private var resetEmail = ""

    enum Field { case email, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {

                // Header
                VStack(spacing: 8) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(AppTheme.primary)

                    Text("Welcome Back")
                        .font(.largeTitle.bold())

                    Text("Continue your journey")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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

                    // Forgot password — right-aligned below the password field
                    HStack {
                        Spacer()
                        Button("Forgot password?") {
                            resetEmail = email  // pre-fill with whatever's typed
                            showForgotPassword = true
                        }
                        .font(.footnote)
                        .foregroundStyle(AppTheme.terracotta)
                    }
                }

                // Error / reset-password messages
                if let error = authViewModel.errorMessage {
                    ErrorBanner(message: error)
                }
                if let msg = authViewModel.resetPasswordMessage {
                    Text(msg)
                        .font(.footnote)
                        .foregroundStyle(msg.contains("sent") ? AppTheme.terracotta : .red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
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
                        .foregroundStyle(.secondary)
                    Button("Sign Up") { onSwitchToSignup() }
                        .foregroundStyle(AppTheme.primary)
                        .fontWeight(.semibold)
                }
                .font(.subheadline)

                // Guest mode — satisfies App Store Guideline 5.1.1(v)
                Button {
                    Task { await authViewModel.continueAsGuest() }
                } label: {
                    Text("Continue without account")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .underline()
                }
                .disabled(authViewModel.isLoading)

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 24)
        }
        // Forgot-password email input
        .alert("Reset password", isPresented: $showForgotPassword) {
            TextField("Email address", text: $resetEmail)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Send reset link") {
                authViewModel.resetPasswordMessage = nil
                Task { await authViewModel.resetPassword(email: resetEmail) }
            }
            .disabled(authViewModel.isResettingPassword)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("We'll email you a link to reset your password.")
        }
        .trackScreen(.authLogin)
    }
}