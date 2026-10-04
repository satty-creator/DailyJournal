// SelfModelService.swift
// DailyJournal
//
// Manages the user's SelfModel — their evolving, hypothesis-driven self-portrait.
// Handles load, save, per-hypothesis status updates, corrections, and deletion.
//
// Firestore paths:
//   users/{uid}/selfModel/current          — single SelfModel document
//   users/{uid}/profileCorrections/{id}    — user-submitted corrections
//   users/{uid}/lifeContext                — single LifeContext document

import Foundation
import FirebaseFirestore

@MainActor
final class SelfModelService: ObservableObject {

    static let shared = SelfModelService()
    private init() {}

    // MARK: - Published state

    @Published private(set) var selfModel: SelfModel = SelfModel.empty(userId: "")
    @Published private(set) var corrections: [ProfileCorrection] = []
    @Published private(set) var isLoading = false

    // MARK: - Load

    /// Fetches the current SelfModel and recent corrections from Firestore.
    func load(for userId: String) async {
        isLoading = true
        defer { isLoading = false }

        async let modelTask = loadSelfModel(userId: userId)
        async let correctionsTask = loadCorrections(userId: userId)

        let (model, fetchedCorrections) = await (modelTask, correctionsTask)

        if let model { selfModel = model }
        corrections = fetchedCorrections
    }

    private func loadSelfModel(userId: String) async -> SelfModel? {
        guard let snapshot = try? await FirestoreCacheFirst.document(
            Firestore.firestore()
                .collection("users").document(userId)
                .collection("selfModel").document("current"),
            key: "selfModel.\(userId)"
        ), let data = snapshot.data()
        else { return nil }

        return SelfModel(from: data)
    }

    private func loadCorrections(userId: String) async -> [ProfileCorrection] {
        guard let snapshot = try? await FirestoreCacheFirst.documents(
            Firestore.firestore()
                .collection("users").document(userId)
                .collection("profileCorrections")
                .order(by: "createdAt", descending: true)
                .limit(to: 20),
            key: "profileCorrections.\(userId)"
        ) else { return [] }

        return snapshot.documents.compactMap { ProfileCorrection(from: $0.data()) }
    }

    // MARK: - Save SelfModel

    /// Fire-and-forget write of the SelfModel to Firestore.
    ///
    /// SINGLE-WRITER GUARD. The nightly server pipeline and the client-side
    /// fallback assembler both write `selfModel/current`, with different
    /// bucketing rules, different maturity maths and different lifecycle
    /// thresholds. Whichever ran last used to win, so a user could open the
    /// Mirror tab and silently downgrade a fully-audited server model to a
    /// thin local approximation — losing confidence scores, disconfirmation
    /// verdicts, and the absences section in one tap.
    ///
    /// The server is authoritative. The client may only write a model it
    /// assembled itself when the server has never produced one.
    func save(_ model: SelfModel, userId: String) {
        if model.writtenBy != "server", selfModel.writtenBy == "server" {
            #if DEBUG
            print("SelfModelService: refusing to overwrite server model with client assembly")
            #endif
            return
        }
        Firestore.firestore()
            .collection("users").document(userId)
            .collection("selfModel").document("current")
            .setData(model.toFirestoreData()) { _ in }
    }

    // MARK: - Close a thread (the forget affordance)

    /// Marks a hypothesis as resolved so it is never surfaced or re-mined again.
    ///
    /// This is deliberately separate from "Hide" and from "Not me". Hiding says
    /// *not now*; "not me" says *you were wrong*; closing says **you were right
    /// and I'm done with it**. Without this third option, the only way to stop
    /// hearing about something you have genuinely moved past is to tell the app
    /// it was mistaken — which corrupts the very corrections that are supposed
    /// to be ground truth.
    ///
    /// Writes straight to the hypothesis doc so the nightly miner honours it
    /// even before the next client load.
    func closeHypothesis(id: String, userId: String) {
        Firestore.firestore()
            .collection("users").document(userId)
            .collection("patternHypotheses").document(id)
            .setData([
                "status": PatternCallbackStatus.closed.rawValue,
                "salienceScore": 0,
                "closedAt": Timestamp(date: Date()),
                // `lastEvidenceAt` is what the nightly job sorts and decays on.
                // Client-written hypothesis docs don't otherwise carry it, and a
                // doc without it can slip outside the server's working window —
                // where it can neither be matched nor retired, so a thread the
                // user closed could be re-minted as new and resurface.
                "lastEvidenceAt": Timestamp(date: Date())
            ], merge: true) { _ in }

        // Retire it locally too, so the section it lives in updates immediately
        // rather than waiting for the next nightly run.
        var updated = selfModel
        if applyRetired(id: id, to: &updated) {
            updated.updatedAt = Date()
            selfModel = updated
            save(updated, userId: userId)
        }
    }

    // MARK: - Submit correction

    /// Persists a user-submitted correction and appends it to the local array.
    func submitCorrection(_ correction: ProfileCorrection, userId: String) {
        Firestore.firestore()
            .collection("users").document(userId)
            .collection("profileCorrections").document(correction.id)
            .setData(correction.toFirestoreData()) { _ in }

        corrections.insert(correction, at: 0)
    }

    // MARK: - Mark hypothesis user status

    /// Updates the userStatus on any hypothesis across all sections of the SelfModel
    /// and writes the updated model back to Firestore.
    func markHypothesis(id: String, userStatus: UserHypothesisStatus, userId: String) {
        // Write to the HYPOTHESIS doc as well as the assembled model. The nightly
        // miner reads `userStatus` off patternHypotheses to derive lifecycle,
        // confidence and decay exemption — a confirmation that only landed in
        // selfModel/current would be silently overwritten by the next run, so the
        // user would confirm something and watch it revert.
        Firestore.firestore()
            .collection("users").document(userId)
            .collection("patternHypotheses").document(id)
            .setData([
                "userStatus": userStatus.rawValue,
                "respondedAt": Timestamp(date: Date())
            ], merge: true) { _ in }

        var updated = selfModel
        if applyUserStatus(id: id, status: userStatus, to: &updated) {
            updated.updatedAt = Date()
            selfModel = updated
            save(updated, userId: userId)
        }
    }

    // MARK: - Hide hypothesis

    /// Sets the stability to .retired for the hypothesis with the given id,
    /// removing it from active surfacing, and writes back to Firestore.
    func hideHypothesis(id: String, userId: String) {
        // Write `stability: retired` straight to the hypothesis doc, exactly like
        // closeHypothesis/markHypothesis. The nightly miner (and the server's
        // profile assembly) reads `stability` off patternHypotheses to decide
        // what reaches the profile — a hide that only landed in selfModel/current
        // would be silently overwritten on the next run, so the user would hide
        // something and watch it come back. `lastEvidenceAt` keeps the doc inside
        // the server's working window so it can be honoured rather than re-minted.
        Firestore.firestore()
            .collection("users").document(userId)
            .collection("patternHypotheses").document(id)
            .setData([
                "stability": HypothesisStability.retired.rawValue,
                "lastEvidenceAt": Timestamp(date: Date())
            ], merge: true) { _ in }

        var updated = selfModel
        if applyRetired(id: id, to: &updated) {
            updated.updatedAt = Date()
            selfModel = updated
            save(updated, userId: userId)
        }
    }

    // MARK: - Delete model

    /// Hard-deletes the user's SelfModel and all associated corrections from Firestore,
    /// then resets local state.
    func deleteModel(userId: String) {
        // Delete the self model document.
        Firestore.firestore()
            .collection("users").document(userId)
            .collection("selfModel").document("current")
            .delete()

        // Batch-delete all profileCorrections.
        Task.detached(priority: .background) {
            guard let snapshot = try? await Firestore.firestore()
                .collection("users").document(userId)
                .collection("profileCorrections")
                .getDocuments()
            else { return }

            let batch = Firestore.firestore().batch()
            for doc in snapshot.documents {
                batch.deleteDocument(doc.reference)
            }
            try? await batch.commit()
        }

        // Reset local state.
        selfModel = SelfModel.empty(userId: userId)
        corrections = []
    }

    // MARK: - Deterministic assembly from hypotheses (Tier 1)

    /// Assembles or updates the SelfModel deterministically from existing PatternHypotheses.
    /// No AI call — slots hypotheses into sections by patternType. Requires 3+ hypotheses.
    func assembleFromHypotheses(_ hypotheses: [PatternHypothesis], userId: String) {
        guard hypotheses.count >= 3 else { return }

        // The server model is audited (disconfirmation verdicts, confidence
        // bands, absences); this local assembly is not. Never replace the former
        // with the latter — it looks like the profile got dumber overnight.
        guard selfModel.writtenBy != "server" else { return }

        let active = hypotheses.filter { $0.isSurfaceable }

        let coreRules: [SelfModelHypothesis] = active
            .filter { $0.patternType == .identityRule || $0.patternType == .timeRhythm }
            .map { toSelfModelHypothesis($0) }

        let absences: [SelfModelHypothesis] = active
            .filter { $0.patternType == .absence }
            .map { toSelfModelHypothesis($0) }

        let bodySignals: [SelfModelHypothesis] = active
            .filter { $0.patternType == .bodySignal }
            .map { toSelfModelHypothesis($0) }

        let protectives: [ProtectiveHypothesis] = active
            .filter { $0.patternType == .protectiveLoop }
            .map { toProtectiveHypothesis($0) }

        let whatHelps: [SelfModelHypothesis] = active
            .filter { $0.patternType == .exception }
            .map { toSelfModelHypothesis($0) }

        let values: [SelfModelHypothesis] = active
            .filter { $0.patternType == .valuesConflict }
            .map { toSelfModelHypothesis($0) }

        let vocabulary: [VocabularyEntry] = active
            .filter { $0.patternType == .vocabularyFingerprint }
            .compactMap { h -> VocabularyEntry? in
                guard let quote = h.evidence.first?.quote else { return nil }
                return VocabularyEntry(
                    word: h.userFacingTitle,
                    personalMeaning: h.coreHypothesis,
                    confidence: h.salienceScore,
                    exampleUsage: quote
                )
            }

        let totalItems = coreRules.count + protectives.count + whatHelps.count + values.count
        let maturity: ProfileMaturity
        if totalItems >= 8 { maturity = .established }
        else if totalItems >= 5 { maturity = .growing }
        else if totalItems >= 3 { maturity = .sprouting }
        else { maturity = .seed }

        // Only update if we have more content than the existing model, or it's empty
        guard totalItems > 0, totalItems >= selfModel.coreRules.count + selfModel.protectiveStrategies.count + selfModel.whatHelps.count else { return }

        let assembled = SelfModel(
            userId: userId,
            version: max(selfModel.version, 1),
            updatedAt: Date(),
            profileMaturity: maturity,
            coreRules: coreRules,
            protectiveStrategies: protectives,
            innerParts: selfModel.innerParts,
            values: values,
            contradictions: selfModel.contradictions,
            whatHelps: whatHelps,
            absences: absences.isEmpty ? selfModel.absences : absences,
            bodySignals: bodySignals.isEmpty ? selfModel.bodySignals : bodySignals,
            relationshipRoles: selfModel.relationshipRoles,
            vocabulary: vocabulary.isEmpty ? selfModel.vocabulary : vocabulary,
            writtenBy: "client"
        )

        selfModel = assembled
        save(assembled, userId: userId)
    }

    private func toSelfModelHypothesis(_ h: PatternHypothesis) -> SelfModelHypothesis {
        SelfModelHypothesis(
            id: h.id,
            title: h.userFacingTitle,
            hypothesis: h.coreHypothesis,
            confidence: h.salienceScore,
            scope: h.scope,
            stability: h.stability,
            lifecycle: h.timesSeen >= 4 ? .recurring : h.timesSeen >= 2 ? .emerging : .observedOnce,
            evidenceEntryIds: h.evidence.map(\.entryId),
            lastSeenAt: h.shownAt ?? h.createdAt,
            decayAfterDays: 45,
            timesSeen: h.timesSeen
        )
    }

    private func toProtectiveHypothesis(_ h: PatternHypothesis) -> ProtectiveHypothesis {
        ProtectiveHypothesis(
            id: h.id,
            title: h.userFacingTitle,
            hypothesis: h.coreHypothesis,
            confidence: h.salienceScore,
            scope: h.scope,
            stability: h.stability,
            lifecycle: h.timesSeen >= 4 ? .recurring : h.timesSeen >= 2 ? .emerging : .observedOnce,
            evidenceEntryIds: h.evidence.map(\.entryId),
            lastSeenAt: h.shownAt ?? h.createdAt,
            decayAfterDays: 45,
            timesSeen: h.timesSeen,
            protectsAgainst: h.protection ?? "something uncertain",
            shortTermBenefit: h.protection ?? "stability",
            possibleCost: h.cost ?? "unknown"
        )
    }

    // MARK: - Life context

    /// Fetches the user's LifeContext from Firestore, or returns an empty one.
    /// Cache-first — this is a small, stable, low-churn doc read on every Mirror
    /// load, and previously paid a server round-trip every single time.
    func lifeContext(for userId: String) async -> LifeContext {
        guard let snapshot = try? await FirestoreCacheFirst.document(
            Firestore.firestore()
                .collection("users").document(userId)
                .collection("lifeContext").document("current"),
            key: "lifeContext.\(userId)"
        ), let data = snapshot.data(),
              let ctx = LifeContext(from: data)
        else { return LifeContext.empty(userId: userId) }

        return ctx
    }

    /// Fire-and-forget write of the user's LifeContext to Firestore.
    func saveLifeContext(_ ctx: LifeContext, userId: String) {
        Firestore.firestore()
            .collection("users").document(userId)
            .collection("lifeContext").document("current")
            .setData(ctx.toFirestoreData()) { _ in }
    }

    // MARK: - Private helpers

    /// Walks all hypothesis-bearing sections of the SelfModel and updates userStatus
    /// on the first hypothesis whose id matches.
    /// Returns true if a match was found and updated.
    @discardableResult
    private func applyUserStatus(
        id: String,
        status: UserHypothesisStatus,
        to model: inout SelfModel
    ) -> Bool {
        if let idx = model.coreRules.firstIndex(where: { $0.id == id }) {
            model.coreRules[idx].userStatus = status
            return true
        }
        if let idx = model.values.firstIndex(where: { $0.id == id }) {
            model.values[idx].userStatus = status
            return true
        }
        if let idx = model.contradictions.firstIndex(where: { $0.id == id }) {
            model.contradictions[idx].userStatus = status
            return true
        }
        if let idx = model.whatHelps.firstIndex(where: { $0.id == id }) {
            model.whatHelps[idx].userStatus = status
            return true
        }
        if let idx = model.absences.firstIndex(where: { $0.id == id }) {
            model.absences[idx].userStatus = status
            return true
        }
        // ProtectiveHypothesis carries its own userStatus field.
        if let idx = model.protectiveStrategies.firstIndex(where: { $0.id == id }) {
            model.protectiveStrategies[idx].userStatus = status
            return true
        }
        // InnerPart also carries userStatus.
        if let idx = model.innerParts.firstIndex(where: { $0.id == id }) {
            model.innerParts[idx].userStatus = status
            return true
        }
        return false
    }

    /// Sets stability to .retired on the first SelfModelHypothesis or
    /// ProtectiveHypothesis whose id matches across all sections.
    /// Returns true if a match was found and updated.
    @discardableResult
    private func applyRetired(id: String, to model: inout SelfModel) -> Bool {
        if let idx = model.coreRules.firstIndex(where: { $0.id == id }) {
            model.coreRules[idx] = retired(model.coreRules[idx])
            return true
        }
        if let idx = model.values.firstIndex(where: { $0.id == id }) {
            model.values[idx] = retired(model.values[idx])
            return true
        }
        if let idx = model.contradictions.firstIndex(where: { $0.id == id }) {
            model.contradictions[idx] = retired(model.contradictions[idx])
            return true
        }
        if let idx = model.whatHelps.firstIndex(where: { $0.id == id }) {
            model.whatHelps[idx] = retired(model.whatHelps[idx])
            return true
        }
        if let idx = model.absences.firstIndex(where: { $0.id == id }) {
            model.absences[idx] = retired(model.absences[idx])
            return true
        }
        if let idx = model.protectiveStrategies.firstIndex(where: { $0.id == id }) {
            model.protectiveStrategies[idx] = retiredProtective(model.protectiveStrategies[idx])
            return true
        }
        return false
    }

    /// Returns a copy of a SelfModelHypothesis with stability set to .retired.
    private func retired(_ h: SelfModelHypothesis) -> SelfModelHypothesis {
        SelfModelHypothesis(
            id:                      h.id,
            title:                   h.title,
            hypothesis:              h.hypothesis,
            confidence:              h.confidence,
            scope:                   h.scope,
            stability:               .retired,
            lifecycle:               h.lifecycle,
            userStatus:              h.userStatus,
            evidenceEntryIds:        h.evidenceEntryIds,
            counterEvidenceEntryIds: h.counterEvidenceEntryIds,
            lastSeenAt:              h.lastSeenAt,
            decayAfterDays:          h.decayAfterDays,
            timesSeen:               h.timesSeen,
            userConfirmations:       h.userConfirmations,
            userRejections:          h.userRejections,
            counterexamples:         h.counterexamples,
            lastTestedAt:            h.lastTestedAt,
            testedAgainstEntries:    h.testedAgainstEntries,
            disconfirmationVerdict:  h.disconfirmationVerdict
        )
    }

    /// Returns a copy of a ProtectiveHypothesis with stability set to .retired.
    private func retiredProtective(_ h: ProtectiveHypothesis) -> ProtectiveHypothesis {
        ProtectiveHypothesis(
            id:                      h.id,
            title:                   h.title,
            hypothesis:              h.hypothesis,
            confidence:              h.confidence,
            scope:                   h.scope,
            stability:               .retired,
            lifecycle:               h.lifecycle,
            userStatus:              h.userStatus,
            evidenceEntryIds:        h.evidenceEntryIds,
            counterEvidenceEntryIds: h.counterEvidenceEntryIds,
            lastSeenAt:              h.lastSeenAt,
            decayAfterDays:          h.decayAfterDays,
            timesSeen:               h.timesSeen,
            userConfirmations:       h.userConfirmations,
            userRejections:          h.userRejections,
            counterexamples:         h.counterexamples,
            lastTestedAt:            h.lastTestedAt,
            testedAgainstEntries:    h.testedAgainstEntries,
            disconfirmationVerdict:  h.disconfirmationVerdict,
            protectsAgainst:         h.protectsAgainst,
            shortTermBenefit:        h.shortTermBenefit,
            possibleCost:            h.possibleCost
        )
    }
}
