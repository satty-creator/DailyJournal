//
//  JournalEntry.swift
//  DailyJournal
//

import Foundation
import FirebaseFirestore
import SwiftUI

// MARK: - Session Type
enum SessionType: String, Codable, CaseIterable {
    case timed        = "ninetySecond"   // raw value kept for Firestore back-compat
    case freeWrite    = "freeWrite"
    /// An entry woven from a Daily Chat conversation with Spilr, back when chat had
    /// a "Casual Vent" mode alongside Thought Journal (retired — chat is Thought
    /// Journal only now, and always saves as `.cbtReframe`). No longer a write
    /// target; kept only to decode historical entries. Behaves exactly like any
    /// other entry downstream — Echoes, River and Patterns all treat it as normal
    /// prose.
    case dailyChat    = "dailyChat"
    /// A structured Journal Snapshot card (Focus / Hurdle / Shift) produced by
    /// Daily Chat. Stored as plain text; behaves like any other entry downstream.
    /// (Raw value kept as "cbtReframe" for Firestore back-compat, from when this
    /// was one of two chat modes.)
    case cbtReframe   = "cbtReframe"
    /// A guided template run (`TemplateRunnerViewModel`) — a short structured
    /// exercise whose answers were woven into prose. Behaves like any other
    /// entry downstream; see `templateId` / `templateScaleBefore` /
    /// `templateScaleAfter` below for the metadata specific to it.
    case template     = "template"
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
    /// Download URL of an optional attached photo (Firebase Storage). nil = none.
    var photoURL: String?
    /// The `JournalTemplate.id` this entry was woven from, if any. Metadata
    /// only — the answer text itself is never persisted (only `content`,
    /// the woven prose, is encrypted at rest; raw structured answers would
    /// be plaintext, which the two scale values below sidestep by being
    /// non-sensitive numbers rather than free text).
    var templateId: String?
    /// Before/after 0–10 self-ratings, present only for a template whose
    /// steps include both a `.before` and `.after` scale (currently
    /// "Untangle a decision"). Lets the delta shown on the review screen be
    /// compared across entries later, not just shown once and discarded.
    var templateScaleBefore: Int?
    var templateScaleAfter: Int?

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
        sentimentLabel: String? = nil,
        photoURL: String? = nil,
        templateId: String? = nil,
        templateScaleBefore: Int? = nil,
        templateScaleAfter: Int? = nil
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
        self.photoURL               = photoURL
        self.templateId             = templateId
        self.templateScaleBefore    = templateScaleBefore
        self.templateScaleAfter     = templateScaleAfter
    }

    // MARK: - Firestore init
    init?(from data: [String: Any]) {
        guard
            let id        = data["id"]      as? String,
            let userId    = data["userId"]  as? String,
            let rawContent = data["content"] as? String,
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        else { return nil }

        let isEncrypted = data["encrypted"] as? Bool ?? false
        let content = isEncrypted
            ? (EntryEncryption.decrypt(rawContent) ?? rawContent)
            : rawContent

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
        self.photoURL               = data["photoURL"]           as? String
        self.templateId             = data["templateId"]           as? String
        self.templateScaleBefore    = data["templateScaleBefore"]  as? Int
        self.templateScaleAfter     = data["templateScaleAfter"]   as? Int
    }

    // MARK: - Firestore write
    func toFirestoreData() -> [String: Any] {
        let encryptedContent = EntryEncryption.encrypt(content) ?? content
        var data: [String: Any] = [
            "id":               id,
            "userId":           userId,
            "title":            title,
            "content":          encryptedContent,
            "encrypted":        true,
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
        if let p = photoURL               { data["photoURL"]               = p }
        if let t = templateId             { data["templateId"]             = t }
        if let b = templateScaleBefore    { data["templateScaleBefore"]    = b }
        if let a = templateScaleAfter     { data["templateScaleAfter"]     = a }
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

    var shortFormattedDate: String {
        createdAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
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
