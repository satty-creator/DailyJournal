//
//  AuthViewModel.swift
//  DailyJournal
//
//  Created on 2026-05-25.
//

import Foundation
import FirebaseAuth
import Combine
import AuthenticationServices

enum AuthState: Equatable {
    case loading
    case authenticated
    case unverified        // signed in, but email/password account not yet verified
    case unauthenticated
}

@MainActor
final class AuthViewModel: ObservableObject {

    @Published var authState: AuthState = .loading
    @Published var currentUser: AppUser?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let authService = AuthService()
    private var authStateListener: AuthStateDidChangeListenerHandle?

    init() {
        listenToAuthState()
    }

    deinit {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }

    // MARK: - Auth State Listener
    private func listenToAuthState() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                if let user = user {
                    self?.currentUser = AppUser(id: user.uid, email: user.email ?? "", displayName: user.displayName)
                    if user.isAnonymous {
                        // Guest users go straight to the app — no email to verify.
                        self?.authState = .authenticated
                    } else {
                        // Gate email/password accounts behind verification.
                        // Google/Apple return isEmailVerified == true so they pass through.
                        self?.authState = user.isEmailVerified ? .authenticated : .unverified
                    }
                } else {
                    self?.currentUser = nil
                    self?.authState = .unauthenticated
                }
            }
        }
    }

    // MARK: - Sign Up
    func signUp(email: String, password: String, displayName: String? = nil) async {
        guard validateSignUp(email: email, password: password) else { return }

        isLoading = true
        errorMessage = nil

        AnalyticsManager.shared.trackSignupStarted()

        do {
            let user = try await authService.signUp(email: email, password: password, displayName: displayName)
            currentUser = user

            AnalyticsManager.shared.setUserId(user.id)
            AnalyticsManager.shared.trackSignupCompleted(provider: "email")
            SessionManager.shared.recordSignupDate()

            // The auth state listener will move us to .unverified (verification
            // email has been sent by AuthService).
        } catch {
            errorMessage = error.localizedDescription
            AnalyticsManager.shared.trackError(error, context: "signup_failed")
        }

        isLoading = false
    }

    // MARK: - Email verification
    @Published var verificationMessage: String?

    /// Re-checks verification status after the user taps the link in their inbox.
    func refreshVerificationStatus() async {
        verificationMessage = nil
        do {
            let verified = try await authService.reloadEmailVerified()
            if verified {
                authState = .authenticated
            } else {
                verificationMessage = "Not verified yet — check your inbox, then tap again."
            }
        } catch {
            verificationMessage = error.localizedDescription
        }
    }

    /// Resends the verification email.
    func resendVerificationEmail() async {
        verificationMessage = nil
        do {
            try await authService.sendEmailVerification()
            verificationMessage = "Verification email sent."
        } catch {
            verificationMessage = error.localizedDescription
        }
    }

    // MARK: - Password Reset
    @Published var resetPasswordMessage: String?
    @Published var isResettingPassword = false

    /// Sends a password-reset email. Updates `resetPasswordMessage` with a success
    /// or failure string that LoginView displays inline.
    func resetPassword(email: String) async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            resetPasswordMessage = "Please enter your email address first."
            return
        }
        isResettingPassword = true
        resetPasswordMessage = nil
        do {
            try await authService.sendPasswordReset(email: trimmed)
            resetPasswordMessage = "Reset link sent — check your inbox."
        } catch {
            resetPasswordMessage = error.localizedDescription
        }
        isResettingPassword = false
    }

    // MARK: - Sign In
    func signIn(email: String, password: String) async {
        guard validateSignIn(email: email, password: password) else { return }

        isLoading = true
        errorMessage = nil

        do {
            let user = try await authService.signIn(email: email, password: password)
            currentUser = user

            AnalyticsManager.shared.setUserId(user.id)
            AnalyticsManager.shared.trackLoginCompleted(provider: "email")
        } catch {
            errorMessage = error.localizedDescription
            AnalyticsManager.shared.trackError(error, context: "signin_failed")
        }

        isLoading = false
    }

    // MARK: - Guest / Anonymous Sign In
    func continueAsGuest() async {
        isLoading = true
        errorMessage = nil
        do {
            currentUser = try await authService.signInAnonymously()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// True when the current session is an anonymous/guest account.
    var isGuest: Bool { Auth.auth().currentUser?.isAnonymous ?? false }

    // MARK: - Upgrade guest account to email/password
    @Published var isUpgrading = false
    @Published var upgradeErrorMessage: String?

    func upgradeGuestAccount(email: String, password: String, displayName: String?) async {
        guard validateSignUp(email: email, password: password) else {
            upgradeErrorMessage = errorMessage; return
        }
        isUpgrading = true
        upgradeErrorMessage = nil
        do {
            currentUser = try await authService.linkGuestWithEmail(
                email: email, password: password, displayName: displayName
            )
        } catch {
            upgradeErrorMessage = error.localizedDescription
        }
        isUpgrading = false
    }

    // MARK: - Google Sign In
    func signInWithGoogle() async {
        isLoading = true
        errorMessage = nil

        do {
            let user = try await authService.signInWithGoogle()
            currentUser = user

            AnalyticsManager.shared.setUserId(user.id)
            AnalyticsManager.shared.trackLoginCompleted(provider: "google")
        } catch {
            errorMessage = error.localizedDescription
            AnalyticsManager.shared.trackError(error, context: "google_signin_failed")
        }

        isLoading = false
    }

    // MARK: - Sign in with Apple

    /// The raw nonce for the in-flight Apple request. Set in `prepareAppleRequest`
    /// and consumed in `handleAppleSignIn`.
    private var currentNonce: String?

    /// Configure the ASAuthorization request: request name/email and attach the
    /// hashed nonce. Call from `SignInWithAppleButton`'s `onRequest`.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = AuthService.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = AuthService.sha256(nonce)
    }

    /// Handle the result from `SignInWithAppleButton`'s `onCompletion`.
    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        switch result {
        case .failure(let error):
            // User cancelling isn't an error worth surfacing loudly.
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = error.localizedDescription

        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let rawNonce = currentNonce,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8)
            else {
                errorMessage = "Apple sign-in failed. Please try again."
                return
            }
            do {
                currentUser = try await authService.signInWithApple(
                    idToken: idToken,
                    rawNonce: rawNonce,
                    fullName: credential.fullName
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            currentNonce = nil
        }
    }

    // MARK: - Update Display Name
    // Optimistic: update the local model immediately so the UI reflects the change
    // at once, then sync to Firebase Auth + Firestore in the background.
    func updateDisplayName(_ name: String) {
        currentUser?.displayName = name
        let service = authService
        Task { try? await service.updateDisplayName(name) }
    }

    // MARK: - Sign Out
    func signOut() {
        do {
            try authService.signOut()
            AnalyticsManager.shared.logEvent(.signoutCompleted)
        } catch {
            errorMessage = error.localizedDescription
            AnalyticsManager.shared.trackError(error, context: "signout_failed")
        }
    }

    // MARK: - Delete Account

    @Published var isDeletingAccount = false
    @Published var deleteErrorMessage: String?

    /// Permanently deletes the account and all associated data.
    ///
    /// For Sign in with Apple users, pass the `authorizationCode` from a
    /// fresh `ASAuthorizationAppleIDCredential` so Apple can revoke the
    /// token (required by App Store guidelines).
    func deleteAccount(appleAuthorizationCode: String? = nil) async {
        isDeletingAccount = true
        deleteErrorMessage = nil
        defer { isDeletingAccount = false }

        do {
            try await authService.deleteAccount(appleAuthorizationCode: appleAuthorizationCode)
            AnalyticsManager.shared.logEvent(.accountDeleted)
            // Auth state listener fires automatically → .unauthenticated
        } catch let nsErr as NSError
            where nsErr.code == AuthErrorCode.requiresRecentLogin.rawValue
        {
            deleteErrorMessage = "For your security, please sign out and sign back in before deleting your account."
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
    }

    /// Returns true if the current user authenticated via Sign in with Apple.
    var isAppleUser: Bool {
        Auth.auth().currentUser?.providerData
            .contains(where: { $0.providerID == "apple.com" }) ?? false
    }

    // MARK: - Apple re-auth for account deletion
    //
    // Deletion of an Apple-linked account requires a fresh Apple authorization
    // to obtain the one-time authorizationCode for token revocation.
    // `pendingAppleDeletion` signals the UI to trigger a new Sign in with Apple
    // sheet, whose completion should call `confirmAppleDeletion`.

    @Published var pendingAppleDeletion = false

    func requestAppleDeletion() {
        pendingAppleDeletion = true
    }

    func confirmAppleDeletion(_ result: Result<ASAuthorization, Error>) async {
        pendingAppleDeletion = false
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                deleteErrorMessage = error.localizedDescription
            }
        case .success(let auth):
            guard
                let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                let codeData = credential.authorizationCode,
                let code = String(data: codeData, encoding: .utf8)
            else {
                deleteErrorMessage = "Apple authorisation failed. Please try again."
                return
            }
            await deleteAccount(appleAuthorizationCode: code)
        }
    }

    // MARK: - Validation
    private func validateSignUp(email: String, password: String) -> Bool {
        if email.isEmpty || password.isEmpty {
            errorMessage = "Please fill in all fields."
            return false
        }
        if !email.contains("@") {
            errorMessage = "Please enter a valid email."
            return false
        }
        if password.count < 6 {
            errorMessage = "Password must be at least 6 characters."
            return false
        }
        return true
    }

    private func validateSignIn(email: String, password: String) -> Bool {
        if email.isEmpty || password.isEmpty {
            errorMessage = "Please fill in all fields."
            return false
        }
        return true
    }
}