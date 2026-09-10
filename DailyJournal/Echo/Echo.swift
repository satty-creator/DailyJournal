//
//  Echo.swift
//  DailyJournal
//
//  The Echo data model. An Echo is an AI-extracted callback from a past entry —
//  at most one is shown per HomeView load, always dismissable, never a list.
//

import Foundation
import FirebaseFirestore

// MARK: - Echo Type

enum EchoType: String, Codable {
    case intention  = "intention"   // "I'll email Marcus before the weekend"
    case openLoop   = "open_loop"   // "the meeting on Thursday"
    case theme      = "theme"       // recurring person / fear / situation
    case moodMarker = "mood_marker" // "I feel completely stuck"

    var displayLabel: String {
        switch self {
        case .intention:  return "stated intention"
        case .openLoop:   return "open loop"
        case .theme:      return "recurring theme"
        case .moodMarker: return "mood callback"
        }
    }

    /// Human-readable primary action label on the card
    var actionLabel: String {
        switch self {
        case .intention:  return "done ✓"
        case .openLoop:   return "it happened"
        case .theme:      return "read them"
        case .moodMarker: return "noted"
        }
    }
}

// MARK: - Echo Status

enum EchoStatus: String, Codable {
    case pending   = "pending"    // waiting to be surfaced
    case answered  = "answered"   // user responded positively
    case dismissed = "dismissed"  // skipped ≥2 times
    case expired   = "expired"    // not acted on within 7 days
}

// MARK: - Echo

struct Echo: Identifiable, Codable {

    let id: String
    let userId: String
    let sourceEntryId: String
    let sourceEntryCreatedAt: Date   // the journal entry's own createdAt, used for "time ago"
    let type: EchoType
    /// The user's exact words from the source entry — never paraphrased.
    let quote: String
    /// Don't surface before this date.
    let surfaceAfterDate: Date
    let confidence: Double
    var status: EchoStatus
    /// Increments on each skip. Reaching 2 → auto-dismiss. Persisted so decay
    /// survives app restarts.
    var skipCount: Int
    let createdAt: Date
    var answeredAt: Date?
    /// For .theme type only — the specific keyword / name that recurs across entries
    /// (e.g. "dad", "the promotion"). The drill-down view that used this to
    /// search matching entries was cut (Journal's own search covers it); kept
    /// here as it's still written by extraction and costs nothing unused.
    var themeKeyword: String?
    /// Spilr's voice line that FRAMES the quote (shown above it). The whole point
    /// of an echo's depth — a perspective, not a replay. Optional + default-safe.
    var line: String?

    // MARK: - Computed

    /// True when this echo should be shown on the home screen.
    var isSurfaceable: Bool {
        status == .pending && surfaceAfterDate <= Date()
    }

    // MARK: - New-entry init

    init(
        userId: String,
        sourceEntryId: String,
        sourceEntryCreatedAt: Date,
        type: EchoType,
        quote: String,
        surfaceAfterHours: Int,
        confidence: Double,
        themeKeyword: String? = nil,
        line: String? = nil
    ) {
        self.id                   = UUID().uuidString
        self.userId               = userId
        self.sourceEntryId        = sourceEntryId
        self.sourceEntryCreatedAt = sourceEntryCreatedAt
        self.type                 = type
        self.quote                = quote
        self.surfaceAfterDate     = Date().addingTimeInterval(Double(surfaceAfterHours) * 3600)
        self.confidence           = confidence
        self.status               = .pending
        self.skipCount            = 0
        self.createdAt            = Date()
        self.answeredAt           = nil
        self.themeKeyword         = themeKeyword
        self.line                 = line
    }

    // MARK: - Firestore deserialisation

    init?(from data: [String: Any]) {
        guard
            let id               = data["id"]               as? String,
            let userId           = data["userId"]           as? String,
            let sourceEntryId    = data["sourceEntryId"]    as? String,
            let sourceDate       = (data["sourceEntryCreatedAt"] as? Timestamp)?.dateValue(),
            let typeRaw          = data["type"]             as? String,
            let type             = EchoType(rawValue: typeRaw),
            let quote            = data["quote"]            as? String,
            let surfaceDate      = (data["surfaceAfterDate"] as? Timestamp)?.dateValue(),
            let confidence       = data["confidence"]       as? Double,
            let statusRaw        = data["status"]           as? String,
            let status           = EchoStatus(rawValue: statusRaw),
            let skipCount        = data["skipCount"]        as? Int,
            let createdAt        = (data["createdAt"]       as? Timestamp)?.dateValue()
        else { return nil }

        self.id                   = id
        self.userId               = userId
        self.sourceEntryId        = sourceEntryId
        self.sourceEntryCreatedAt = sourceDate
        self.type                 = type
        self.quote                = quote
        self.surfaceAfterDate     = surfaceDate
        self.confidence           = confidence
        self.status               = status
        self.skipCount            = skipCount
        self.createdAt            = createdAt
        self.answeredAt           = (data["answeredAt"] as? Timestamp)?.dateValue()
        self.themeKeyword         = data["themeKeyword"] as? String
        self.line                 = data["line"] as? String
    }

    // MARK: - Firestore serialisation

    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "id":                   id,
            "userId":               userId,
            "sourceEntryId":        sourceEntryId,
            "sourceEntryCreatedAt": Timestamp(date: sourceEntryCreatedAt),
            "type":                 type.rawValue,
            "quote":                quote,
            "surfaceAfterDate":     Timestamp(date: surfaceAfterDate),
            "confidence":           confidence,
            "status":               status.rawValue,
            "skipCount":            skipCount,
            "createdAt":            Timestamp(date: createdAt)
        ]
        if let answeredAt   = answeredAt   { data["answeredAt"]   = Timestamp(date: answeredAt) }
        if let themeKeyword = themeKeyword { data["themeKeyword"] = themeKeyword }
        if let line         = line         { data["line"]         = line }
        return data
    }
}
