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

    // MARK: - Persist hypothesis
    //
    // `saveHypothesis` was DELETED (Mirror v3). It had no call sites — the
    // server has been the sole writer of `patternHypotheses` since mining
    // moved server-side — and firestore.rules now enforces that: the client
    // may only patch `userStatus` / `status` / the shown+responded timestamps.
    // A general-purpose full-document writer sitting here unused was a
    // landmine: the next caller would have got a silent permission failure,
    // and fire-and-forget writes have no error path to notice it in.

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
}
