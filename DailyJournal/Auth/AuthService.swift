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
import FirebaseStorage
import GoogleSignIn
import CryptoKit
import RevenueCat

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

    // MARK: - RevenueCat identification
    //
    // Called at every sign-in/sign-up return point below. RevenueCat is
    // configured anonymously at launch (DailyJournalApp.swift) — this is what
    // attaches the Firebase uid, which matters because `revenueCatWebhook`
    // (functions/index.js) writes entitlement events keyed on RevenueCat's
    // App User ID. If that id is ever something other than this uid, the
    // webhook's writes land on the wrong `aiUsage`/`entitlements` doc and
    // geminiProxy never sees the entitlement — silently, since a missing
    // entitlement just falls back to local AI like any other budget miss.
    //
    // Best-effort: a failure here must never block sign-in. Worst case, the
    // user stays anonymous to RevenueCat until the next successful call.
    private func identifyRevenueCat(uid: String) async {
        _ = try? await Purchases.shared.logIn(uid)
    }

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
            await identifyRevenueCat(uid: user.id)
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
            let user = try await fetchUserFromFirestore(userId: result.user.uid)
            await identifyRevenueCat(uid: user.id)
            return user
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
            await identifyRevenueCat(uid: existingUser.id)
            return existingUser
        } else {
            let newUser = AppUser(
                id: authResult.user.uid,
                email: authResult.user.email ?? "",
                displayName: authResult.user.displayName
            )
            try await saveUserToFirestore(newUser)
            await identifyRevenueCat(uid: newUser.id)
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
            await identifyRevenueCat(uid: existing.id)
            return existing
        }
        let newUser = AppUser(
            id: authResult.user.uid,
            email: authResult.user.email ?? "",
            displayName: resolvedName
        )
        try await saveUserToFirestore(newUser)
        await identifyRevenueCat(uid: newUser.id)
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

    // MARK: - Anonymous / Guest Sign In
    //
    // Satisfies App Store Guideline 5.1.1(v): apps may not require account
    // creation to access features that aren't account-based. Anonymous Firebase
    // Auth gives the guest a real UID so all services (Firestore, AI proxy)
    // work identically — the user just hasn't set a password or email yet.
    // The anonymous account can be upgraded to a permanent one later via
    // AuthViewModel.linkGuestAccount(…).
    func signInAnonymously() async throws -> AppUser {
        let result = try await Auth.auth().signInAnonymously()
        return AppUser(id: result.user.uid, email: "", displayName: nil)
    }

    // MARK: - Upgrade guest → permanent account (link credentials)
    func linkGuestWithEmail(email: String, password: String, displayName: String?) async throws -> AppUser {
        guard let current = Auth.auth().currentUser, current.isAnonymous else {
            // Not a guest; fall through to normal sign-up.
            return try await signUp(email: email, password: password, displayName: displayName)
        }
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        let result = try await current.link(with: credential)

        let trimmedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name = trimmedName, !name.isEmpty {
            let req = result.user.createProfileChangeRequest()
            req.displayName = name
            try? await req.commitChanges()
        }
        try? await result.user.sendEmailVerification()
        let user = AppUser(id: result.user.uid, email: email, displayName: trimmedName)
        try await saveUserToFirestore(user)
        return user
    }

    // MARK: - Password Reset
    func sendPasswordReset(email: String) async throws {
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        } catch let error as NSError {
            throw mapFirebaseError(error)
        }
    }

    // MARK: - Sign Out
    func signOut() throws {
        try Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
        // Drop the cache-first hydration flags. They record "we have fetched this
        // query at least once" per user, and leaving them set would let the next
        // account on this device serve an empty cache as a real answer.
        FirestoreCacheFirst.reset()
    }

    // MARK: - Delete Account
    //
    // Permanently erases all user data from Firestore, revokes the Apple
    // OAuth token if applicable, then deletes the Firebase Auth user.
    //
    // Firebase requires a recent sign-in before `user.delete()` succeeds.
    // If the token is stale the call throws `requiresRecentLogin` — callers
    // should surface "please sign out and back in, then try again."
    //
    // For Sign in with Apple users Apple also requires token revocation
    // (App Store guideline 5.1.1v). Pass the authorizationCode from a fresh
    // ASAuthorization when available; pass nil for email/Google accounts.
    func deleteAccount(appleAuthorizationCode: String? = nil) async throws {
        guard let user = Auth.auth().currentUser else {
            throw AuthError.unknown("No signed-in user.")
        }
        let uid = user.uid

        // 1. Delete all Firestore data under users/{uid}.
        //    Each subcollection is fetched and batch-deleted. Fire-and-forget
        //    semantics apply — if a partial delete occurs the Auth user is
        //    still removed and orphaned documents become inaccessible.
        await eraseFirestoreData(for: uid)

        // 2. Revoke the Apple OAuth token so Apple removes app authorisation
        //    from the user's Apple ID settings (required by Apple).
        if let code = appleAuthorizationCode {
            try? await Auth.auth().revokeToken(withAuthorizationCode: code)
        }

        // 3. Delete the Firebase Auth account. Throws requiresRecentLogin if
        //    the session is older than ~5 minutes.
        try await user.delete()
    }

    // Deletes every document in every known subcollection plus the user
    // root document. Uses WriteBatches (max 500 ops each) to stay within
    // Firestore limits.
    //
    // The collection list lives in `FirestoreSchema.userSubcollections` — do NOT
    // inline it here again. A previous hand-maintained copy drifted from the names
    // the services actually write ("reads" vs `dailyReads`, "moods" vs `moodLogs`)
    // and omitted `riverMarks` and `pushTokens` entirely, so four collections
    // survived account deletion. One list, one place.
    private func eraseFirestoreData(for uid: String) async {
        let userRef = db.collection(FirestoreSchema.users).document(uid)

        for name in FirestoreSchema.userSubcollections {
            await deleteCollection(userRef.collection(name))
        }

        // Finally, delete the root user document.
        try? await userRef.delete()

        // Delete Firebase Storage photos (users/{uid}/entryPhotos/).
        // Storage has no batch-delete API; we list and delete individually.
        await eraseStorageFolder(path: FirestoreSchema.entryPhotosPath(for: uid))
    }

    /// Lists and deletes all items under a Storage folder path.
    private func eraseStorageFolder(path: String) async {
        let ref = Storage.storage().reference().child(path)
        guard let result = try? await ref.listAll() else { return }
        for item in result.items {
            try? await item.delete()
        }
        // Recurse into any sub-prefixes (e.g. nested folders).
        for prefix in result.prefixes {
            await eraseStorageFolder(path: prefix.fullPath)
        }
    }

    /// Deletes all documents in `collection` in batches of 400.
    private func deleteCollection(_ collection: CollectionReference) async {
        guard let snapshot = try? await collection.getDocuments() else { return }
        let docs = snapshot.documents
        guard !docs.isEmpty else { return }

        // Firestore batch limit is 500 writes; use 400 for safety headroom.
        let batchSize = 400
        var offset = 0
        while offset < docs.count {
            let batch = db.batch()
            let slice = docs[offset ..< min(offset + batchSize, docs.count)]
            slice.forEach { batch.deleteDocument($0.reference) }
            try? await batch.commit()
            offset += batchSize
        }
    }

    // MARK: - Private Helpers
    private func saveUserToFirestore(_ user: AppUser) async throws {
        let data: [String: Any] = [
            "id": user.id,
            "email": user.email,
            "displayName": user.displayName ?? "",
            "createdAt": Timestamp(date: user.createdAt),
            "lastActiveAt": Timestamp(date: user.lastActiveAt),
            // IANA timezone (e.g. "America/Los_Angeles"). Refreshed on every
            // sign-in so a user who travels always has the current one stored.
            "timezone": TimeZone.current.identifier
        ]
        // merge:true so we never clobber fields written elsewhere.
        try await db.collection("users").document(user.id).setData(data, merge: true)
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