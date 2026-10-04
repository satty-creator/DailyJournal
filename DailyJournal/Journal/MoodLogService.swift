//
//  MoodLogService.swift
//  DailyJournal
//
//  Writes and reads `users/{uid}/moodLogs/{yyyy-MM-dd}` — one doc per local
//  date, each holding the day's 0–10 ratings as a points array. First written
//  to by onboarding's baseline step and guided first entry (before/after);
//  `MoodTrendCard` on the Mirror tab is the first reader. The collection
//  itself predates this — see `FirestoreSchema.moodLogs` — but nothing wrote
//  to it until now.
//
//  Fire-and-forget, like every other Firestore write in the app (CLAUDE.md,
//  "Fire-and-forget writes").
//

import Foundation
import FirebaseFirestore

/// Where a single rating came from — kept distinct so a chart or a future
/// "what moved this" surface can tell a snap baseline apart from a rating
/// made at the end of a guided reflection.
enum MoodLogSource: String, Codable {
    case baseline
    case entryBefore = "entry_before"
    case entryAfter  = "entry_after"
}

struct MoodLogPoint: Codable, Equatable {
    let value: Int
    let source: MoodLogSource
    let at: Date

    init(value: Int, source: MoodLogSource, at: Date = Date()) {
        self.value = value
        self.source = source
        self.at = at
    }

    init?(from data: [String: Any]) {
        guard
            let value = data["value"] as? Int,
            let sourceRaw = data["source"] as? String,
            let source = MoodLogSource(rawValue: sourceRaw),
            let at = (data["at"] as? Timestamp)?.dateValue()
        else { return nil }
        self.value = value
        self.source = source
        self.at = at
    }

    func toFirestoreData() -> [String: Any] {
        ["value": value, "source": source.rawValue, "at": Timestamp(date: at)]
    }
}

final class MoodLogService {

    static let shared = MoodLogService()
    private init() {}

    private let db = Firestore.firestore()
    private static let dateKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        return f
    }()

    private func moodLogsCollection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection(FirestoreSchema.moodLogs)
    }

    /// Appends one rating to today's doc (local date), creating it if needed.
    /// Fire-and-forget.
    func log(value: Int, source: MoodLogSource, userId: String, at: Date = Date()) {
        guard !userId.isEmpty else { return }
        let dateKey = Self.dateKeyFormatter.string(from: at)
        let point = MoodLogPoint(value: value, source: source, at: at)
        moodLogsCollection(for: userId)
            .document(dateKey)
            .setData(["points": FieldValue.arrayUnion([point.toFirestoreData()])], merge: true) { _ in }
    }

    /// The last `days` days of ratings, oldest first, flattened across every
    /// day's `points` array. Cache-first so `MoodTrendCard` paints instantly
    /// off whatever's already synced locally.
    func fetch(days: Int = 90, userId: String) async -> [MoodLogPoint] {
        guard !userId.isEmpty else { return [] }
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date.distantPast
        let sinceKey = Self.dateKeyFormatter.string(from: since)
        let query = moodLogsCollection(for: userId)
            .whereField(FieldPath.documentID(), isGreaterThanOrEqualTo: sinceKey)

        let snapshot: QuerySnapshot
        if let cached = try? await query.getDocuments(source: .cache), !cached.isEmpty {
            snapshot = cached
        } else if let fetched = try? await query.getDocuments(source: .default) {
            snapshot = fetched
        } else {
            return []
        }

        let points = snapshot.documents.flatMap { doc -> [MoodLogPoint] in
            guard let raw = doc.data()["points"] as? [[String: Any]] else { return [] }
            return raw.compactMap(MoodLogPoint.init(from:))
        }
        return points.sorted { $0.at < $1.at }
    }
}
