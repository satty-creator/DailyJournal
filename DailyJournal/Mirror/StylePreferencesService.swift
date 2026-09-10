// StylePreferencesService.swift
// DailyJournal
//
// Load/save for StylePreferences. Follows the same shape as
// MirrorGraphService/SelfModelService: @MainActor singleton, cache-first read,
// fire-and-forget writes.

import Foundation
import FirebaseFirestore

@MainActor
final class StylePreferencesService: ObservableObject {

    static let shared = StylePreferencesService()
    private init() {}

    @Published private(set) var preferences: StylePreferences = .empty

    private func docRef(userId: String) -> DocumentReference {
        Firestore.firestore()
            .collection("users").document(userId)
            .collection("stylePreferences").document("current")
    }

    func load(for userId: String) async {
        guard let snapshot = try? await FirestoreCacheFirst.document(
            docRef(userId: userId),
            key: "stylePreferences.\(userId)"
        ), let data = snapshot.data(), let prefs = StylePreferences(from: data)
        else { return }
        preferences = prefs
    }

    /// Routes one piece of Mirror feedback into style learning. `patternType`
    /// is the hypothesis's `PatternType.rawValue` the feedback was given on.
    /// Fire-and-forget, matching every other Mirror write.
    func recordFeedback(_ feedback: MirrorFeedback, patternType: String, userId: String) {
        var prefs = preferences
        switch feedback {
        case .tooIntense:
            prefs.sharpness = max(-2, prefs.sharpness - 1)
        case .almost, .notMe:
            let streak = (prefs.softNegativeStreak[patternType] ?? 0) + 1
            if streak >= 2 {
                prefs.mutedTypes[patternType] = Date().addingTimeInterval(StylePreferences.muteDuration)
                prefs.softNegativeStreak[patternType] = 0
            } else {
                prefs.softNegativeStreak[patternType] = streak
            }
        case .thisIsMe:
            prefs.softNegativeStreak[patternType] = 0
        case .askTomorrow:
            break
        }
        prefs.updatedAt = Date()
        preferences = prefs

        docRef(userId: userId).setData(prefs.toFirestoreData(), merge: true) { _ in }
    }

    /// Appends a free-text style note (see MirrorCorrectionClassifier),
    /// most-recent-first, capped at StylePreferences.maxNotes.
    func addNote(_ text: String, userId: String) {
        var prefs = preferences
        prefs.notes = Array(([text] + prefs.notes).prefix(StylePreferences.maxNotes))
        prefs.updatedAt = Date()
        preferences = prefs

        docRef(userId: userId).setData(prefs.toFirestoreData(), merge: true) { _ in }
    }
}
