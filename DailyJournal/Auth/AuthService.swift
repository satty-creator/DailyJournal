//
//  AuthService.swift
//  DailyJournal
//
//  Created on 2026-05-25.
//

import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn
import CryptoKit

struct AppUser: Identifiable, Codable {
    let id: String
    let email: String
    var displayName: String?
    var profileImageURL: String?
    let createdAt: Date
    var lastActiveAt: Date

    init(id: String, email: String, displayName: String? = nil) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.createdAt = Date()
        self.lastActiveAt = Date()
    }
}

enum AuthError: LocalizedError {
    case invalidEmail
    case weakPassword
    case emailAlreadyInUse
    case invalidCredentials
    case networkError
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidEmail:         return "Please enter a valid email address."
        case .weakPassword:         return "Password must be at least 6 characters."
        case .emailAlreadyInUse:    return "An account with this email already exists."
        case .invalidCredentials:   return "Incorrect email or password."
        case .networkError:         return "Network error. Please try again."
        case .unknown(let msg):     return msg
        }
    }
}

final class AuthService {

    private let db = Firestore.firestore()

    // MARK: - Email/Password Sign Up
    func signUp(email: String, password: String, displayName: String? = nil) async throws -> AppUser {
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)

            // If the user provided a display name, set it on the Firebase Auth
            // profile so it's available everywhere `user.displayName` is read.
            let trimmedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmedName, !trimmedName.isEmpty {
                let changeRequest = result.user.createProfileChangeRequest()
                changeRequest.displayName = trimmedName
                try? await changeRequest.commitChanges()
            }

            // Send the verification email. We don't fail signup if this throws —
            // the user can resend from the verification screen.
            try? await result.user.sendEmailVerification()

            let resolvedName = (trimmedName?.isEmpty == false) ? trimmedName : nil
            let user = AppUser(id: result.user.uid, email: email, displayName: resolvedName)
            try await saveUserToFirestore(user)
            return user
        } catch let error as NSError {
            throw mapFirebaseError(error)
        }
    }

    // MARK: - Email verification helpers
    /// Resends the verification email to the currently signed-in user.
    func sendEmailVerification() async throws {
        guard let user = Auth.auth().currentUser else {
            throw AuthError.unknown("No signed-in user to verify.")
        }
        try await user.sendEmailVerification()
    }

    /// Reloads the current user from the server and returns whether their email
    /// is now verified. Used after the user taps the link in their inbox.
    @discardableResult
    func reloadEmailVerified() async throws -> Bool {
        guard let user = Auth.auth().currentUser else { return false }
        try await user.reload()
        return user.isEmailVerified
    }

    // MARK: - Email/Password Sign In
    func signIn(email: String, password: String) async throws -> AppUser {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            return try await fetchUserFromFirestore(userId: result.user.uid)
        } catch let error as NSError {
            throw mapFirebaseError(error)
        }
    }

    // MARK: - Google Sign In
    func signInWithGoogle() async throws -> AppUser {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthError.unknown("Firebase configuration error.")
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        guard let windowScene = await UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = await windowScene.windows.first?.rootViewController else {
            throw AuthError.unknown("Unable to find root view controller.")
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)

        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.unknown("Google authentication failed.")
        }

        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )

        let authResult = try await Auth.auth().signIn(with: credential)

        // Check if user already exists or create new
        if let existingUser = try? await fetchUserFromFirestore(userId: authResult.user.uid) {
            return existingUser
        } else {
            let newUser = AppUser(
                id: authResult.user.uid,
                email: authResult.user.email ?? "",
                displayName: authResult.user.displayName
            )
            try await saveUserToFirestore(newUser)
            return newUser
        }
    }

    // MARK: - Sign in with Apple
    //
    // The UI (SignInWithAppleButton) generates a raw nonce, hashes it into the
    // ASAuthorization request, and on completion hands the Apple ID token + the
    // *raw* nonce here. We exchange them for a Firebase credential. Apple only
    // returns the user's name on the very first authorization, so we opportun-
    // istically persist it when present.
    func signInWithApple(
        idToken: String,
        rawNonce: String,
        fullName: PersonNameComponents?
    ) async throws -> AppUser {
        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: rawNonce,
            fullName: fullName
        )

        let authResult = try await Auth.auth().signIn(with: credential)

        // Resolve a display name: Firebase value first, then Apple's one-time name.
        let appleName = [fullName?.givenName, fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let resolvedName = authResult.user.displayName
            ?? (appleName.isEmpty ? nil : appleName)

        // If Firebase doesn't have a name yet but Apple gave us one, set it.
        if (authResult.user.displayName ?? "").isEmpty, !appleName.isEmpty {
            let change = authResult.user.createProfileChangeRequest()
            change.displayName = appleName
            try? await change.commitChanges()
        }

        if let existing = try? await fetchUserFromFirestore(userId: authResult.user.uid) {
            return existing
        }
        let newUser = AppUser(
            id: authResult.user.uid,
            email: authResult.user.email ?? "",
            displayName: resolvedName
        )
        try await saveUserToFirestore(newUser)
        return newUser
    }

    // MARK: - Apple nonce helpers (Firebase-recommended)

    /// A cryptographically secure random string used as the Apple nonce.
    static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if status != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with \(status)")
                }
                return random
            }
            randoms.forEach { random in
                if remaining == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    /// SHA256 of the raw nonce — this is what goes into the ASAuthorization request.
    static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Update Display Name
    func updateDisplayName(_ name: String) async throws {
        // Firebase Auth profile update requires a network round-trip; that's fine
        // since this runs in a background Task started by the ViewModel.
        if let firebaseUser = Auth.auth().currentUser {
            let changeRequest = firebaseUser.createProfileChangeRequest()
            changeRequest.displayName = name
            try await changeRequest.commitChanges()
        }
        // Firestore user document — fire-and-forget (completion: nil forces the void
        // overload so Swift doesn't pick the async throws version).
        if let userId = Auth.auth().currentUser?.uid {
            db.collection("users").document(userId).updateData(["displayName": name], completion: nil)
        }
    }

    // MARK: - Sign Out
    func signOut() throws {
        try Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
    }

    // MARK: - Private Helpers
    private func saveUserToFirestore(_ user: AppUser) async throws {
        let data: [String: Any] = [
            "id": user.id,
            "email": user.email,
            "displayName": user.displayName ?? "",
            "createdAt": Timestamp(date: user.createdAt),
            "lastActiveAt": Timestamp(date: user.lastActiveAt)
        ]
        try await db.collection("users").document(user.id).setData(data)
    }

    private func fetchUserFromFirestore(userId: String) async throws -> AppUser {
        let doc = try await db.collection("users").document(userId).getDocument()
        guard let data = doc.data() else { throw AuthError.unknown("User not found.") }

        return AppUser(
            id: data["id"] as? String ?? userId,
            email: data["email"] as? String ?? "",
            displayName: data["displayName"] as? String
        )
    }

    private func mapFirebaseError(_ error: NSError) -> AuthError {
        switch error.code {
        case AuthErrorCode.invalidEmail.rawValue:           return .invalidEmail
        case AuthErrorCode.weakPassword.rawValue:           return .weakPassword
        case AuthErrorCode.emailAlreadyInUse.rawValue:      return .emailAlreadyInUse
        case AuthErrorCode.wrongPassword.rawValue,
             AuthErrorCode.userNotFound.rawValue:           return .invalidCredentials
        case AuthErrorCode.networkError.rawValue:           return .networkError
        default:                                            return .unknown(error.localizedDescription)
        }
    }
}