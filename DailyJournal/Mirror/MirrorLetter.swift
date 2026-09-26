// MirrorLetter.swift
// DailyJournal
//
// The weekly Mirror letter (§3.10) — three sentences, server-written once a
// week, read-only client-side. Firestore path:
// users/{uid}/mirrorLetters/{yyyy-MM-dd} (the Sunday that starts the week).

import Foundation
import FirebaseFirestore

struct MirrorLetter: Identifiable {
    let id: String   // the week key (doc id)
    let letter: String
    let quote: String?
    let generatedAt: Date
    var openedAt: Date?

    init?(from data: [String: Any], id: String) {
        guard
            let letter = data["letter"] as? String, !letter.isEmpty,
            let generatedAt = (data["generatedAt"] as? Timestamp)?.dateValue()
        else { return nil }
        self.id           = id
        self.letter       = letter
        self.quote        = data["quote"] as? String
        self.generatedAt  = generatedAt
        self.openedAt     = (data["openedAt"] as? Timestamp)?.dateValue()
    }

    /// Shown as a banner only while unread and recent — an old unopened
    /// letter isn't worth surfacing once the next one has likely landed.
    var isFreshAndUnread: Bool {
        openedAt == nil && Date().timeIntervalSince(generatedAt) < 7 * 86400
    }
}

@MainActor
final class MirrorLetterService: ObservableObject {
    static let shared = MirrorLetterService()
    private init() {}

    @Published private(set) var latest: MirrorLetter?

    func loadLatest(for userId: String) async {
        guard let snapshot = try? await FirestoreCacheFirst.documents(
            Firestore.firestore()
                .collection("users").document(userId)
                .collection("mirrorLetters")
                .order(by: "generatedAt", descending: true)
                .limit(to: 1),
            key: "mirrorLetterLatest.\(userId)"
        ), let doc = snapshot.documents.first else { return }
        latest = MirrorLetter(from: doc.data(), id: doc.documentID)
    }

    /// Server-first refresh, for the push deep link only. The push means a
    /// letter was written moments ago — `loadLatest`'s cache-first read would
    /// still hand back last week's until its own detached refresh lands. Silently
    /// leaves `latest` alone when offline; the banner keeps whatever it already has.
    func refreshFromServer(for userId: String) async {
        guard let snapshot = try? await Firestore.firestore()
            .collection("users").document(userId)
            .collection("mirrorLetters")
            .order(by: "generatedAt", descending: true)
            .limit(to: 1)
            .getDocuments(source: .server),
            let doc = snapshot.documents.first else { return }
        latest = MirrorLetter(from: doc.data(), id: doc.documentID)
    }

    func markOpened(userId: String) {
        guard let letter = latest, letter.openedAt == nil else { return }
        latest?.openedAt = Date()
        Firestore.firestore()
            .collection("users").document(userId)
            .collection("mirrorLetters").document(letter.id)
            .updateData(["openedAt": Timestamp(date: Date())]) { _ in }
    }
}
