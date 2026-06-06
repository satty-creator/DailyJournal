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
                    // Gate access behind email verification. Google/federated
                    // accounts return isEmailVerified == true, so they pass straight
                    // through; only unverified email/password accounts are held.
                    self?.authState = user.isEmailVerified ? .authenticated : .unverified
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

        do {
            let user = try await authService.signUp(email: email, password: password, displayName: displayName)
            currentUser = user
            // The auth state listener will move us to .unverified (verification
            // email has been sent by AuthService).
        } catch {
            errorMessage = error.localizedDescription
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

    // MARK: - Sign In
    func signIn(email: String, password: String) async {
        guard validateSignIn(email: email, password: password) else { return }

        isLoading = true
        errorMessage = nil

        do {
            let user = try await authService.signIn(email: email, password: password)
            currentUser = user
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Google Sign In
    func signInWithGoogle() async {
        isLoading = true
        errorMessage = nil

        do {
            let user = try await authService.signInWithGoogle()
            currentUser = user
        } catch {
            errorMessage = error.localizedDescription
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
        } catch {
            errorMessage = error.localizedDescription
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