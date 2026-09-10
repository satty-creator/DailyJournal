//
//  PersonModel.swift
//  DailyJournal
//
//  Mirror v3.1 — the Person Model (mirror-v3.1-person-model-2026-09-10.md §4).
//  `patternHypotheses`/`SelfModel`'s successor: a CBT case formulation held
//  as falsifiable hypotheses in Kuyken's three levels — descriptive,
//  cross-sectional (signatures, rules, needs, loops, distortions, people),
//  longitudinal (core beliefs, values, strengths) — plus the open questions
//  that drive tomorrow's journaling prompt.
//
//  `users/{uid}/personModel/{itemId}` — one doc per item, server-written by
//  Prompt F. The client may patch only `userStatus`/`shownAt`/
//  `notQuiteCount`/`respondedAt` (firestore.rules).
//  `users/{uid}/derived/personModel` — the non-correctable aggregate: needs,
//  openHypotheses, the next question.
//
//  Manual dict decoding, matching every other model in this folder
//  (EntryAnalysis, SelfModel, Reading) — no Codable/FirestoreSwift anywhere
//  in Mirror/.
//

import Foundation
import FirebaseFirestore

// MARK: - PersonModelItem

/// One hypothesis. Every kind shares the envelope below; the kind-specific
/// fields (if/then/notWhen for a signature, rule for a rule, and so on) are
/// stored optionally on the same doc rather than as a Swift enum payload,
/// so a kind this client doesn't yet render still decodes and can still be
/// listed generically.
struct PersonModelItem: Identifiable {
    let id: String
    let kind: String
    let level: Int
    /// Server-computed — (timesSeen, disconfirmationVerdict, userStatus)
    /// ONLY, never a number the model returned. "hunch" | "maybe" | "likely".
    let confidence: String
    let userStatus: String
    let timesSeen: Int
    let evidenceEntryIds: [String]
    let counterEvidenceEntryIds: [String]
    let firstSeenAt: Date?
    let lastEvidenceAt: Date?
    let testQuestion: String?
    let status: String

    // Kind-specific, all optional.
    let ifClause: String?
    let thenClause: String?
    let notWhen: String?
    let contexts: [String]
    let crossContext: Bool
    let rule: String?
    let move: String?
    let relief: String?
    let cost: String?
    let plainName: String?
    let quote: String?
    let name: String?
    let roleTheyTake: String?
    let exception: String?
    let capacity: String?
    let shownWhen: String?

    init?(id: String, from data: [String: Any]) {
        guard let kind = data["kind"] as? String else { return nil }
        self.id = id
        self.kind = kind
        self.level = data["level"] as? Int ?? 2
        self.confidence = data["confidence"] as? String ?? "hunch"
        self.userStatus = data["userStatus"] as? String ?? "unrated"
        self.timesSeen = data["timesSeen"] as? Int ?? 0
        self.evidenceEntryIds = data["evidenceEntryIds"] as? [String] ?? []
        self.counterEvidenceEntryIds = data["counterEvidenceEntryIds"] as? [String] ?? []
        self.firstSeenAt = (data["firstSeenAt"] as? Timestamp)?.dateValue()
        self.lastEvidenceAt = (data["lastEvidenceAt"] as? Timestamp)?.dateValue()
        self.testQuestion = data["testQuestion"] as? String
        self.status = data["status"] as? String ?? "active"

        self.ifClause = data["if"] as? String
        self.thenClause = data["then"] as? String
        self.notWhen = data["notWhen"] as? String
        self.contexts = data["contexts"] as? [String] ?? []
        self.crossContext = data["crossContext"] as? Bool ?? false
        self.rule = data["rule"] as? String
        self.move = data["move"] as? String
        self.relief = data["relief"] as? String
        self.cost = data["cost"] as? String
        self.plainName = data["plainName"] as? String
        self.quote = data["quote"] as? String
        self.name = data["name"] as? String
        self.roleTheyTake = data["roleTheyTake"] as? String
        self.exception = data["exception"] as? String
        self.capacity = data["capacity"] as? String
        self.shownWhen = data["shownWhen"] as? String
    }

    var isActive: Bool { status != "retired" && status != "merged" }
    var isConfirmed: Bool { userStatus == "this_is_me" }

    /// The single line for "WHAT SPILR THINKS IT KNOWS" — an if-then for a
    /// signature, the plain text for everything else. PARITY:
    /// functions/lib/personModel.js#displayTitleFor.
    var displayTitle: String {
        switch kind {
        case "signature":
            let base = "\(ifClause ?? "") → \(thenClause ?? "")".trimmingCharacters(in: .whitespaces)
            return base.isEmpty ? "signature" : base
        case "rule": return rule ?? "a rule"
        case "loop": return move ?? "a loop"
        case "distortion": return plainName ?? "a thinking pattern"
        case "person": return name.map { "With \($0)" } ?? "a person"
        case "coreBelief": return "a core belief"
        case "value": return "a value"
        case "strength": return capacity ?? "a strength"
        default: return displayTitleFallback
        }
    }
    private var displayTitleFallback: String { kind }

    /// "likely · 6 entries" / "hunch · from 2 thoughts" — one confidence
    /// word, once, per §9's design note that collaborative empiricism
    /// requires the user to see how sure the app is, but only ever once.
    var metaLine: String {
        let count = timesSeen == 1 ? "1 entry" : "\(timesSeen) entries"
        return "\(confidence) · \(count)"
    }

    /// The contrast clause a signature row shows under its title — "not when
    /// someone's there" — the thing that makes the claim checkable.
    var contrastLine: String? {
        guard kind == "signature", let notWhen, !notWhen.isEmpty else { return nil }
        return "not when \(notWhen)"
    }
}

// MARK: - OpenHypothesis

/// "WHAT IT DOESN'T KNOW YET" — the open questions Prompt Q draws from.
struct OpenHypothesis: Identifiable {
    let id: String
    let hypothesis: String
    let wouldConfirm: String?
    let wouldReject: String?
    let testQuestion: String?
    let value: Double

    init?(from data: [String: Any]) {
        guard let id = data["id"] as? String,
              let hypothesis = data["hypothesis"] as? String, !hypothesis.isEmpty
        else { return nil }
        self.id = id
        self.hypothesis = hypothesis
        self.wouldConfirm = data["wouldConfirm"] as? String
        self.wouldReject = data["wouldReject"] as? String
        self.testQuestion = data["testQuestion"] as? String
        self.value = data["value"] as? Double ?? 0.5
    }
}

// MARK: - NextQuestion

/// Prompt Q's pick for tonight — feeds the "Answer tonight" affordance on
/// Today and (eventually) Mirror Seeds.
struct NextQuestion {
    let question: String
    let hypothesisId: String
    let seedLabel: String?
    let createdAt: Date?

    init?(from data: [String: Any]) {
        guard let question = data["question"] as? String, !question.isEmpty else { return nil }
        self.question = question
        self.hypothesisId = data["hypothesisId"] as? String ?? ""
        self.seedLabel = data["seedLabel"] as? String
        self.createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
    }
}

// MARK: - NeedsRead

/// SDT autonomy/competence/relatedness read from Prompt F, shown only when
/// lopsided (the model itself only fills `read` when one need is >= 70%).
struct NeedsRead {
    let read: String?

    init?(from data: [String: Any]) {
        self.read = data["read"] as? String
    }
}

// MARK: - PersonModelAggregate

/// `users/{uid}/derived/personModel` — server-only, no client write path.
struct PersonModelAggregate {
    let needs: NeedsRead?
    let openHypotheses: [OpenHypothesis]
    let nextQuestion: NextQuestion?
    let computedAt: Date?

    static let empty = PersonModelAggregate(needs: nil, openHypotheses: [], nextQuestion: nil, computedAt: nil)

    init(needs: NeedsRead?, openHypotheses: [OpenHypothesis], nextQuestion: NextQuestion?, computedAt: Date?) {
        self.needs = needs
        self.openHypotheses = openHypotheses
        self.nextQuestion = nextQuestion
        self.computedAt = computedAt
    }

    init?(from data: [String: Any]) {
        self.needs = (data["needs"] as? [String: Any]).flatMap { NeedsRead(from: $0) }
        self.openHypotheses = (data["openHypotheses"] as? [[String: Any]] ?? [])
            .compactMap { OpenHypothesis(from: $0) }
            .sorted { $0.value > $1.value }
        self.nextQuestion = (data["nextQuestion"] as? [String: Any]).flatMap { NextQuestion(from: $0) }
        self.computedAt = (data["computedAt"] as? Timestamp)?.dateValue()
    }
}
