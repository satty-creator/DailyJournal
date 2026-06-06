//
//  MoodLog.swift
//  DailyJournal
//
//  A lightweight, journal-free mood check-in. One record per calendar day,
//  stored separately from journal entries so a user can log how they feel
//  without writing anything. Feeds into the Patterns mood distribution
//  alongside the moods attached to full entries.
//

import Foundation
import FirebaseFirestore

struct MoodLog: Identifiable, Codable {

    /// Document id == day key ("yyyy-MM-dd"), so logging again on the same day
    /// updates that day's record instead of creating duplicates.
    let id: String
    let userId: String
    var mood: Mood
    var note: String?
    let createdAt: Date
    var updatedAt: Date

    /// Stable per-day key in the user's current calendar.
    static func dayKey(for date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    init(userId: String, mood: Mood, note: String? = nil, date: Date = Date()) {
        self.id        = MoodLog.dayKey(for: date)
        self.userId    = userId
        self.mood      = mood
        self.note      = note
        self.createdAt = date
        self.updatedAt = date
    }

    init?(from data: [String: Any]) {
        guard
            let id     = data["id"]     as? String,
            let userId = data["userId"] as? String,
            let moodRaw = data["mood"]  as? String,
            let mood   = Mood(rawValue: moodRaw),
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        else { return nil }

        self.id        = id
        self.userId    = userId
        self.mood      = mood
        self.note      = data["note"] as? String
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "id":        id,
            "userId":    userId,
            "mood":      mood.rawValue,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt)
        ]
        if let note { data["note"] = note }
        return data
    }
}
