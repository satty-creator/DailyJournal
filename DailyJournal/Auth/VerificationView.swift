//
//  VerificationView.swift
//  DailyJournal
//
//  Shown when an email/password account is signed in but the email address
//  has not yet been verified. Access to the app is gated until the user taps
//  the link in their inbox and returns here to continue.
//

import SwiftUI

struct VerificationView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var isChecking = false
    @State private var isResending = false

    private var email: String { authViewModel.currentUser?.email ?? "your email" }

    var body: some View {
        ZStack {
            AppTheme.paper.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                Image(systemName: "envelope.badge")
                    .font(.system(size: 56))
                    .foregroundStyle(AppTheme.terracotta)

                VStack(spacing: 10) {
                    Text("Check your inbox")
                        .font(AppTheme.editorialDisplay(size: 30))
                        .foregroundStyle(AppTheme.ink)

                    Text("We sent a verification link to")
                        .font(AppTheme.editorialBody(size: 15))
                        .foregroundStyle(AppTheme.inkSoft)

                    Text(email)
                        .font(AppTheme.mono(size: 13))
                        .foregroundStyle(AppTheme.terracotta)
                        .tracking(0.3)

                    Text("Tap the link, then come back and continue.")
                        .font(AppTheme.editorialBody(size: 14))
                        .foregroundStyle(AppTheme.inkSoft)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

                if let message = authViewModel.verificationMessage {
                    Text(message)
                        .font(AppTheme.mono(size: 11))
                        .foregroundStyle(AppTheme.inkSoft)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .transition(.opacity)
                }

                VStack(spacing: 14) {
                    PrimaryButton(
                        title: "I've verified — continue",
                        isLoading: isChecking,
                        isDisabled: false
                    ) {
                        Task {
                            isChecking = true
                            await authViewModel.refreshVerificationStatus()
                            isChecking = false
                        }
                    }

                    Button {
                        Task {
                            isResending = true
                            await authViewModel.resendVerificationEmail()
                            isResending = false
                        }
                    } label: {
                        Text(isResending ? "Sending…" : "Resend email")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppTheme.terracotta)
                    }
                    .disabled(isResending)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                Spacer()

                Button {
                    authViewModel.signOut()
                } label: {
                    Text("Use a different account")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.inkSoft)
                }
                .padding(.bottom, 32)
            }
            .animation(.easeInOut(duration: 0.25), value: authViewModel.verificationMessage)
        }
    }
}
