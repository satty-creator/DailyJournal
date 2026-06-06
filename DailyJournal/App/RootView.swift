//
//  RootView.swift
//  DailyJournal
//

import SwiftUI

// MARK: - Root
struct RootView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

    var body: some View {
        Group {
            switch authViewModel.authState {
            case .loading:
                SplashView()
            case .authenticated:
                MainTabView()
            case .unverified:
                VerificationView()
            case .unauthenticated:
                AuthContainerView()
            }
        }
        .animation(.easeInOut(duration: 0.4), value: authViewModel.authState)
    }
}

// MARK: - Splash
struct SplashView: View {
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            AppTheme.paper.ignoresSafeArea()

            VStack(spacing: 12) {
                Text("ninety.")
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

// MARK: - Main tab view (4 tabs)
struct MainTabView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

    var body: some View {
        TabView {
            HomeView(userId: authViewModel.currentUser?.id ?? "")
                .tabItem {
                    Label("Today", systemImage: "sun.horizon")
                }

            JournalListView(userId: authViewModel.currentUser?.id ?? "")
                .tabItem {
                    Label("Journal", systemImage: "book")
                }

            PatternsView(userId: authViewModel.currentUser?.id ?? "")
                .tabItem {
                    Label("Patterns", systemImage: "waveform.path")
                }

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person")
                }
        }
        .tint(AppTheme.terracotta)
    }
}

// MARK: - Profile view
struct ProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var isEditing = false
    @State private var editedName = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.paper.ignoresSafeArea()
                List {
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

                    // MARK: Sign out
                    Section {
                        Button(role: .destructive) {
                            authViewModel.signOut()
                        } label: {
                            Label("Sign out", systemImage: "arrow.right.square")
                                .font(.system(size: 15))
                        }
                        .listRowBackground(AppTheme.cream)
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
        }
    }
}
