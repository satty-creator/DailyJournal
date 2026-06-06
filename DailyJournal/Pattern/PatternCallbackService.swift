//
//  PatternCallbackService.swift
//  DailyJournal
//
//  Firestore CRUD for `users/{uid}/patternCallbacks` plus the frequency /
//  quiet-hours / account-age gating that keeps callbacks SCARCE.
//
//  Callbacks are rare by design, so the whole subcollection is tiny — we read
//  it wholesale and filter in Swift. That sidesteps every composite-index
//  requirement (same pragmatic choice as MoodLogService).
//
//  Write pattern: fire-and-forget, same as EchoService / JournalService.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

final class PatternCallbackService {

    private let db = Firestore.firestore()

    private func collection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("patternCallbacks")
    }

    // MARK: - Create

    /// Fire-and-forget. Writes to local cache immediately.
    func createCallback(_ callback: PatternCallback) {
        collection(for: callback.userId)
            .document(callback.id)
            .setData(callback.toFirestoreData())
    }

    // MARK: - Fetch

    /// Reads the entire (small) subcollection. Callbacks are scarce by design.
    func fetchAll(for userId: String) async throws -> [PatternCallback] {
        let snapshot = try await collection(for: userId).getDocuments()
        return snapshot.documents.compactMap { PatternCallback(from: $0.data()) }
    }

    // MARK: - Status mutations (fire-and-forget)

    private func patch(_ callback: PatternCallback, _ fields: [String: Any]) {
        collection(for: callback.userId)
            .document(callback.id)
            .setData(fields, merge: true)
    }

    func markShown(_ callback: PatternCallback) {
        patch(callback, [
            "status":  PatternCallbackStatus.shown.rawValue,
            "shownAt": Timestamp(date: Date())
        ])
    }

    func markAnswered(_ callback: PatternCallback) {
        patch(callback, [
            "status":      PatternCallbackStatus.answered.rawValue,
            "respondedAt": Timestamp(date: Date())
        ])
    }

    func markDismissed(_ callback: PatternCallback) {
        patch(callback, [
            "status":      PatternCallbackStatus.dismissed.rawValue,
            "respondedAt": Timestamp(date: Date())
        ])
    }

    func markMuted(_ callback: PatternCallback) {
        patch(callback, [
            "status":      PatternCallbackStatus.muted.rawValue,
            "respondedAt": Timestamp(date: Date())
        ])
    }

    // MARK: - Surfacing gate
    //
    // Given the full set of callbacks plus the user's settings, decide which
    // single callback (if any) may be shown right now.

    /// The callbacks that have already been surfaced (any non-pending status
    /// that carries a shownAt timestamp).
    private func shownCallbacks(_ all: [PatternCallback]) -> [PatternCallback] {
        all.filter { $0.shownAt != nil }
    }

    /// Number of callbacks shown within the trailing `days`.
    private func shownCount(_ all: [PatternCallback], withinDays days: Int) -> Int {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        return shownCallbacks(all).filter { ($0.shownAt ?? .distantPast) >= cutoff }.count
    }

    /// Days since the account was created (Auth metadata is authoritative — the
    /// local AppUser.createdAt is just `Date()` from the auth listener).
    private var accountAgeDays: Int {
        guard let created = Auth.auth().currentUser?.metadata.creationDate else { return 9999 }
        return Int(Date().timeIntervalSince(created) / 86400)
    }

    /// Weekly cap that scales with account maturity (and the user's preference).
    private func weeklyCap(_ settings: PatternSettings) -> Int {
        if settings.frequency == .off { return 0 }
        let age = accountAgeDays
        if age < 14 { return 0 }          // 2-week grace period for new users
        if settings.frequency == .weekly { return 1 }
        return age >= 90 ? 2 : 1          // matures from 1/week to 2/week at day 90
    }

    /// True if we're inside the 4-day hard-suppression window after the last
    /// surfaced callback.
    private func inSuppressionWindow(_ all: [PatternCallback]) -> Bool {
        guard let lastShown = shownCallbacks(all).compactMap(\.shownAt).max() else { return false }
        return Date().timeIntervalSince(lastShown) < 4 * 86400
    }

    /// Quiet hours: 11pm–7am local. We stay silent unless the user is a habitual
    /// night-writer (they already engage at this hour, so a callback isn't an
    /// intrusion).
    private func inQuietHours(habitualNightUser: Bool) -> Bool {
        if habitualNightUser { return false }
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 23 || hour < 7
    }

    /// The single highest-salience callback eligible to surface right now, or
    /// nil if the gates say "stay quiet". Pure given its inputs — easy to test.
    ///
    /// - Parameters:
    ///   - all:      every callback for the user (from `fetchAll`).
    ///   - settings: the user's frequency / scope / mute preferences.
    ///   - habitualNightUser: pass true when the user regularly writes at night.
    func surfaceableCallback(
        from all: [PatternCallback],
        settings: PatternSettings,
        habitualNightUser: Bool = false
    ) -> PatternCallback? {

        // Global off switch.
        guard settings.frequency != .off else { return nil }
        // Respect the 4-day cool-down after the last callback.
        guard !inSuppressionWindow(all) else { return nil }
        // Respect the rolling weekly cap (scaled by account age).
        guard shownCount(all, withinDays: 7) < weeklyCap(settings) else { return nil }
        // Respect quiet hours.
        guard !inQuietHours(habitualNightUser: habitualNightUser) else { return nil }

        // Of the pending callbacks, drop muted entities and out-of-scope
        // archetypes, then take the most salient.
        return all
            .filter { $0.isSurfaceable }
            .filter { settings.scope.allows($0.archetype) }
            .filter { callback in
                guard let entity = callback.entity else { return true }
                return !settings.isMuted(entity)
            }
            .sorted { $0.salienceScore > $1.salienceScore }
            .first
    }

    /// Whether detection is even worth running: skip if callbacks are off, the
    /// account is too young, or we're inside the suppression window. (The 20h
    /// throttle is enforced separately by PatternSettings.)
    func detectionIsWorthwhile(
        from all: [PatternCallback],
        settings: PatternSettings
    ) -> Bool {
        guard settings.frequency != .off else { return false }
        guard weeklyCap(settings) > 0 else { return false }   // also covers <14-day grace
        guard !inSuppressionWindow(all) else { return false }
        // Don't pile up: if an unshown pending callback already exists, no need
        // to detect again until it's resolved.
        return !all.contains { $0.isSurfaceable }
    }
}
