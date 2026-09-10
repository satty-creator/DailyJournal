//
//  ThemeManager.swift
//  DailyJournal
//
//  Owns the currently selected theme, persists it, and pushes the active
//  palette into `AppTheme` so every screen that reads `AppTheme.*` adopts it.
//
//  Live switching strategy:
//  `AppTheme.*` colours are computed from `AppTheme.active`, which is a plain
//  static. Mutating it does not, by itself, tell SwiftUI to redraw. So the root
//  view observes this manager and re-identifies its content on `themeID` change
//  (`.id(themeManager.themeID)`), which rebuilds the tree with the new palette.
//  This keeps the whole refactor to zero per-screen edits.
//
//  See themesprd.md.
//

import SwiftUI
import Combine

@MainActor
final class ThemeManager: ObservableObject {

    static let shared = ThemeManager()

    private static let storageKey = "ninety.selectedTheme"

    /// The user's selected theme. Setting it persists the choice and updates
    /// the global `AppTheme.active` palette.
    @Published var themeID: ThemeID {
        didSet {
            guard themeID != oldValue else { return }
            AppTheme.active = themeID.palette
            UserDefaults.standard.set(themeID.rawValue, forKey: Self.storageKey)
            AnalyticsManager.shared.trackThemeChanged(
                themeId: themeID.rawValue,
                isDark: themeID.colorScheme == .dark
            )
        }
    }

    /// The palette currently in effect.
    var palette: ThemePalette { themeID.palette }

    /// Drives `preferredColorScheme` at the root.
    var colorScheme: ColorScheme { themeID.colorScheme }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.storageKey)
        let initial = saved.flatMap(ThemeID.init(rawValue:)) ?? .bloom
        self.themeID = initial
        // Ensure AppTheme reflects the persisted choice from the very first read,
        // before any view body runs.
        AppTheme.active = initial.palette
    }

    /// Convenience setter used by the picker (animatable from the call site).
    func select(_ id: ThemeID) {
        themeID = id
    }
}
