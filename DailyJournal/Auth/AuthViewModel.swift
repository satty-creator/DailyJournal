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

    /// The demo account handed to App Review in App Store Connect.
    ///
    /// Nobody reads this mailbox, so the verification email Firebase sends on
    /// sign-up can never be opened and `isEmailVerified` stays false forever.
    /// Reviewers therefore signed in successfully and then hit
    /// `VerificationView`'s "Check your inbox" wall, which they reported as the
    /// app demanding an authentication code — Guideline 2.1(a), submission
    /// 7225aa5b, September 2026.
    private static let reviewDemoEmail = "test@spilr.com"

    /// True for the App Review demo account, whatever its verification state.
    ///
    /// The address must stay byte-identical to the Demo Account username in
    /// App Store Connect → App Review Information. Firebase already lower-cases
    /// the addresses it stores, but both sides are normalised anyway: the cost
    /// is nothing, and the failure mode of a near-miss — a silent no-op that
    /// resurfaces weeks later as another rejection — is expensive.
    private static func isReviewDemoAccount(_ user: User) -> Bool {
        guard let email = user.email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else { return false }
        return email == reviewDemoEmail
    }

    /// Email verification proves the person owns the address. The review
    /// account's address is ours, it exists only for review, and it is still
    /// protected by its password — so waiving *that one* check costs nothing
    /// and grants nothing. The account is an ordinary signed-in user
    /// afterwards, with no extra entitlement or privilege anywhere.
    private static func passesVerificationGate(_ user: User) -> Bool {
        user.isEmailVerified || isReviewDemoAccount(user)
    }

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
                    // Closes the launch-time race where FCM hands us a
                    // cached token before this listener resolves a uid.
                    PushNotificationManager.shared.resaveCurrentTokenIfNeeded()
                    if user.isAnonymous {
                        // Guest users go straight to the app — no email to verify.
                        self?.authState = .authenticated
                    } else {
                        // Gate email/password accounts behind verification.
                        // Google/Apple return isEmailVerified == true so they pass through,
                        // as does the App Review demo account — see reviewDemoEmail.
                        self?.authState = Self.passesVerificationGate(user) ? .authenticated : .unverified
                        // Restores RevenueCat's identification on relaunch — see
                        // AuthService.reidentifyRevenueCat's doc comment.
                        await self?.authService.reidentifyRevenueCat(uid: user.uid)
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
            // email has been sent by AuthService). That send counts against the
            // throttle, so the cooldown starts here rather than on first tap.
            startResendCooldown()
        } catch {
            errorMessage = error.localizedDescription
            AnalyticsManager.shared.trackError(error, context: "signup_failed")
        }

        isLoading = false
    }

    // MARK: - Email verification
    @Published var verificationMessage: String?

    /// Seconds remaining before another verification email may be requested.
    /// 0 means the Resend button is live.
    ///
    /// Firebase throttles `sendOobCode` per IP *and* per address, and the quota
    /// is small. Without a cooldown a new user waiting on a slow corporate inbox
    /// can tap Resend four times in ten seconds and trip it — which surfaces as
    /// `AuthError.tooManyRequests` on the one screen they cannot get past.
    @Published private(set) var resendCooldown: Int = 0

    private var resendCooldownTask: Task<Void, Never>?
    private static let resendCooldownSeconds = 60

    /// Starts (or restarts) the countdown. Called after every *attempted* send,
    /// including the automatic one at sign-up.
    private func startResendCooldown() {
        resendCooldownTask?.cancel()
        resendCooldown = Self.resendCooldownSeconds
        // @MainActor is inherited here, so the mutations below stay on main.
        resendCooldownTask = Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                guard let self else { return }
                self.resendCooldown = max(0, self.resendCooldown - 1)
                if self.resendCooldown == 0 { return }
            }
        }
    }

    /// Re-checks verification status after the user taps the link in their inbox.
    func refreshVerificationStatus() async {
        verificationMessage = nil

        // The demo account's waiver is a local string comparison, so it is
        // settled before any network call. The listener normally means App
        // Review never reaches this screen at all; if some ordering quirk puts
        // them here anyway, a reload that fails on a flaky connection must not
        // be what strands them on it.
        if let user = Auth.auth().currentUser, Self.isReviewDemoAccount(user) {
            authState = .authenticated
            return
        }

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

    /// Resends the verification email. No-ops while the cooldown is running.
    func resendVerificationEmail() async {
        guard resendCooldown == 0 else { return }
        verificationMessage = nil
        do {
            try await authService.sendEmailVerification()
            verificationMessage = "Verification email sent."
            startResendCooldown()
        } catch {
            verificationMessage = error.localizedDescription
            // A throttle rejection means the send was refused, not that we may
            // retry at once — back off exactly as we would after a success.
            if case AuthError.tooManyRequests = error { startResendCooldown() }
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
            // linkGuestWithEmail sends a verification email too — same reason.
            startResendCooldown()
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
        // Read the uid first — it is gone by the time the sign-out returns, and
        // the on-device memory digest is keyed by it.
        let uid = Auth.auth().currentUser?.uid
        do {
            try authService.signOut()
            if let uid { MemoryProfileService.shared.clearCache(for: uid) }
            AnalyticsManager.shared.logEvent(.signoutCompleted)
        } catch {
            errorMessage = error.localizedDescription
            AnalyticsManager.shared.trackError(error, context: "signout_failed")
        }
    }

    // MARK: - Delete Account

    @Published var isDeletingAccount = false
    @Published var deleteErrorMessage: String?

    /// Entry point for the Delete-account button.
    ///
    /// Apple accounts detour through a fresh Sign in with Apple, not to prove
    /// who they are — the server needs no reauthentication — but because
    /// Apple's token revocation needs a one-time authorizationCode that only a
    /// new ASAuthorization yields. Everything else deletes on the first tap.
    func beginAccountDeletion() {
        deleteErrorMessage = nil
        if isAppleUser {
            pendingAppleDeletion = true
        } else {
            Task { await deleteAccount() }
        }
    }

    /// Permanently deletes the account and all associated data.
    ///
    /// For Sign in with Apple users, `appleAuthorizationCode` lets Apple revoke
    /// the token (required by App Store guidelines).
    func deleteAccount(appleAuthorizationCode: String? = nil) async {
        isDeletingAccount = true
        deleteErrorMessage = nil
        defer { isDeletingAccount = false }

        let uid = Auth.auth().currentUser?.uid
        do {
            try await authService.deleteAccount(appleAuthorizationCode: appleAuthorizationCode)
            if let uid { MemoryProfileService.shared.clearCache(for: uid) }
            AnalyticsManager.shared.logEvent(.accountDeleted)
            // AuthService signs out on success → listener → .unauthenticated
        } catch {
            deleteErrorMessage = error.localizedDescription
            AnalyticsManager.shared.trackError(error, context: "account_delete_failed")
        }
    }

    /// Returns true if the current user authenticated via Sign in with Apple.
    var isAppleUser: Bool {
        Auth.auth().currentUser?.providerData
            .contains(where: { $0.providerID == "apple.com" }) ?? false
    }

    // MARK: - Apple authorization for account deletion
    //
    // `pendingAppleDeletion` signals the UI to present a Sign in with Apple
    // sheet, whose completion calls `confirmAppleDeletion`. The only thing
    // taken from the result is the one-time authorizationCode.

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
            // The nonce this request was prepared with is spent either way; it
            // must not leak into a later sign-in attempt.
            currentNonce = nil

            let code = (auth.credential as? ASAuthorizationAppleIDCredential)?
                .authorizationCode
                .flatMap { String(data: $0, encoding: .utf8) }

            // A missing code costs only Apple-side revocation — the account
            // still deletes — so this proceeds rather than dead-ending the
            // user on a flow they have now confirmed twice.
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