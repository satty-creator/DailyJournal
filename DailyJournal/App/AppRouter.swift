//
//  AppRouter.swift
//  DailyJournal
//
//  Cross-tab navigation state.
//
//  WHY THIS EXISTS
//  ---------------
//  `MainTabView` used to be a bare `TabView { … }` with no `selection:` binding, so
//  nothing anywhere in the app could change tabs programmatically. The visible
//  symptom: you save an entry from Today, the entry lands in the Journal tab, and
//  you are returned to Today with no way to see what just happened. There was also
//  no way for one tab to point at a specific row in another.
//
//  This is deliberately a tiny shared object rather than closures threaded through
//  four different composers (SpillWriteView, JournalEditorView, DailyChatView,
//  JournalListView's FAB), which is what the closure approach would have required.
//
//  Injected once, in `MainTabView`, via `.environmentObject`.
//

import SwiftUI

/// The three tabs, in the order they appear in `MainTabView`. Raw values are the
/// `TabView` selection tags — do not renumber without updating the `.tag(…)` calls.
enum AppTab: Int, Hashable, CaseIterable {
    case today    = 0
    case journal  = 1
    case mirror   = 2
}

@MainActor
final class AppRouter: ObservableObject {

    /// Singleton so `PushNotificationManager`'s `UNUserNotificationCenterDelegate`
    /// callback — which fires outside any SwiftUI view and has no way to reach the
    /// `@StateObject` `MainTabView` owns — can still route a notification tap.
    /// `MainTabView` adopts this instance rather than creating its own; every other
    /// consumer keeps using `@EnvironmentObject` as before.
    static let shared = AppRouter()

    /// Which tab is on screen. Bound to `TabView(selection:)`.
    @Published var selectedTab: AppTab = .today

    /// An entry the Journal tab should scroll to and briefly highlight on next
    /// appearance. Set alongside `selectedTab = .journal`; the Journal list clears
    /// it once consumed so the highlight plays exactly once.
    @Published var highlightedEntryId: String?

    /// Set when a "weekly_letter" push is tapped. The Mirror tab consumes this
    /// (fetching the letter fresh from the server, since a push means one was just
    /// written) and clears it once handled — see `MirrorView.consumePendingLetterOpen`.
    @Published var pendingWeeklyLetterOpen = false

    /// Jump to the Journal tab and point at a specific entry.
    ///
    /// Used by the Today "done" card so "See it in your Journal" lands on the
    /// entry the user just wrote rather than the top of an undifferentiated list.
    func showInJournal(entryId: String?) {
        highlightedEntryId = entryId
        selectedTab = .journal
    }

    /// Called by the Journal list once it has scrolled to and highlighted the row,
    /// so returning to the tab later doesn't replay the animation.
    func clearHighlight() {
        highlightedEntryId = nil
    }

    /// Jump to the Mirror tab.
    func showMirror() {
        selectedTab = .mirror
    }

    /// A "weekly_letter" push was tapped — jump to Mirror and flag that it should
    /// open the letter once loaded.
    func openWeeklyLetter() {
        pendingWeeklyLetterOpen = true
        selectedTab = .mirror
    }
}
