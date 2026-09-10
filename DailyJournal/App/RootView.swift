//
//  RootView.swift
//  DailyJournal
//

import SwiftUI
import AuthenticationServices

// MARK: - Root
struct RootView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var themeManager: ThemeManager

    /// Tracks whether the user has completed onboarding. Starts false for new
    /// accounts; becomes true when OnboardingView calls its completion closure.
    @AppStorage(UserDefaults.onboardingCompletedKey) private var onboardingCompleted = false

    /// True when the returning-user AI consent sheet should be shown.
    /// Fires once for users who completed onboarding before the consent screen
    /// was added (aiConsentGranted key is absent in their UserDefaults).
    @State private var showRetroConsentSheet = false

    var body: some View {
        Group {
            switch authViewModel.authState {
            case .loading:
                SplashView()
            case .authenticated:
                // Show onboarding for brand-new users; skip straight to the app
                // for returning users who already completed it.
                if onboardingCompleted {
                    MainTabView()
                        .sheet(isPresented: $showRetroConsentSheet) {
                            RetroAIConsentSheet(isPresented: $showRetroConsentSheet)
                        }
                        .onAppear {
                            // Show once for users who never saw the consent screen.
                            if UserDefaults.standard.aiConsentGranted == nil {
                                showRetroConsentSheet = true
                            }
                        }
                } else {
                    OnboardingView {
                        // Completion handler — @AppStorage updates automatically,
                        // the body re-runs and switches to MainTabView.
                    }
                    .environmentObject(themeManager)
                }
            case .unverified:
                VerificationView()
            case .unauthenticated:
                AuthContainerView()
            }
        }
        .animation(.easeInOut(duration: 0.4), value: authViewModel.authState)
        .animation(.easeInOut(duration: 0.4), value: onboardingCompleted)
        // Re-identify the whole tree when the theme changes so every screen that
        // reads `AppTheme.*` rebuilds with the new palette. `AppTheme.active` is
        // already updated by ThemeManager before this runs.
        .id(themeManager.themeID)
        // Each palette declares whether it is a light or dark UI. Most palettes
        // are light; Moon is dark. Driving this from the palette (instead of the
        // old hard `.light` pin) keeps system label/control colours legible
        // against the selected surfaces.
        .preferredColorScheme(themeManager.colorScheme)
        .animation(.easeInOut(duration: 0.45), value: themeManager.themeID)
    }
}

// MARK: - Retro consent sheet (returning users)

struct RetroAIConsentSheet: View {
    @Binding var isPresented: Bool
    @State private var showDetails = false

    var body: some View {
        ZStack {
            AppTheme.paper.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI Insights\nConsent.")
                            .font(AppTheme.editorialDisplay(size: 30))
                            .foregroundStyle(AppTheme.ink)
                            .padding(.top, 8)
                    }

                    // Consent card — same design as onboarding step
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Spilr uses advanced AI models to analyze your mood patterns and give you personalized reflections. To do this, your text is securely processed by our third-party AI partners.")
                            .font(AppTheme.editorialBody(size: 15))
                            .foregroundStyle(AppTheme.inkSoft)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) { showDetails.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Text("View AI Partners & Data Details")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(AppTheme.terracotta)
                                Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AppTheme.terracotta)
                            }
                        }
                        .buttonStyle(.plain)

                        if showDetails {
                            VStack(alignment: .leading, spacing: 12) {
                                detailRow(label: "AI provider",         value: "Google Gemini (via Firebase)")
                                detailRow(label: "Data sent",           value: "Your journal entry text")
                                detailRow(label: "Purpose",             value: "Reflections, patterns, emotional summaries")
                                detailRow(label: "Stored server-side?", value: "No — only structured results are saved")
                                detailRow(label: "Used to train models?", value: "No")
                            }
                            .padding(14)
                            .background(AppTheme.cream)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(18)
                    .background(AppTheme.cream.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    Text("You can change this at any time in Profile → AI & Privacy.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkSoft)

                    VStack(spacing: 12) {
                        Button {
                            UserDefaults.standard.aiConsentGranted = true
                            AnalyticsManager.shared.trackAIConsentGranted()
                            isPresented = false
                        } label: {
                            Text("Agree & Enable AI Features")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(AppTheme.cream)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 17)
                                .background(LinearGradient(colors: [AppTheme.terracotta, AppTheme.terracottaDeep],
                                                           startPoint: .leading, endPoint: .trailing))
                                .clipShape(Capsule())
                                .shadow(color: AppTheme.terracotta.opacity(0.35), radius: 14, x: 0, y: 7)
                        }
                        .buttonStyle(.plain)

                        Button {
                            UserDefaults.standard.aiConsentGranted = false
                            AnalyticsManager.shared.trackAIConsentDenied()
                            isPresented = false
                        } label: {
                            Text("Use local insights only")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppTheme.inkSoft)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppTheme.cream.opacity(0.8))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(AppTheme.inkSoft.opacity(0.2), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(AppTheme.mono(size: 9))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(1.5)
            Text(value)
                .font(AppTheme.editorialBody(size: 13))
                .foregroundStyle(AppTheme.ink)
        }
    }
}

// MARK: - Splash
struct SplashView: View {
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            AppTheme.paper.ignoresSafeArea()

            VStack(spacing: 12) {
                Text("spilr.")
                    .font(AppTheme.editorialDisplay(size: 52))
                    .foregroundStyle(AppTheme.ink)
                    .italic()

                ProgressView()
                    .tint(AppTheme.terracotta)
                    .scaleEffect(0.8)
            }
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeIn(duration: 0.5)) { opacity = 1 }
            }
        }
    }
}

// MARK: - Main tab view (Today · Journal · Mirror)
struct MainTabView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

    @StateObject private var mirrorVM: MirrorViewModel

    /// Owns tab selection so one tab can send the user to another. Created here
    /// (the only place that hosts the TabView) and injected into the whole tree.
    @StateObject private var router = AppRouter()

    init() {
        _mirrorVM = StateObject(wrappedValue: MirrorViewModel(userId: ""))
    }

    var body: some View {
        let uid = authViewModel.currentUser?.id ?? ""
        TabView(selection: $router.selectedTab) {
            HomeView(userId: uid, mirrorVM: mirrorVM)
                .tag(AppTab.today)
                .tabItem {
                    Label("Today", systemImage: "sun.horizon")
                }

            JournalListView(userId: uid)
                .tag(AppTab.journal)
                .tabItem {
                    Label("Journal", systemImage: "book")
                }

            MirrorView(userId: uid, viewModel: mirrorVM)
                .tag(AppTab.mirror)
                .tabItem {
                    Label("Mirror", systemImage: "sparkles")
                }
        }
        .environmentObject(router)
        .tint(AppTheme.terracotta)
        // `.task(id: uid)` — not a bare `.task` — so this re-fires if `uid`
        // changes after the tab first appears (e.g. auth resolves a beat
        // after MainTabView does), instead of only ever running once against
        // whatever `uid` happened to be at that moment.
        .task(id: uid) {
            guard !uid.isEmpty else { return }
            mirrorVM.setUserId(uid)
            await mirrorVM.load(showSpinner: false)
        }
    }
}

// MARK: - Profile view
struct ProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var entitlements = EntitlementService.shared
    @State private var isEditing = false
    @State private var editedName = ""
    @State private var showDeleteConfirmation = false
    @State private var showGuestUpgrade = false
    @State private var showPaywall = false
    #if DEBUG
    @State private var debugTokenStatus: String? = nil
    #endif

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.paper.ignoresSafeArea()
                List {
                    // MARK: Guest upgrade banner
                    if authViewModel.isGuest {
                        Section {
                            Button {
                                showGuestUpgrade = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "icloud.and.arrow.up")
                                        .font(.system(size: 18))
                                        .foregroundStyle(AppTheme.terracotta)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Save your journal")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(AppTheme.ink)
                                        Text("Create a free account to back up your entries.")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.inkSoft)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.inkSoft)
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(AppTheme.terracotta.opacity(0.08))
                        }
                    }

                    // MARK: Spilr Pro
                    if !authViewModel.isGuest {
                        Section {
                            if entitlements.isPro {
                                HStack(spacing: 12) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(AppTheme.terracotta)
                                    Text("You're on Spilr Pro")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(AppTheme.ink)
                                }
                                .padding(.vertical, 4)
                                .listRowBackground(AppTheme.cream)
                            } else {
                                Button {
                                    showPaywall = true
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 18))
                                            .foregroundStyle(AppTheme.terracotta)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Get Spilr Pro")
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(AppTheme.ink)
                                            Text("Unlimited AI, deeper patterns.")
                                                .font(.caption)
                                                .foregroundStyle(AppTheme.inkSoft)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.inkSoft)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .listRowBackground(AppTheme.cream)
                            }
                        }
                    }

                    // MARK: Account section
                    Section {
                        if let user = authViewModel.currentUser {
                            if isEditing {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("DISPLAY NAME")
                                        .font(AppTheme.mono(size: 10))
                                        .foregroundStyle(AppTheme.inkSoft)
                                        .tracking(2)
                                    TextField("Your name", text: $editedName)
                                        .font(AppTheme.editorialDisplay(size: 20))
                                        .foregroundStyle(AppTheme.ink)
                                        .autocorrectionDisabled()
                                    Text(user.email)
                                        .font(AppTheme.mono(size: 12))
                                        .foregroundStyle(AppTheme.inkSoft)
                                        .tracking(0.3)
                                }
                                .padding(.vertical, 10)
                                .listRowBackground(AppTheme.cream)
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(user.displayName ?? user.email)
                                        .font(AppTheme.editorialDisplay(size: 22))
                                        .foregroundStyle(AppTheme.ink)
                                    Text(user.email)
                                        .font(AppTheme.mono(size: 12))
                                        .foregroundStyle(AppTheme.inkSoft)
                                        .tracking(0.3)
                                }
                                .padding(.vertical, 10)
                                .listRowBackground(AppTheme.cream)
                            }
                        }
                    }

                    // MARK: AI & Privacy
                    Section {
                        Toggle(isOn: Binding(
                            get: { UserDefaults.standard.aiConsentGranted ?? false },
                            set: {
                                UserDefaults.standard.aiConsentGranted = $0
                                AnalyticsManager.shared.logEvent(.aiConsentToggled, parameters: ["granted": $0])
                            }
                        )) {
                            Label("AI Insights", systemImage: "sparkles")
                                .font(.system(size: 15))
                        }
                        .tint(AppTheme.terracotta)
                        .listRowBackground(AppTheme.cream)
                    } header: {
                        Text("AI & Privacy")
                            .foregroundStyle(AppTheme.inkSoft)
                    } footer: {
                        // The second sentence used to read "Your text is never stored
                        // server-side or used to train models." The training half is
                        // true; the storage half is not — JournalService writes the
                        // full plaintext `content` to users/{uid}/entries. Corrected
                        // so this doesn't contradict the Privacy Policy two rows down.
                        Text("When enabled, your entry text is sent to Google Gemini to generate reflections and patterns. Google doesn't use it to train their models. Your entries are saved to your account either way — see Privacy Policy.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.inkSoft)
                    }

                    // MARK: Appearance
                    Section {
                        NavigationLink {
                            ThemePickerView()
                                .environmentObject(ThemeManager.shared)
                        } label: {
                            HStack {
                                Label("Theme", systemImage: "paintpalette")
                                    .font(.system(size: 15))
                                Spacer()
                                Text(ThemeManager.shared.themeID.title)
                                    .font(AppTheme.mono(size: 12))
                                    .foregroundStyle(AppTheme.inkSoft)
                            }
                        }
                        .listRowBackground(AppTheme.cream)
                    } header: {
                        Text("Appearance")
                            .foregroundStyle(AppTheme.inkSoft)
                    }

                    // MARK: Feedback & support
                    Section {
                        Button {
                            AnalyticsManager.shared.logEvent(.feedbackSent)
                            if let url = URL(string: "mailto:support@spilr.app?subject=Spilr%20Feedback") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Send feedback", systemImage: "envelope")
                                .font(.system(size: 15))
                                .foregroundStyle(AppTheme.ink)
                        }
                        .listRowBackground(AppTheme.cream)

                        // Was a mailto: asking support to send a policy, which is not
                        // a privacy policy and fails App Store Review 5.1.1(i).
                        // App Store Connect still needs a public URL separately —
                        // publish PRIVACY_POLICY.md and paste that link there.
                        NavigationLink {
                            PrivacyPolicyView()
                        } label: {
                            Label("Privacy Policy", systemImage: "hand.raised")
                                .font(.system(size: 15))
                                .foregroundStyle(AppTheme.ink)
                        }
                        .listRowBackground(AppTheme.cream)
                    } header: {
                        Text("Feedback")
                            .foregroundStyle(AppTheme.inkSoft)
                    }

                    #if DEBUG
                    // MARK: Dev tools — Mirror v3 manual testing
                    //
                    // `runNightlyForUser` (functions/index.js) needs a real Firebase
                    // ID token in its Authorization header, same contract as
                    // geminiProxy. There's no UI anywhere else to get one, and it's
                    // the only way to trigger the nightly pipeline without waiting
                    // for 04:00 UTC — see MIRROR_V3_TEST_CASES.md §3.
                    Section {
                        Button {
                            Task { await copyDebugIDToken() }
                        } label: {
                            Label(debugTokenStatus ?? "Copy ID token for testing",
                                  systemImage: "key")
                                .font(.system(size: 15))
                        }
                        .listRowBackground(AppTheme.cream)
                    } header: {
                        Text("Debug")
                            .foregroundStyle(AppTheme.inkSoft)
                    } footer: {
                        Text("Paste this as the Bearer token when calling runNightlyForUser. Expires in about an hour — copy a fresh one if a call starts returning 401.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                    #endif

                    // MARK: Sign out / Delete account
                    Section {
                        Button(role: .destructive) {
                            authViewModel.signOut()
                        } label: {
                            Label("Sign out", systemImage: "arrow.right.square")
                                .font(.system(size: 15))
                        }
                        .listRowBackground(AppTheme.cream)

                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            if authViewModel.isDeletingAccount {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .tint(.red)
                                        .scaleEffect(0.8)
                                    Text("Deleting account…")
                                        .font(.system(size: 15))
                                }
                            } else {
                                Label("Delete account", systemImage: "trash")
                                    .font(.system(size: 15))
                            }
                        }
                        .disabled(authViewModel.isDeletingAccount)
                        .listRowBackground(AppTheme.cream)
                    }

                    // Error banner for deletion failures
                    if let deleteError = authViewModel.deleteErrorMessage {
                        Section {
                            Text(deleteError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .listRowBackground(AppTheme.cream)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isEditing {
                        Button("Save") {
                            let name = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty else { isEditing = false; return }
                            authViewModel.updateDisplayName(name)
                            isEditing = false
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.terracotta)
                    } else {
                        Button("Edit") {
                            editedName = authViewModel.currentUser?.displayName ?? ""
                            isEditing = true
                        }
                        .foregroundStyle(AppTheme.terracotta)
                    }
                }
                if isEditing {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { isEditing = false }
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                }
            }
            // MARK: Guest upgrade sheet
            .sheet(isPresented: $showGuestUpgrade) {
                GuestUpgradeView()
                    .environmentObject(authViewModel)
            }
            // MARK: Spilr Pro paywall
            .sheet(isPresented: $showPaywall) {
                SpilrPaywallView()
            }
            .task {
                await entitlements.refresh()
                AnalyticsManager.shared.logEvent(.settingsOpened)
            }

            // MARK: Delete-account confirmation
            .confirmationDialog(
                "Delete your account?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) {
                    if authViewModel.isAppleUser {
                        // Apple users need a fresh authorization to obtain the
                        // one-time authorizationCode for token revocation.
                        authViewModel.requestAppleDeletion()
                    } else {
                        Task { await authViewModel.deleteAccount() }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete your account and all journal data. This cannot be undone.")
            }
            // Fresh Apple sign-in sheet for token revocation (Apple users only)
            .signInWithAppleDeleteSheet(authViewModel: authViewModel)
        }
    }

    #if DEBUG
    /// Copies a fresh Firebase ID token to the clipboard for manually calling
    /// `runNightlyForUser` (see MIRROR_V3_TEST_CASES.md §3) — the only way to
    /// exercise the nightly pipeline without waiting for the 04:00 UTC cron,
    /// since the Firebase emulator doesn't implement task queues.
    ///
    /// Reuses `AIService.idToken()` — same fetch, same 10s timeout, same
    /// contract geminiProxy already expects — rather than duplicating it here.
    /// Works no matter how you signed in (email, Google, Apple): Firebase
    /// issues the same kind of ID token regardless of provider.
    private func copyDebugIDToken() async {
        guard let token = await AIService.shared.idToken() else {
            debugTokenStatus = "No signed-in user — sign in first"
            return
        }
        UIPasteboard.general.string = token
        debugTokenStatus = "Copied ✓ (paste within ~1 hour)"
    }
    #endif
}

// MARK: - SignInWithApple sheet for account deletion (Apple users)

private extension View {
    func signInWithAppleDeleteSheet(authViewModel: AuthViewModel) -> some View {
        self.modifier(AppleDeletionSheetModifier(authViewModel: authViewModel))
    }
}

private struct AppleDeletionSheetModifier: ViewModifier {
    @ObservedObject var authViewModel: AuthViewModel

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $authViewModel.pendingAppleDeletion) {
                AppleDeletionAuthView(authViewModel: authViewModel)
                    .presentationDetents([.medium])
            }
    }
}

/// Small sheet that triggers a Sign in with Apple flow purely to obtain the
/// `authorizationCode` needed for token revocation before account deletion.
private struct AppleDeletionAuthView: View {
    @ObservedObject var authViewModel: AuthViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "trash.circle")
                .font(.system(size: 52))
                .foregroundStyle(.red)

            VStack(spacing: 8) {
                Text("Confirm with Apple")
                    .font(.title3.bold())
                Text("Sign in with Apple once more so we can securely revoke access before deleting your account.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            SignInWithAppleButton(.continue) { request in
                authViewModel.prepareAppleRequest(request)
            } onCompletion: { result in
                Task { await authViewModel.confirmAppleDeletion(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 54)
            .cornerRadius(14)
            .padding(.horizontal, 32)

            Button("Cancel") { authViewModel.pendingAppleDeletion = false }
                .foregroundStyle(.secondary)
                .font(.subheadline)

            Spacer()
        }
        .padding()
    }
}

// MARK: - Guest upgrade sheet

struct GuestUpgradeView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var displayName = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @FocusState private var focused: Field?

    enum Field { case email, name, password, confirm }

    private var passwordsMatch: Bool { password == confirmPassword || confirmPassword.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.paper.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 28) {
                        VStack(spacing: 8) {
                            Image(systemName: "icloud.and.arrow.up")
                                .font(.system(size: 44))
                                .foregroundStyle(AppTheme.terracotta)
                            Text("Save your journal")
                                .font(AppTheme.editorialDisplay(size: 28))
                                .foregroundStyle(AppTheme.ink)
                            Text("Create a free account. Your existing entries are kept.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.inkSoft)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)

                        VStack(spacing: 14) {
                            CustomTextField(placeholder: "Email", text: $email,
                                            keyboardType: .emailAddress, systemImage: "envelope")
                                .focused($focused, equals: .email)
                                .submitLabel(.next)
                                .onSubmit { focused = .name }

                            CustomTextField(placeholder: "Display name (optional)", text: $displayName,
                                            systemImage: "person")
                                .focused($focused, equals: .name)
                                .submitLabel(.next)
                                .onSubmit { focused = .password }

                            CustomTextField(placeholder: "Password", text: $password,
                                            isSecure: true, systemImage: "lock")
                                .focused($focused, equals: .password)
                                .submitLabel(.next)
                                .onSubmit { focused = .confirm }

                            VStack(alignment: .leading, spacing: 4) {
                                CustomTextField(placeholder: "Confirm password", text: $confirmPassword,
                                                isSecure: true, systemImage: "lock.fill")
                                    .focused($focused, equals: .confirm)
                                    .submitLabel(.done)
                                if !passwordsMatch {
                                    Text("Passwords do not match")
                                        .font(.caption).foregroundStyle(.red).padding(.leading, 4)
                                }
                            }
                        }

                        if let err = authViewModel.upgradeErrorMessage {
                            ErrorBanner(message: err)
                        }

                        PrimaryButton(title: "Create account",
                                      isLoading: authViewModel.isUpgrading,
                                      isDisabled: !passwordsMatch) {
                            Task {
                                await authViewModel.upgradeGuestAccount(
                                    email: email, password: password,
                                    displayName: displayName.isEmpty ? nil : displayName
                                )
                                if authViewModel.upgradeErrorMessage == nil { dismiss() }
                            }
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 24)
                }
            }
            .navigationTitle("Create account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                        .foregroundStyle(AppTheme.inkSoft)
                }
            }
        }
    }
}
