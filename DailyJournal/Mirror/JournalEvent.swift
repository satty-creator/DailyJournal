// JournalEvent.swift
// DailyJournal
//
// A first-class, queryable episode — situation → move → outcome — promoted out
// of EntryAnalysis.episodes. Firestore path: users/{uid}/events/{id}
//
// WHY THIS EXISTS: Prompt A (mirror-extract-v1) already extracts episodes on
// every entry — the mine prompt calls them "the only place a real
// action→outcome claim can come from" — but they were only ever readable
// nested three levels deep inside `entryAnalyses[].episodes`, capped at 3 per
// analysis and consumed only by the mine/write prompts. Promoting them to
// their own collection is what lets a future retrieval pass (Ask, a richer
// prompt-context builder) cite a specific remembered moment instead of a
// word-frequency count. No new AI cost: this is a projection of data Prompt A
// already produced, not a new extraction.
//
// PRIVACY: same posture as `entryAnalyses` — plaintext, but never raw entry
// text. `situation`/`outcome`/etc. are the model's short paraphrase or a
// distinctive quoted phrase, the same kind of text `entryAnalyses` already
// stores unencrypted.

import Foundation
import FirebaseFirestore

struct JournalEvent: Identifiable {

    /// Deterministic: `"\(sourceEntryId)_\(episodeId)"`. `episodeId` alone
    /// ("ep1", "ep2", ...) is only unique WITHIN one entry's analysis — the
    /// model reuses those labels across entries — so the composite is what
    /// keeps this collection collision-free while staying idempotent: a
    /// content-hash cache hit on `analyzeEntry` re-promotes the SAME episodes
    /// under the SAME ids, which overwrites rather than duplicates.
    let id: String
    let userId: String
    let sourceEntryId: String
    let situation: String
    let emotions: [String]
    let bodySignals: [String]
    let protectiveStrategy: String?
    let need: String?
    let outcome: String?
    /// The source entry's `createdAt` — when this actually happened, not when
    /// it was extracted.
    let occurredAt: Date
    /// The parent analysis's `lifeDomains`, carried along for coarse filtering
    /// ("show me work-related moments") without a join back to `entryAnalyses`.
    let tags: [String]
    /// Deterministic 0–1 heuristic — see `JournalEvent.salience(for:)`. Not a
    /// model output: how "checkable" this episode is (does it have an outcome,
    /// a stated need) rather than how emotionally loaded it is.
    let salience: Double
    /// When this event doc was (last) written — distinct from `occurredAt`.
    let createdAt: Date

    // MARK: - Derive from an EntryAnalysis + one of its episodes

    init(from analysis: EntryAnalysis, episode: EpisodeFrame) {
        self.id                  = "\(analysis.entryId)_\(episode.episodeId)"
        self.userId              = analysis.userId
        self.sourceEntryId       = analysis.entryId
        self.situation           = episode.situation
        self.emotions            = episode.emotions
        self.bodySignals         = episode.bodySignals
        self.protectiveStrategy  = episode.protectiveStrategy
        self.need                = episode.need
        self.outcome             = episode.outcome
        self.occurredAt          = analysis.createdAt
        self.tags                = analysis.lifeDomains
        self.salience            = Self.salience(for: episode)
        self.createdAt           = Date()
    }

    /// Deterministic, no model call: an episode with a concrete outcome and a
    /// named need is more useful to cite later than a bare situation with
    /// neither — closer to "checkable against a specific entry" than to how
    /// intense it reads.
    static func salience(for episode: EpisodeFrame) -> Double {
        var score = 0.3
        if let outcome = episode.outcome, !outcome.isEmpty { score += 0.3 }
        if let need = episode.need, !need.isEmpty { score += 0.2 }
        if !episode.bodySignals.isEmpty { score += 0.1 }
        if let strategy = episode.protectiveStrategy, !strategy.isEmpty { score += 0.1 }
        return min(1.0, score)
    }

    // MARK: - Firestore deserialisation

    init?(from data: [String: Any]) {
        guard
            let id            = data["id"]            as? String,
            let userId        = data["userId"]        as? String,
            let sourceEntryId = data["sourceEntryId"]  as? String,
            let situation     = data["situation"]      as? String,
            let occurredAt    = (data["occurredAt"] as? Timestamp)?.dateValue(),
            let createdAt     = (data["createdAt"]  as? Timestamp)?.dateValue()
        else { return nil }

        self.id                 = id
        self.userId             = userId
        self.sourceEntryId      = sourceEntryId
        self.situation          = situation
        self.emotions           = data["emotions"]    as? [String] ?? []
        self.bodySignals        = data["bodySignals"] as? [String] ?? []
        self.protectiveStrategy = data["protectiveStrategy"] as? String
        self.need               = data["need"]   as? String
        self.outcome            = data["outcome"] as? String
        self.occurredAt         = occurredAt
        self.tags               = data["tags"] as? [String] ?? []
        self.salience           = data["salience"] as? Double ?? 0.3
        self.createdAt          = createdAt
    }

    // MARK: - Firestore serialisation

    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "id": id,
            "userId": userId,
            "sourceEntryId": sourceEntryId,
            "situation": situation,
            "emotions": emotions,
            "bodySignals": bodySignals,
            "tags": tags,
            "salience": salience,
            "occurredAt": Timestamp(date: occurredAt),
            "createdAt": Timestamp(date: createdAt)
        ]
        if let protectiveStrategy { data["protectiveStrategy"] = protectiveStrategy }
        if let need { data["need"] = need }
        if let outcome { data["outcome"] = outcome }
        return data
    }
}
