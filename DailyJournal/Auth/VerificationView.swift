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
    @Environment(\.scenePhase) private var scenePhase
    @State private var isChecking = false
    @State private var isResending = false

    private var email: String { authViewModel.currentUser?.email ?? "your email" }

    /// Resend is throttled by Firebase per IP and per address, so the button
    /// states its own wait rather than letting the user discover the limit.
    private var canResend: Bool { !isResending && authViewModel.resendCooldown == 0 }

    private var resendTitle: String {
        if isResending { return "Sending…" }
        let remaining = authViewModel.resendCooldown
        return remaining > 0 ? "Resend email in \(remaining)s" : "Resend email"
    }

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

                    // Firebase's shared sender often lands in Gmail's Spam,
                    // which also disables the link until it's moved out.
                    Text("Not there? Check your Spam folder.")
                        .font(AppTheme.mono(size: 11))
                        .foregroundStyle(AppTheme.inkSoft)
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
                        Text(resendTitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(canResend ? AppTheme.terracotta : AppTheme.inkSoft)
                    }
                    .disabled(!canResend)
                    .animation(.easeInOut(duration: 0.2), value: canResend)
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
        // Cold launch starts already `.active`, so the onChange below never
        // fires then — check once on appear too.
        .task { await authViewModel.recheckVerificationSilently() }
        // Back from the inbox/browser — pick up a verification that happened
        // outside the app without making the user tap "continue".
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await authViewModel.recheckVerificationSilently() }
            }
        }
    }
}
