// MirrorGraphService.swift
// DailyJournal
//
// Signal accumulator for the Mirror Engine.
// Reads PatternHypothesis docs from Firestore, applies MirrorScore ranking,
// and provides the top candidate for daily mirror card generation.
//
// Phase 2 note: a full Firestore MirrorGraph subcollection is future work.
// For now, hypotheses live in users/{uid}/patternHypotheses and are loaded
// and scored here on demand.
//
// Firestore paths:
//   users/{uid}/patternHypotheses/{hypothesisId}
//   users/{uid}/entryAnalyses/{entryId}

import Foundation
import FirebaseFirestore

// MARK: - MirrorShownRecord
//
// One doc per local day at `users/{uid}/mirrorShown/{yyyy-MM-dd}` — the
// client's own record of what was actually DISPLAYED on Today's Mirror.
// Distinct from `patternHypotheses/{id}.shownAt`, which only tracks the
// hypothesis: the server writes up to MIRROR_DECK_SIZE (3) cards a night,
// but at most one is ever shown, and only the client knows which. Backs the
// 14-day novelty gate (rosebud-teardown-mirror-redesign-2026-09-09.md §3.8).

struct MirrorShownRecord {
    let hypothesisId: String
    let line: String
    let contentWords: [String]
    let evidenceEntryIds: [String]
    let shownAt: Date

    init(hypothesisId: String, line: String, evidenceEntryIds: [String], shownAt: Date = Date()) {
        self.hypothesisId     = hypothesisId
        self.line              = line
        self.contentWords      = Array(MirrorText.contentWords(line))
        self.evidenceEntryIds  = evidenceEntryIds
        self.shownAt            = shownAt
    }

    init?(from data: [String: Any]) {
        guard
            let hypothesisId = data["hypothesisId"] as? String,
            let line          = data["line"]          as? String,
            let shownAt       = (data["shownAt"] as? Timestamp)?.dateValue()
        else { return nil }
        self.hypothesisId    = hypothesisId
        self.line             = line
        self.contentWords     = data["contentWords"]     as? [String] ?? []
        self.evidenceEntryIds = data["evidenceEntryIds"] as? [String] ?? []
        self.shownAt           = shownAt
    }

    func toFirestoreData() -> [String: Any] {
        [
            "hypothesisId":    hypothesisId,
            "line":            line,
            "contentWords":    contentWords,
            "evidenceEntryIds": evidenceEntryIds,
            "shownAt":         Timestamp(date: shownAt)
        ]
    }

    /// `yyyy-MM-dd` in the current calendar/locale — one doc per local day.
    static func dateKey(for date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

@MainActor
final class MirrorGraphService: ObservableObject {

    static let shared = MirrorGraphService()
    private init() {}

    // MARK: - Published state

    @Published private(set) var hypotheses: [PatternHypothesis] = []
    @Published private(set) var isLoading = false

    // MARK: - Load hypotheses

    /// Fetches the top-20 surfaceable hypotheses for this user, ordered by salienceScore.
    ///
    /// Cache-first (`FirestoreCacheFirst`) — this ran a bare `.getDocuments()` (a
    /// server round-trip) on every Mirror load, including the second visit in the
    /// same session where the answer hadn't changed.
    func loadHypotheses(for userId: String) async {
        isLoading = true
        defer { isLoading = false }

        guard let snapshot = try? await FirestoreCacheFirst.documents(
            Firestore.firestore()
                .collection("users").document(userId)
                .collection("patternHypotheses")
                .order(by: "salienceScore", descending: true)
                .limit(to: 20),
            key: "mirrorHypotheses.\(userId)"
        ) else { return }

        hypotheses = snapshot.documents
            .compactMap { PatternHypothesis(from: $0.data()) }
            .filter { $0.isSurfaceable }
    }

    // MARK: - Ranked candidates for today's card

    /// The top `limit` hypotheses whose MirrorScore clears the 0.5 threshold,
    /// highest first. `loadOrGenerateMirrorCard` walks this list rather than
    /// taking just the argmax — the server-generated deck holds up to
    /// MIRROR_DECK_SIZE (3) cards, and a suppressed or not-yet-generated #1
    /// should not mean "no card today" when #2 or #3 has one.
    ///
    /// Scores once per hypothesis rather than the old `max { }` comparator,
    /// which recomputed `MirrorScore.score` (and re-read `Date()`) on every
    /// pairwise comparison.
    func rankedCandidates(limit: Int = 3) -> [PatternHypothesis] {
        hypotheses
            .map { (h: $0, score: MirrorScore.score(for: $0)) }
            .filter { $0.score > 0.5 }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.h)
    }

    // MARK: - Persist hypothesis

    /// Fire-and-forget write of a hypothesis to Firestore.
    ///
    /// `merge: true` is load-bearing. `PatternHypothesis.toFirestoreData()` does
    /// not carry the fields the nightly server pipeline owns —
    /// `counterEvidenceEntryIds`, `disconfirmation`, `lifecycle`,
    /// `evidenceEntryIdsAllTime`, `lastEvidenceAt`, `obviousRisk`,
    /// `actionOutcome`, `absenceFact`. A full overwrite therefore erased the
    /// entire audit trail and evidence history for any hypothesis the client
    /// touched, which is exactly the data that makes the profile trustworthy.
    func saveHypothesis(_ h: PatternHypothesis, userId: String) {
        Firestore.firestore()
            .collection("users").document(userId)
            .collection("patternHypotheses").document(h.id)
            .setData(h.toFirestoreData(), merge: true) { _ in }
    }

    // MARK: - Mark shown

    /// Records the timestamp when a hypothesis was surfaced to the user, AND
    /// (when a line/evidence are given) writes today's `mirrorShown` record —
    /// the history the novelty gate reads. `line`/`evidenceEntryIds` are
    /// optional so existing callers that only care about `shownAt` on the
    /// hypothesis keep working unchanged.
    func markShown(_ id: String, userId: String, line: String? = nil, evidenceEntryIds: [String] = []) {
        let now = Date()

        Firestore.firestore()
            .collection("users").document(userId)
            .collection("patternHypotheses").document(id)
            .updateData(["shownAt": Timestamp(date: now)]) { _ in }

        // One doc per local day — `set` (not `merge`) is deliberate: if the
        // tab is reopened later the same day, this SHOULD overwrite with
        // whichever hypothesis was actually shown, not accumulate.
        if let line {
            let record = MirrorShownRecord(hypothesisId: id, line: line, evidenceEntryIds: evidenceEntryIds, shownAt: now)
            Firestore.firestore()
                .collection("users").document(userId)
                .collection("mirrorShown").document(MirrorShownRecord.dateKey(for: now))
                .setData(record.toFirestoreData()) { _ in }
        }

        if let idx = hypotheses.firstIndex(where: { $0.id == id }) {
            // PatternHypothesis is a struct — rebuild with updated shownAt.
            let original = hypotheses[idx]
            hypotheses[idx] = PatternHypothesis(
                id:                  original.id,
                userId:              original.userId,
                archetype:           original.archetype,
                evidence:            original.evidence,
                salienceScore:       original.salienceScore,
                status:              original.status,
                createdAt:           original.createdAt,
                shownAt:             now,
                respondedAt:         original.respondedAt,
                patternType:         original.patternType,
                userFacingTitle:     original.userFacingTitle,
                coreHypothesis:      original.coreHypothesis,
                protection:          original.protection,
                cost:                original.cost,
                counterEvidence:     original.counterEvidence,
                noveltyScore:        original.noveltyScore,
                emotionalWeight:     original.emotionalWeight,
                actionabilityScore:  original.actionabilityScore,
                shameRisk:           original.shameRisk,
                diagnosticRisk:      original.diagnosticRisk,
                tinyExperiment:      original.tinyExperiment,
                callbackQuestion:    original.callbackQuestion,
                firstSeenAt:         original.firstSeenAt,
                // NOT `+ 1`. `timesSeen` now means "distinct entries supporting
                // this", and the Mirror renders it as "N entries". Bumping it on
                // every surfacing inflated the evidence count purely because the
                // user looked at the card — the same class of lie as the old
                // server behaviour of counting nightly cron runs. Showing a card
                // is not evidence.
                timesSeen:           original.timesSeen,
                scope:               original.scope,
                stability:           original.stability
            )
        }
    }

    // MARK: - Record feedback

    /// Persists user feedback for a hypothesis and updates the local copy.
    func recordFeedback(
        hypothesisId: String,
        userId: String,
        status: PatternCallbackStatus
    ) {
        let now = Date()

        Firestore.firestore()
            .collection("users").document(userId)
            .collection("patternHypotheses").document(hypothesisId)
            .updateData([
                "status":      status.rawValue,
                "respondedAt": Timestamp(date: now)
            ]) { _ in }

        if let idx = hypotheses.firstIndex(where: { $0.id == hypothesisId }) {
            let original = hypotheses[idx]
            hypotheses[idx] = PatternHypothesis(
                id:                  original.id,
                userId:              original.userId,
                archetype:           original.archetype,
                evidence:            original.evidence,
                salienceScore:       original.salienceScore,
                status:              status,
                createdAt:           original.createdAt,
                shownAt:             original.shownAt,
                respondedAt:         now,
                patternType:         original.patternType,
                userFacingTitle:     original.userFacingTitle,
                coreHypothesis:      original.coreHypothesis,
                protection:          original.protection,
                cost:                original.cost,
                counterEvidence:     original.counterEvidence,
                noveltyScore:        original.noveltyScore,
                emotionalWeight:     original.emotionalWeight,
                actionabilityScore:  original.actionabilityScore,
                shameRisk:           original.shameRisk,
                diagnosticRisk:      original.diagnosticRisk,
                tinyExperiment:      original.tinyExperiment,
                callbackQuestion:    original.callbackQuestion,
                firstSeenAt:         original.firstSeenAt,
                timesSeen:           original.timesSeen,
                scope:               original.scope,
                stability:           original.stability
            )
        }
    }

    // MARK: - Load recent analyses

    /// Fetches the most recent entry analyses for this user.
    /// Cache-first — same rationale as `loadHypotheses` above. The key is scoped by
    /// `limit` too, since a cached answer for one page size isn't a valid answer
    /// for a different one.
    func loadRecentAnalyses(for userId: String, limit: Int = 10) async -> [EntryAnalysis] {
        guard let snapshot = try? await FirestoreCacheFirst.documents(
            Firestore.firestore()
                .collection("users").document(userId)
                .collection("entryAnalyses")
                .order(by: "createdAt", descending: true)
                .limit(to: limit),
            key: "mirrorRecentAnalyses.\(userId).\(limit)"
        ) else { return [] }

        return snapshot.documents.compactMap { EntryAnalysis(from: $0.data()) }
    }

    // MARK: - Recent shown records (novelty gate history)

    /// The last `days` `mirrorShown` records, most recent first. Cache-first,
    /// same rationale as the other reads on this service.
    func recentShownRecords(for userId: String, days: Int = 14) async -> [MirrorShownRecord] {
        guard let snapshot = try? await FirestoreCacheFirst.documents(
            Firestore.firestore()
                .collection("users").document(userId)
                .collection("mirrorShown")
                .order(by: "shownAt", descending: true)
                .limit(to: days),
            key: "mirrorShown.\(userId).\(days)"
        ) else { return [] }

        return snapshot.documents.compactMap { MirrorShownRecord(from: $0.data()) }
    }
}
