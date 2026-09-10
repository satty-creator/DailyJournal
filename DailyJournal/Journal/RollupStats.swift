//
//  RollupStats.swift
//  DailyJournal
//
//  A single small derived document per user — `users/{uid}/rollups/stats` —
//  holding the numbers that would otherwise require fetching (and, for entries,
//  decrypting) the full corpus just to answer "how many?".
//
//  `entryCount` is what `MirrorMaturity` gates on (see MirrorMaturity.swift) and
//  what Patterns' stat row displays. Kept incrementally by JournalService on
//  every create/delete — a single FieldValue.increment, no read required — and
//  self-healing: if the counter has never existed, RollupService backfills it
//  from a Firestore COUNT aggregation query, which returns a number without
//  downloading or decrypting a single entry document.
//

import Foundation
import FirebaseFirestore

struct RollupStats: Codable {

    let userId: String
    var entryCount: Int
    var lastEntryAt: Date?
    var updatedAt: Date
    /// Bumped if the shape of this doc ever changes, so a future reader can tell
    /// an old backfill apart from a reconciled one.
    var schemaVersion: Int

    static let currentSchemaVersion = 1

    static func empty(userId: String) -> RollupStats {
        // Not `.distantPast` — `toFirestoreData()` feeds `updatedAt` into
        // `Timestamp(date:)`, which crashes on that value (see the same fix in
        // EventService.backfillIfNeeded). Epoch zero says "never updated" just
        // as clearly and is safely inside Firestore's representable range.
        RollupStats(userId: userId, entryCount: 0, lastEntryAt: nil,
                    updatedAt: Date(timeIntervalSince1970: 0), schemaVersion: currentSchemaVersion)
    }

    init(userId: String, entryCount: Int, lastEntryAt: Date?, updatedAt: Date, schemaVersion: Int) {
        self.userId = userId
        self.entryCount = entryCount
        self.lastEntryAt = lastEntryAt
        self.updatedAt = updatedAt
        self.schemaVersion = schemaVersion
    }

    init?(from data: [String: Any]) {
        guard
            let userId = data["userId"] as? String,
            let entryCount = data["entryCount"] as? Int,
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        else { return nil }

        self.userId = userId
        self.entryCount = max(0, entryCount) // a counter racing a backfill can dip below 0 transiently
        self.lastEntryAt = (data["lastEntryAt"] as? Timestamp)?.dateValue()
        self.updatedAt = updatedAt
        self.schemaVersion = data["schemaVersion"] as? Int ?? 1
    }

    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "userId": userId,
            "entryCount": entryCount,
            "updatedAt": Timestamp(date: updatedAt),
            "schemaVersion": schemaVersion
        ]
        if let lastEntryAt { data["lastEntryAt"] = Timestamp(date: lastEntryAt) }
        return data
    }
}
