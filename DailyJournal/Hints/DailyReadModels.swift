//
//  DailyReadModels.swift
//  DailyJournal
//
//  Domain models for "Today's Read" — the daily, zero-effort, instant-reward hook.
//
//  A Read is a single, sharp, evidence-backed line ("tenderly brutal") generated
//  from the user's own recent entries, surfaced once per day on Home behind a
//  sealed card. Tapping reveals the line plus "receipts" (tiny word chips drawn
//  from the user's actual words) and an invitation to reply in 90 seconds.
//
//  Storage mirrors the rest of the app: one Firestore doc per user per local date
//  at `users/{uid}/dailyReads/{localDate}`. We keep the codebase's manual
//  init?(from:) / toFirestoreData() style (Timestamps, String ids) rather than the
//  Codable+snake_case shape so every other model and service stays consistent.
//

import Foundation
import FirebaseFirestore

// MARK: - Tone

/// The flavour the *generated* read text actually lands in. This is a property of
/// the read, chosen by the engine, not a user setting.
enum ReadTone: String, Codable, CaseIterable {
    case soft
    case direct
    case funny
    case spicy

    /// Tiny mono-uppercase tag shown on the card.
    var displayLabel: String { rawValue }
}

// MARK: - Sharpness preference

/// The user-facing "how hard should it hit?" dial. Distinct from `ReadTone`:
/// `funny` is a *flavour* the engine can reach for, but the sharpness LADDER the
/// "too sharp" loop walks down is strictly soft ↔ direct ↔ spicy (per spec:
/// "spicy → direct, or direct → soft"). The local engine maps this preference
/// onto a tone, optionally choosing `funny` only at `.direct`/`.spicy`.
enum ReadSharpness: String, Codable, CaseIterable {
    case soft
    case direct
    case spicy

    /// Ordered gentle → sharp. Used by the "too sharp" step-down.
    static let ladder: [ReadSharpness] = [.soft, .direct, .spicy]

    var gradient: Int { Self.ladder.firstIndex(of: self) ?? 1 }

    /// One gradient gentler. `.soft` is the floor — it never goes lower.
    var softer: ReadSharpness {
        let i = gradient
        return i > 0 ? Self.ladder[i - 1] : .soft
    }
}

// MARK: - Feedback

/// The three top-level reactions on a revealed read.
enum ReadFeedback: String, Codable {
    case feltTrue     = "felt_true"
    case notMe        = "not_me"
    case tooSharp     = "too_sharp"
    case moreLikeThis = "more_like_this"
}

/// The "not me" micro-menu classification codes. Appended to training history so
/// the next payload assembly steers clear of the same failure mode.
enum ReadRejectionCode: String, Codable, CaseIterable {
    case tooDramatic   = "too_dramatic"
    case wrongTopic    = "wrong_topic"
    case tooVague      = "too_vague"
    case closeNotQuite = "close_but_not_quite"

    var label: String {
        switch self {
        case .tooDramatic:   return "too dramatic"
        case .wrongTopic:    return "wrong topic"
        case .tooVague:      return "too vague"
        case .closeNotQuite: return "close, but not quite"
        }
    }
}

// MARK: - Safety level

/// Self-reported distress level from the generator, mirrored from the server.
/// `none` is the only level allowed to surface a read; anything else is held
/// back client-side as a belt-and-suspenders gate on top of the server guard.
enum ReadSafetyLevel: String, Codable {
    case none
    case mildDistress = "mild_distress"
    case highDistress = "high_distress"

    var isSurfaceable: Bool { self == .none }
}

// MARK: - DailyRead

struct DailyRead: Identifiable, Codable {

    /// Firestore doc id. For a daily read this is the local date string
    /// (`yyyy-MM-dd`) so the per-user-per-day uniqueness constraint is structural.
    let id: String
    let userId: String
    /// The local calendar day this read belongs to (midnight, user-local).
    let localDate: Date

    // ── Core typography contracts ───────────────────────────────────────
    let readText: String
    /// 2–4 short string clips lifted from the user's own words / contexts.
    let receiptChips: [String]
    let replyPrompt: String
    /// Clean, context-free line safe for an external share card.
    let shareSafeText: String
    /// Push-notification body (≤ 45 chars). Written by the server generator; the
    /// curiosity-gap line, never the read itself. Default-safe for local reads.
    let notificationCopy: String

    // ── State parameters ────────────────────────────────────────────────
    let tone: ReadTone
    let sharpnessLevel: ReadSharpness
    let safetyLevel: ReadSafetyLevel
    let confidence: Double
    let shouldShow: Bool
    let doNotShowReason: String?

    // ── Dependency tracing ──────────────────────────────────────────────
    let sourceEntryIds: [String]
    let sourcePatternIds: [String]
    let sourceRiverMarkIds: [String]

    // ── User tracking (mutated by feedback loops) ───────────────────────
    var userFeedback: ReadFeedback?
    var detailedFeedbackCode: ReadRejectionCode?

    // ── Telemetry ───────────────────────────────────────────────────────
    let modelProvider: String
    let modelName: String
    let promptVersion: String
    let createdAt: Date

    // MARK: - Computed

    /// True when this read is allowed onto the Home screen.
    var isSurfaceable: Bool {
        shouldShow && safetyLevel.isSurfaceable && !readText.isEmpty
    }

    // MARK: - Local date key helper

    /// `yyyy-MM-dd` for the given date in the current calendar — the doc id.
    static func dateKey(for date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: - Designated init (local engine / generator output)

    init(
        id: String? = nil,
        userId: String,
        localDate: Date = Date(),
        readText: String,
        receiptChips: [String],
        replyPrompt: String,
        shareSafeText: String,
        notificationCopy: String = "",
        tone: ReadTone,
        sharpnessLevel: ReadSharpness,
        safetyLevel: ReadSafetyLevel = .none,
        confidence: Double,
        shouldShow: Bool = true,
        doNotShowReason: String? = nil,
        sourceEntryIds: [String] = [],
        sourcePatternIds: [String] = [],
        sourceRiverMarkIds: [String] = [],
        userFeedback: ReadFeedback? = nil,
        detailedFeedbackCode: ReadRejectionCode? = nil,
        modelProvider: String,
        modelName: String,
        promptVersion: String
    ) {
        self.id                   = id ?? DailyRead.dateKey(for: localDate)
        self.userId               = userId
        self.localDate            = Calendar.current.startOfDay(for: localDate)
        self.readText             = readText
        self.receiptChips         = receiptChips
        self.replyPrompt          = replyPrompt
        self.shareSafeText        = shareSafeText
        self.notificationCopy     = notificationCopy
        self.tone                 = tone
        self.sharpnessLevel       = sharpnessLevel
        self.safetyLevel          = safetyLevel
        self.confidence           = confidence
        self.shouldShow           = shouldShow
        self.doNotShowReason      = doNotShowReason
        self.sourceEntryIds       = sourceEntryIds
        self.sourcePatternIds     = sourcePatternIds
        self.sourceRiverMarkIds   = sourceRiverMarkIds
        self.userFeedback         = userFeedback
        self.detailedFeedbackCode = detailedFeedbackCode
        self.modelProvider        = modelProvider
        self.modelName            = modelName
        self.promptVersion        = promptVersion
        self.createdAt            = Date()
    }

    // MARK: - Firestore deserialisation

    init?(from data: [String: Any]) {
        guard
            let id        = data["id"]        as? String,
            let userId    = data["userId"]    as? String,
            let localDate = (data["localDate"] as? Timestamp)?.dateValue(),
            let readText  = data["readText"]  as? String,
            let replyPrompt = data["replyPrompt"] as? String,
            let toneRaw   = data["tone"]      as? String,
            let tone      = ReadTone(rawValue: toneRaw),
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        else { return nil }

        self.id            = id
        self.userId        = userId
        self.localDate     = localDate
        self.readText      = readText
        self.receiptChips  = data["receiptChips"] as? [String] ?? []
        self.replyPrompt   = replyPrompt
        self.shareSafeText = data["shareSafeText"] as? String ?? readText
        self.notificationCopy = data["notificationCopy"] as? String ?? ""
        self.tone          = tone
        self.sharpnessLevel = ReadSharpness(rawValue: data["sharpnessLevel"] as? String ?? "") ?? .direct
        self.safetyLevel    = ReadSafetyLevel(rawValue: data["safetyLevel"] as? String ?? "") ?? .none
        self.confidence     = data["confidence"] as? Double ?? 0
        self.shouldShow     = data["shouldShow"] as? Bool ?? true
        self.doNotShowReason = data["doNotShowReason"] as? String
        self.sourceEntryIds     = data["sourceEntryIds"]     as? [String] ?? []
        self.sourcePatternIds   = data["sourcePatternIds"]   as? [String] ?? []
        self.sourceRiverMarkIds = data["sourceRiverMarkIds"] as? [String] ?? []
        self.userFeedback   = (data["userFeedback"] as? String).flatMap(ReadFeedback.init(rawValue:))
        self.detailedFeedbackCode = (data["detailedFeedbackCode"] as? String).flatMap(ReadRejectionCode.init(rawValue:))
        self.modelProvider  = data["modelProvider"] as? String ?? "local"
        self.modelName      = data["modelName"]     as? String ?? "local-engine"
        self.promptVersion  = data["promptVersion"] as? String ?? "unknown"
        self.createdAt      = createdAt
    }

    // MARK: - Firestore serialisation

    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "id":                 id,
            "userId":             userId,
            "localDate":          Timestamp(date: localDate),
            "readText":           readText,
            "receiptChips":       receiptChips,
            "replyPrompt":        replyPrompt,
            "shareSafeText":      shareSafeText,
            "notificationCopy":   notificationCopy,
            "tone":               tone.rawValue,
            "sharpnessLevel":     sharpnessLevel.rawValue,
            "safetyLevel":        safetyLevel.rawValue,
            "confidence":         confidence,
            "shouldShow":         shouldShow,
            "sourceEntryIds":     sourceEntryIds,
            "sourcePatternIds":   sourcePatternIds,
            "sourceRiverMarkIds": sourceRiverMarkIds,
            "modelProvider":      modelProvider,
            "modelName":          modelName,
            "promptVersion":      promptVersion,
            "createdAt":          Timestamp(date: createdAt)
        ]
        if let r = doNotShowReason      { data["doNotShowReason"]      = r }
        if let f = userFeedback         { data["userFeedback"]         = f.rawValue }
        if let c = detailedFeedbackCode { data["detailedFeedbackCode"] = c.rawValue }
        return data
    }
}
