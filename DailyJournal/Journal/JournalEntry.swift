//
//  JournalEntry.swift
//  DailyJournal
//

import Foundation
import FirebaseFirestore
import SwiftUI

// MARK: - Session Type
enum SessionType: String, Codable, CaseIterable {
    case ninetySecond = "ninetySecond"
    case freeWrite    = "freeWrite"
}

// MARK: - Mood
enum Mood: String, CaseIterable, Codable {
    case amazing  = "amazing"
    case good     = "good"
    case neutral  = "neutral"
    case bad      = "bad"
    case terrible = "terrible"

    var emoji: String {
        switch self {
        case .amazing:  return "🤩"
        case .good:     return "😊"
        case .neutral:  return "😐"
        case .bad:      return "😔"
        case .terrible: return "😢"
        }
    }

    /// Face emoji for the pleasant ↔ unpleasant scale.
    var faceEmoji: String {
        switch self {
        case .amazing:  return "😄"
        case .good:     return "🙂"
        case .neutral:  return "😐"
        case .bad:      return "🙁"
        case .terrible: return "😣"
        }
    }

    var label: String { rawValue.capitalized }

    /// Valence wording — "very pleasant" through "very unpleasant".
    var scaleLabel: String {
        switch self {
        case .amazing:  return "Very pleasant"
        case .good:     return "Pleasant"
        case .neutral:  return "Neutral"
        case .bad:      return "Unpleasant"
        case .terrible: return "Very unpleasant"
        }
    }
}

// MARK: - Journal Entry
struct JournalEntry: Identifiable, Codable {

    let id: String
    let userId: String
    var title: String
    var content: String
    var mood: Mood?
    var tags: [String]
    let createdAt: Date
    var updatedAt: Date

    // ── New fields ─────────────────────────────────────────────────────
    var sessionType: SessionType
    var futureSelfDeliveryDate: Date?
    var futureSelfOpened: Bool
    var aiSummaryBullets: [String]
    var aiQuestion: String?
    var sentimentLabel: String?

    // MARK: - New entry init
    init(
        userId: String,
        title: String = "",
        content: String,
        mood: Mood? = nil,
        tags: [String] = [],
        sessionType: SessionType = .freeWrite,
        futureSelfDeliveryDate: Date? = nil,
        aiSummaryBullets: [String] = [],
        aiQuestion: String? = nil,
        sentimentLabel: String? = nil
    ) {
        self.id                     = UUID().uuidString
        self.userId                 = userId
        self.title                  = title
        self.content                = content
        self.mood                   = mood
        self.tags                   = tags
        self.createdAt              = Date()
        self.updatedAt              = Date()
        self.sessionType            = sessionType
        self.futureSelfDeliveryDate = futureSelfDeliveryDate
        self.futureSelfOpened       = false
        self.aiSummaryBullets       = aiSummaryBullets
        self.aiQuestion             = aiQuestion
        self.sentimentLabel         = sentimentLabel
    }

    // MARK: - Firestore init
    init?(from data: [String: Any]) {
        guard
            let id        = data["id"]      as? String,
            let userId    = data["userId"]  as? String,
            let content   = data["content"] as? String,
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        else { return nil }

        self.id        = id
        self.userId    = userId
        self.title     = data["title"]  as? String ?? ""
        self.content   = content
        self.mood      = Mood(rawValue: data["mood"] as? String ?? "")
        self.tags      = data["tags"]   as? [String] ?? []
        self.createdAt = createdAt
        self.updatedAt = updatedAt

        // New fields — all default-safe for backward compat
        self.sessionType            = SessionType(rawValue: data["sessionType"] as? String ?? "freeWrite") ?? .freeWrite
        self.futureSelfDeliveryDate = (data["futureSelfDeliveryDate"] as? Timestamp)?.dateValue()
        self.futureSelfOpened       = data["futureSelfOpened"]  as? Bool     ?? false
        self.aiSummaryBullets       = data["aiSummaryBullets"]  as? [String] ?? []
        self.aiQuestion             = data["aiQuestion"]         as? String
        self.sentimentLabel         = data["sentimentLabel"]     as? String
    }

    // MARK: - Firestore write
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "id":               id,
            "userId":           userId,
            "title":            title,
            "content":          content,
            "mood":             mood?.rawValue ?? "",
            "tags":             tags,
            "createdAt":        Timestamp(date: createdAt),
            "updatedAt":        Timestamp(date: updatedAt),
            "sessionType":      sessionType.rawValue,
            "futureSelfOpened": futureSelfOpened,
            "aiSummaryBullets": aiSummaryBullets
        ]
        if let d = futureSelfDeliveryDate { data["futureSelfDeliveryDate"] = Timestamp(date: d) }
        if let q = aiQuestion             { data["aiQuestion"]             = q }
        if let s = sentimentLabel         { data["sentimentLabel"]         = s }
        return data
    }

    // MARK: - Computed
    var wordCount: Int { content.split(separator: " ").count }

    var displayTitle: String {
        title.isEmpty
            ? String(content.prefix(60)).trimmingCharacters(in: .whitespacesAndNewlines)
            : title
    }

    var formattedDate: String {
        createdAt.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var isScheduledLetter: Bool { futureSelfDeliveryDate != nil }
    var hasArrivedLetter:  Bool {
        guard let d = futureSelfDeliveryDate else { return false }
        return d <= Date() && !futureSelfOpened
    }

    var accentColor: Color {
        if let sentiment = sentimentLabel { return AppTheme.sentimentColor(sentiment) }
        return AppTheme.moodColor(mood)
    }
}
