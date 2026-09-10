//
//  JournalViewMode.swift
//  DailyJournal
//
//  List ↔ collage toggle for the Journal tab (Spilr Redesign screens 1e/1f).
//  Persisted per-device so the choice survives a relaunch and, more importantly,
//  a theme switch — `RootView` re-identifies the whole tab tree with
//  `.id(themeManager.themeID)` on every theme change, which would otherwise
//  reset any @State-held mode back to its default. Same persistence idiom as
//  `ChatMode.lastUsed` (Chat/ChatMode.swift).
//

import Foundation

enum JournalViewMode: String {
    case list
    case collage

    private static let storageKey = "spilr.journalViewMode"

    /// The last view mode the user picked, defaulting to list.
    static var lastUsed: JournalViewMode {
        get { JournalViewMode(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .list }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: storageKey) }
    }
}
