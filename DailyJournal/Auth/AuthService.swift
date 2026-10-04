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
import FirebaseAppCheck
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
    case tooManyRequests
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidEmail:         return "Please enter a valid email address."
        case .weakPassword:         return "Password must be at least 6 characters."
        case .emailAlreadyInUse:    return "An account with this email already exists."
        case .invalidCredentials:   return "Incorrect email or password."
        case .networkError:         return "Network error. Please try again."
        // Firebase's own copy for this one reads "we have blocked all requests
        // from this device due to unusual activity", which describes a 60-second
        // throttle as if the account were banned. It is the first thing a new
        // user sees if they tap Resend a few times waiting on a slow inbox.
        case .tooManyRequests:      return "Too many attempts — wait a minute and try again."
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
        // UI tests sign in emulator-only accounts; don't mint RevenueCat
        // customers for them in the production project.
        if TestLaunchConfig.isUITest { return }
        _ = try? await Purchases.shared.logIn(uid)
    }

    /// Public entry point for re-identifying RevenueCat outside the sign-in
    /// paths above — used by `AuthViewModel.listenToAuthState()` on session
    /// restore. RevenueCat persists its App User ID across launches on its
    /// own, but iOS Keychain (where Firebase's session lives) outlives app
    /// deletion, so a reinstall can otherwise leave a user signed into
    /// Firebase and permanently anonymous to RevenueCat with no other path
    /// to recover. `logIn` with an already-current id is a cheap no-op, so
    /// calling this on every restore is safe.
    func reidentifyRevenueCat(uid: String) async {
        await identifyRevenueCat(uid: uid)
    }

    // Resets RevenueCat back to a fresh anonymous App User ID. Called on
    // sign-out/delete so the next account on this device (a shared device,
    // most likely) doesn't inherit this user's RevenueCat identity — without
    // this, account B's purchases/webhook events would land on account A's
    // `entitlements/{uid}` and `aiUsage/{uid}` docs until B's own `logIn`
    // fires. Best-effort, same as `identifyRevenueCat` above.
    private func deidentifyRevenueCat() async {
        _ = try? await Purchases.shared.logOut()
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
            try? await sendVerificationLogged(to: result.user, context: "signup")

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
        do {
            try await sendVerificationLogged(to: user, context: "resend")
        } catch let error as AuthError {
            throw error
        } catch let error as NSError {
            throw mapFirebaseError(error)
        }
    }

    /// Sends the verification email and logs the outcome. Failures used to be
    /// swallowed at sign-up, so "no email arrived" left no trace anywhere —
    /// this prints the full Firebase error to the console and records it in
    /// analytics (`app_error`, context `verification_send_<context>`).
    private func sendVerificationLogged(to user: User, context: String) async throws {
        print("AuthService: sending verification email (\(context)) uid=\(user.uid) email=\(user.email ?? "nil") project=\(FirebaseApp.app()?.options.projectID ?? "nil")")
        switch await sendAuthEmailViaServer(kind: "verifyEmail") {
        case .sent:
            print("AuthService: branded verification email sent (\(context)) uid=\(user.uid)")
            await AnalyticsManager.shared.logEvent(.verificationEmailSent, parameters: ["context": context, "via": "server"])
            return
        case .throttled:
            throw AuthError.tooManyRequests
        case .unavailable:
            break
        }
        do {
            try await user.sendEmailVerification(with: Self.verificationLinkSettings)
            print("AuthService: verification email accepted by Firebase (\(context)) uid=\(user.uid)")
            await AnalyticsManager.shared.logEvent(.verificationEmailSent, parameters: ["context": context])
        } catch let error as NSError {
            let name = error.userInfo[AuthErrorUserInfoNameKey] as? String ?? "?"
            let underlying = (error.userInfo[NSUnderlyingErrorKey] as? NSError).map { "\($0.domain)#\($0.code) \($0.userInfo)" } ?? "none"
            print("AuthService: verification email FAILED (\(context)) uid=\(user.uid) code=\(error.code) name=\(name) — \(error.localizedDescription) | underlying: \(underlying)")
            await AnalyticsManager.shared.trackError(error, context: "verification_send_\(context)")
            throw error
        }
    }

    enum ServerEmailResult { case sent, throttled, unavailable }

    /// Sends a branded auth email through the `sendAuthEmail` Cloud Function.
    /// Firebase locks template editing on new projects, so its own emails go
    /// out with a raw URL and a "noreply" sender and land in spam.
    ///
    /// `.unavailable` covers everything short of a definite answer — function
    /// not deployed, SMTP not configured (503), network, 5xx — and callers
    /// then fall back to Firebase's built-in send, so an email always goes out.
    /// `.throttled` is final: falling back would just dodge the rate limit.
    private func sendAuthEmailViaServer(kind: String, email: String? = nil) async -> ServerEmailResult {
        guard let url = URL(string: AIService.sendAuthEmailURLString) else { return .unavailable }
        var body: [String: Any] = ["kind": kind]
        if let email { body["email"] = email }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if kind == "verifyEmail" {
            guard let token = await AIService.shared.idToken() else { return .unavailable }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20

        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return .unavailable }
        switch http.statusCode {
        case 200: return .sent
        case 429: return .throttled
        default:
            print("AuthService: sendAuthEmail(\(kind)) returned \(http.statusCode) — falling back to Firebase")
            return .unavailable
        }
    }

    /// Continue URL for the verification email.
    ///
    /// The template's custom action URL (Firebase Console → Auth → Templates)
    /// is `https://spilr-100f7.web.app/auth/action`. That domain's
    /// apple-app-site-association (served automatically by Firebase Hosting)
    /// claims `/*`, so tapping the link opens the app, which applies the
    /// `oobCode` itself (`AuthViewModel.handleVerificationLink`). Opened in a
    /// browser instead, `public/auth/action.html` applies it and tells the user
    /// to return; the app re-checks on launch and on foreground.
    ///
    /// Without the custom action URL the link falls back to Firebase's own
    /// handler on firebaseapp.com, whose "Continue" button lands on this URL.
    ///
    /// Not `handleCodeInApp` + `linkDomain`: Firebase rejects a default hosting
    /// domain (web.app / firebaseapp.com) as a link domain, and sends nothing.
    /// That needs a custom domain connected to Hosting.
    private static let verificationLinkSettings: ActionCodeSettings = {
        let settings = ActionCodeSettings()
        settings.url = URL(string: "https://\(returnHost)/")
        settings.handleCodeInApp = false
        return settings
    }()

    /// Host of the continue URL above. `onOpenURL` treats any link to it as
    /// "the user may have just verified".
    static let returnHost = "spilr-100f7.web.app"

    /// Pulls a verify-email `oobCode` out of an incoming link. The code may sit
    /// on the URL itself or on the URL nested in its `link` query parameter
    /// (the `/__/auth/links` wrapper), so both are searched.
    static func verificationCode(in url: URL) -> String? {
        var candidates = [url]
        if let nested = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "link" })?.value,
           let nestedURL = URL(string: nested) {
            candidates.append(nestedURL)
        }
        for candidate in candidates {
            let items = URLComponents(url: candidate, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard items.first(where: { $0.name == "mode" })?.value == "verifyEmail" else { continue }
            if let code = items.first(where: { $0.name == "oobCode" })?.value { return code }
        }
        return nil
    }

    /// Applies a verification link opened in the app, then reloads the user so
    /// `isEmailVerified` reflects it. Returns whether the email is now verified.
    func applyVerificationLink(code: String) async throws -> Bool {
        print("AuthService: applying verification link from inbox")
        do {
            try await Auth.auth().applyActionCode(code)
        } catch let error as NSError {
            print("AuthService: applyActionCode FAILED code=\(error.code) — \(error.localizedDescription)")
            await AnalyticsManager.shared.trackError(error, context: "verification_apply_link")
            throw mapFirebaseError(error)
        }
        return try await reloadEmailVerified()
    }

    /// Reloads the current user from the server and returns whether their email
    /// is now verified. Used after the user taps the link in their inbox.
    ///
    /// `user.reload()` only refreshes the `User` object (so `isEmailVerified`
    /// flips here), not the cached ID token JWT — that keeps its stale
    /// `email_verified: false` claim for up to an hour otherwise. Every
    /// server-side check that reads the claim (owner status, AI access) would
    /// see the old value until the token's natural refresh, so force one the
    /// moment verification lands.
    @discardableResult
    func reloadEmailVerified() async throws -> Bool {
        guard let user = Auth.auth().currentUser else { return false }
        do {
            try await user.reload()
        } catch let error as NSError {
            throw mapFirebaseError(error)
        }
        if user.isEmailVerified {
            _ = try? await user.getIDToken(forcingRefresh: true)
        }
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
        try? await sendVerificationLogged(to: result.user, context: "link_guest")
        let user = AppUser(id: result.user.uid, email: email, displayName: trimmedName)
        try await saveUserToFirestore(user)
        // The uid is unchanged by linking (Firebase keeps the anonymous uid),
        // but RevenueCat has no reason to know that — without this call the
        // user stays on RevenueCat's anonymous App User ID indefinitely, the
        // exact app_user_id/uid divergence identifyRevenueCat's doc comment
        // above warns about.
        await identifyRevenueCat(uid: user.id)
        return user
    }

    // MARK: - Password Reset
    func sendPasswordReset(email: String) async throws {
        switch await sendAuthEmailViaServer(kind: "resetPassword", email: email) {
        case .sent:      return
        case .throttled: throw AuthError.tooManyRequests
        case .unavailable: break
        }
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        } catch let error as NSError {
            throw mapFirebaseError(error)
        }
    }

    // MARK: - Sign Out
    func signOut() throws {
        // Drop this device's push token BEFORE signing out — the read needs
        // `Auth.auth().currentUser`, and once signed out there is no uid to key
        // the deletion on. Left undone, the next account on a shared device
        // would keep receiving this user's weekly letter / daily read pushes.
        PushNotificationManager.shared.removeCurrentToken()
        try Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
        // Drop the cache-first hydration flags. They record "we have fetched this
        // query at least once" per user, and leaving them set would let the next
        // account on this device serve an empty cache as a real answer.
        FirestoreCacheFirst.reset()
        // Fire-and-forget: this function is synchronous, and RevenueCat logout
        // must never delay/block the sign-out the user is waiting on.
        Task.detached(priority: .utility) { [weak self] in
            await self?.deidentifyRevenueCat()
        }
    }

    // MARK: - Delete Account
    //
    // Deletion runs server-side, in the `deleteAccount` Cloud Function. The
    // client's only jobs are Apple token revocation, making the authenticated
    // call, and tearing down local state afterwards.
    //
    // It is not done here on the device because a client `user.delete()`
    // throws `requiresRecentLogin` for any sign-in older than a few minutes —
    // which is nearly every session — so the old client-side implementation
    // silently never deleted anything. Forcing the user back through a sign-in
    // sheet would have fixed that, but the Admin SDK has no recency rule at
    // all: the ID token this call carries is proof enough. The function's
    // header comment has the full rationale, including why it also finishes
    // more reliably than a chain of awaited batches on a phone that can be
    // backgrounded mid-erase.
    //
    // For Sign in with Apple users Apple requires token revocation (App Store
    // guideline 5.1.1v). That stays on the client: Firebase already holds the
    // Apple OAuth config for `revokeToken`, whereas revoking from the function
    // would mean provisioning an Apple private key for no behavioural gain.
    // Pass the authorizationCode from a fresh ASAuthorization; pass nil for
    // email/Google/guest accounts.
    func deleteAccount(appleAuthorizationCode: String? = nil) async throws {
        guard Auth.auth().currentUser != nil else {
            throw AuthError.unknown("No signed-in user.")
        }

        // 1. Revoke the Apple OAuth token while the account still exists.
        //    Best-effort — a revoke failure must not leave the user stuck with
        //    an account they have asked twice to delete.
        if let code = appleAuthorizationCode {
            try? await Auth.auth().revokeToken(withAuthorizationCode: code)
        }

        // 2. The server erases Firestore + Storage and deletes the Auth user.
        try await requestServerDeletion()

        // 3. Local teardown. The Auth user is gone, but this client won't
        //    notice until its token next refreshes, so sign out explicitly —
        //    that's what fires the state listener and returns the app to the
        //    signed-out root. The rest mirrors `signOut`; see it for why each
        //    of these outlives the account otherwise.
        try? Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
        FirestoreCacheFirst.reset()

        // 4. Wipe the device-local half of the account — onboarding progress,
        //    AI consent, the goals and tone that shape every prompt. Deliberately
        //    after the sign-out above: clearing `spilr.onboardingCompleted` while
        //    the app still thinks it's authenticated would flash OnboardingView
        //    on the way out. See LocalUserState for what each key leaked.
        await MainActor.run { LocalUserState.clearForDeletedAccount() }

        await deidentifyRevenueCat()
    }

    /// POSTs to the `deleteAccount` Cloud Function with the user's ID token.
    /// Throws unless the server reports the account gone — a silent failure
    /// here would tell the user their data was erased when it wasn't.
    private func requestServerDeletion() async throws {
        guard let token = await AIService.shared.idToken() else {
            throw AuthError.unknown("Couldn't verify your session. Please try again.")
        }

        var request = URLRequest(url: URL(string: AIService.deleteAccountURLString)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let appCheckToken = try? await AppCheck.appCheck().token(forcingRefresh: false) {
            request.setValue(appCheckToken.token, forHTTPHeaderField: "X-Firebase-AppCheck")
        }
        // A long-tenured account is a lot of documents. The function itself is
        // allowed 540s; don't give up on it from this side first.
        request.timeoutInterval = 300

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.networkError
        }
        guard http.statusCode == 200 else {
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let detail = (json ?? nil)?["error"] as? String
            throw AuthError.unknown(detail ?? "Couldn't delete your account. Please try again.")
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
        // `invalidCredential` is what a wrong password comes back as once email
        // enumeration protection is on (the default for new projects) — without
        // it the reauthentication sheet shows Firebase's raw "supplied auth
        // credential is malformed or has expired" for a simple typo.
        case AuthErrorCode.wrongPassword.rawValue,
             AuthErrorCode.invalidCredential.rawValue,
             AuthErrorCode.userNotFound.rawValue:           return .invalidCredentials
        case AuthErrorCode.networkError.rawValue:           return .networkError
        case AuthErrorCode.tooManyRequests.rawValue:        return .tooManyRequests
        default:                                            return .unknown(error.localizedDescription)
        }
    }
}