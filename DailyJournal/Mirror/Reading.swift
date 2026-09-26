//
//  Reading.swift
//  DailyJournal
//
//  Today's one thing — `users/{uid}/readings/{yyyy-MM-dd}`
//  (mirror-v3-prd-2026-09-10.md §5.2).
//
//  One line, one receipt, two taps. The line is either a model sentence that
//  passed the §6 copy contract, or — far more often, and by design — the
//  deterministic observation itself. Silence is a valid outcome, not a failure:
//  a surface that always has something to say is one that is making things up.
//
//  Read-only on the client except for three feedback fields; see
//  DerivedService.recordReadingFeedback and firestore.rules.
//

import Foundation
import FirebaseFirestore

// MARK: - Supporting types

struct ObservationQuote: Identifiable {
    let text: String
    let entryId: String?
    let date: String?
    var id: String { "\(date ?? "")-\(text.prefix(24))" }

    init(text: String, entryId: String?, date: String?) {
        self.text = text; self.entryId = entryId; self.date = date
    }

    init?(from data: [String: Any]) {
        guard let text = data["text"] as? String, !text.isEmpty else { return nil }
        self.text = text
        self.entryId = data["entryId"] as? String
        self.date = data["date"] as? String
    }
}

struct ReadingReceipt {
    let quote: String
    let entryId: String?
    let date: String?
    /// "2 days ago" — computed server-side against the user's own local
    /// calendar, so it can't disagree with the dates in the proof sheet.
    let relativeLabel: String?

    init?(from data: [String: Any]) {
        guard let quote = data["quote"] as? String, !quote.isEmpty else { return nil }
        self.quote = quote
        self.entryId = data["entryId"] as? String
        self.date = data["date"] as? String
        self.relativeLabel = data["relativeLabel"] as? String
    }
}

/// The numbers behind the line — what "more…" opens.
struct ReadingProof {
    let n: Int
    let m: Int
    let k: Int
    let j: Int
    let lift: Double
    let type: String
    let quotes: [ObservationQuote]
    let exceptionDays: [String]
    let entryIds: [String]
    let contrastEntryIds: [String]
    let pct: Int?
    let band: String?
    let thenQuote: ObservationQuote?
    let nowQuote: ObservationQuote?
    let daysApart: Int?
    let before: Int?
    let after: Int?
    let runLength: Int?

    init(from data: [String: Any]) {
        self.n = data["n"] as? Int ?? 0
        self.m = data["m"] as? Int ?? 0
        self.k = data["k"] as? Int ?? 0
        self.j = data["j"] as? Int ?? 0
        self.lift = data["lift"] as? Double ?? 0
        self.type = data["type"] as? String ?? "cooccurrence"
        self.quotes = (data["quotes"] as? [[String: Any]] ?? []).compactMap { ObservationQuote(from: $0) }
        self.exceptionDays = ((data["exception"] as? [String: Any])?["days"] as? [String]) ?? []
        self.entryIds = data["entryIds"] as? [String] ?? []
        self.contrastEntryIds = data["contrastEntryIds"] as? [String] ?? []
        self.pct = data["pct"] as? Int
        self.band = data["band"] as? String
        self.thenQuote = (data["thenQuote"] as? [String: Any]).flatMap { ObservationQuote(from: $0) }
        self.nowQuote = (data["nowQuote"] as? [String: Any]).flatMap { ObservationQuote(from: $0) }
        self.daysApart = data["daysApart"] as? Int
        self.before = data["before"] as? Int
        self.after = data["after"] as? Int
        self.runLength = data["runLength"] as? Int
    }

    /// The two-row comparison at the top of the proof sheet: "3 of 3 'lucky'
    /// entries after 8pm" vs "1 of 4 other entries". Only meaningful for the
    /// comparison types — a callback or a delta shows its own layout instead.
    var hasComparison: Bool {
        ["cooccurrence", "exception"].contains(type) && n > 0
    }
}

// MARK: - Reading

struct Reading {
    let date: String
    let userId: String
    let sourceId: String?
    let sourceType: String?
    /// The model's sentence when one passed lint, otherwise the observation's
    /// own deterministic sentence. Never empty on a non-silent day.
    let line: String
    /// The observation's sentence, ALWAYS stored — §6's rule is that a failed
    /// line is not softened and retried, it is replaced by this.
    let templateText: String?
    let move: String?
    let question: String?
    let lintPassed: Bool
    let lintReason: String?
    let receipt: ReadingReceipt?
    let proof: ReadingProof?
    let silence: Bool
    let reason: String?
    let unlockHint: String?
    let userStatus: String
    let computedAt: Date
    /// Mirror v3.1 (mirror-v3.1-person-model-2026-09-10.md §7-9). One of
    /// SIGNATURE / BECAUSE / SAYDO / EXCEPTION when `source.kind ==
    /// "personModel"`; nil for a v3.0 observation-only reading, which still
    /// renders exactly as before.
    let shape: String?

    init?(from data: [String: Any]) {
        guard let date = data["date"] as? String else { return nil }
        self.date = date
        self.userId = data["userId"] as? String ?? ""
        let source = data["source"] as? [String: Any]
        self.sourceId = source?["id"] as? String
        self.sourceType = source?["type"] as? String
        self.line = data["line"] as? String ?? ""
        self.templateText = data["templateText"] as? String
        self.move = data["move"] as? String
        self.question = data["question"] as? String
        self.lintPassed = data["lintPassed"] as? Bool ?? false
        self.lintReason = data["lintReason"] as? String
        self.receipt = (data["receipt"] as? [String: Any]).flatMap { ReadingReceipt(from: $0) }
        self.proof = (data["proof"] as? [String: Any]).map { ReadingProof(from: $0) }
        self.silence = data["silence"] as? Bool ?? false
        self.reason = data["reason"] as? String
        self.unlockHint = data["unlockHint"] as? String
        self.userStatus = data["userStatus"] as? String ?? "unrated"
        self.computedAt = (data["computedAt"] as? Timestamp)?.dateValue() ?? Date()
        self.shape = data["shape"] as? String
    }

    var isConfirmed: Bool { userStatus == "this_is_me" }
    var isHuh: Bool { userStatus == "huh" }

    /// The headline for a quiet day. Never apologetic — a silent day is the
    /// app being honest, and the copy should sound like it means it.
    var silenceHeadline: String {
        switch reason {
        case "no_analyses":     return "Nothing to read back yet."
        case "no_observations": return "Nothing new to show today."
        case "below_threshold": return "Nothing sharp enough to show today."
        default:                return "Nothing new to show today."
        }
    }
}

// MARK: - Feedback

/// §9's three reactions on Today. `huh` is new in v3.1 — "new to me" — and is
/// the one the "Didn't know that" metric (target >= 25%) is built from; it is
/// weighted below `thisIsMe` (the strongest signal the model can get) but is
/// not a rejection, so it never touches `notQuiteCount`.
enum ReadingFeedback: String {
    case thisIsMe = "this_is_me"
    case huh      = "huh"
    case almost   = "almost"
}

/// Why it missed — this is what makes "Not quite" teach the app something
/// instead of just registering a complaint. Only `.tooMuch` lowers sharpness.
/// §9: "'Not quite' -> three chips: Wrong (retire), Half (weaken + ask what's
/// missing, one line), Too much (StylePreferences.sharpness -1)."
enum ReadingMissReason: String, CaseIterable, Identifiable {
    case tooMuch = "too_much"
    case wrong   = "wrong"
    case half    = "half"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tooMuch: return "Too much"
        case .wrong:   return "Wrong"
        case .half:    return "Half"
        }
    }
}
