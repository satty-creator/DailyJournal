// EntryAnalysis.swift
// DailyJournal
//
// Deep per-entry analysis produced by the Mirror Engine.
// Persisted at: users/{uid}/entryAnalyses/{entryId}

import Foundation
import FirebaseFirestore

// MARK: - Nested supporting types (file-scope, not inside EntryAnalysis)

struct InferredEmotion {
    let emotion: String
    let confidence: Double
    let evidenceQuote: String

    init(emotion: String, confidence: Double, evidenceQuote: String) {
        self.emotion       = emotion
        self.confidence    = confidence
        self.evidenceQuote = evidenceQuote
    }

    init?(from data: [String: Any]) {
        guard
            let emotion       = data["emotion"]       as? String,
            let confidence    = data["confidence"]    as? Double,
            let evidenceQuote = data["evidenceQuote"] as? String
        else { return nil }
        self.emotion       = emotion
        self.confidence    = confidence
        self.evidenceQuote = evidenceQuote
    }

    func toFirestoreData() -> [String: Any] {
        [
            "emotion":       emotion,
            "confidence":    confidence,
            "evidenceQuote": evidenceQuote
        ]
    }
}

struct ProtectiveStrategy {
    let strategy: String
    let protectsAgainst: String
    let confidence: Double
    let evidence: String

    init(strategy: String, protectsAgainst: String, confidence: Double, evidence: String) {
        self.strategy        = strategy
        self.protectsAgainst = protectsAgainst
        self.confidence      = confidence
        self.evidence        = evidence
    }

    init?(from data: [String: Any]) {
        guard
            let strategy        = data["strategy"]        as? String,
            let protectsAgainst = data["protectsAgainst"] as? String,
            let confidence      = data["confidence"]      as? Double,
            let evidence        = data["evidence"]        as? String
        else { return nil }
        self.strategy        = strategy
        self.protectsAgainst = protectsAgainst
        self.confidence      = confidence
        self.evidence        = evidence
    }

    func toFirestoreData() -> [String: Any] {
        [
            "strategy":        strategy,
            "protectsAgainst": protectsAgainst,
            "confidence":      confidence,
            "evidence":        evidence
        ]
    }
}

/// A guided-template before/after self-rating (Phase 5 — typed template
/// fields). `templateId` is `JournalTemplate.id`; `before`/`after` are the
/// entry's own `templateScaleBefore`/`templateScaleAfter` (0–10), carried
/// through as a typed passthrough — never model output, so there is nothing
/// for the model to invent. The mine prompt treats a delta as arithmetic
/// fact, exactly like the existing absence shortlist.
struct TemplateDelta {
    let templateId: String
    let before: Int
    let after: Int

    init(templateId: String, before: Int, after: Int) {
        self.templateId = templateId
        self.before     = before
        self.after      = after
    }

    init?(from data: [String: Any]) {
        guard
            let templateId = data["templateId"] as? String,
            let before     = data["before"]     as? Int,
            let after      = data["after"]      as? Int
        else { return nil }
        self.templateId = templateId
        self.before     = before
        self.after      = after
    }

    func toFirestoreData() -> [String: Any] {
        ["templateId": templateId, "before": before, "after": after]
    }
}

struct AvoidanceMarker {
    let type: String
    let phrase: String
    let function: String

    init(type: String, phrase: String, function: String) {
        self.type     = type
        self.phrase   = phrase
        self.function = function
    }

    init?(from data: [String: Any]) {
        guard
            let type     = data["type"]     as? String,
            let phrase   = data["phrase"]   as? String,
            let function = data["function"] as? String
        else { return nil }
        self.type     = type
        self.phrase   = phrase
        self.function = function
    }

    func toFirestoreData() -> [String: Any] {
        [
            "type":     type,
            "phrase":   phrase,
            "function": function
        ]
    }
}

// MARK: - EntryAnalysis

struct EntryAnalysis {

    let entryId: String
    let userId: String
    let surfaceSummary: String
    let lifeDomains: [String]
    let explicitEmotions: [String]
    let inferredEmotions: [InferredEmotion]
    let needs: [String]
    let protectiveStrategies: [ProtectiveStrategy]
    let avoidanceMarkers: [AvoidanceMarker]
    let cognitivePatterns: [String]
    let valuesPresent: [String]
    let valuesConflict: [String]
    let bodySignals: [String]
    let relationshipRoles: [String]
    let openLoops: [String]
    let phrasesToTrack: [String]
    let possibleTinyAct: String?
    let episodes: [EpisodeFrame]
    let promptVersion: String
    let createdAt: Date
    /// Typed passthrough from the entry, not model output — see TemplateDelta.
    let templateDelta: TemplateDelta?

    // MARK: - Designated init

    init(
        entryId: String,
        userId: String,
        surfaceSummary: String,
        lifeDomains: [String],
        explicitEmotions: [String],
        inferredEmotions: [InferredEmotion],
        needs: [String],
        protectiveStrategies: [ProtectiveStrategy],
        avoidanceMarkers: [AvoidanceMarker],
        cognitivePatterns: [String],
        valuesPresent: [String],
        valuesConflict: [String],
        bodySignals: [String],
        relationshipRoles: [String],
        openLoops: [String],
        phrasesToTrack: [String],
        possibleTinyAct: String? = nil,
        episodes: [EpisodeFrame],
        promptVersion: String,
        createdAt: Date = Date(),
        templateDelta: TemplateDelta? = nil
    ) {
        self.entryId              = entryId
        self.userId               = userId
        self.surfaceSummary       = surfaceSummary
        self.lifeDomains          = lifeDomains
        self.explicitEmotions     = explicitEmotions
        self.inferredEmotions     = inferredEmotions
        self.needs                = needs
        self.protectiveStrategies = protectiveStrategies
        self.avoidanceMarkers     = avoidanceMarkers
        self.cognitivePatterns    = cognitivePatterns
        self.valuesPresent        = valuesPresent
        self.valuesConflict       = valuesConflict
        self.bodySignals          = bodySignals
        self.relationshipRoles    = relationshipRoles
        self.openLoops            = openLoops
        self.phrasesToTrack       = phrasesToTrack
        self.possibleTinyAct      = possibleTinyAct
        self.episodes             = episodes
        self.promptVersion        = promptVersion
        self.createdAt            = createdAt
        self.templateDelta        = templateDelta
    }

    // MARK: - Firestore deserialisation

    init?(from data: [String: Any]) {
        guard
            let entryId  = data["entryId"]  as? String,
            let userId   = data["userId"]   as? String,
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        else { return nil }

        self.entryId          = entryId
        self.userId           = userId
        self.surfaceSummary   = data["surfaceSummary"]   as? String ?? ""
        self.lifeDomains      = data["lifeDomains"]      as? [String] ?? []
        self.explicitEmotions = data["explicitEmotions"] as? [String] ?? []
        self.inferredEmotions = (data["inferredEmotions"] as? [[String: Any]] ?? [])
            .compactMap { InferredEmotion(from: $0) }
        self.needs            = data["needs"] as? [String] ?? []
        self.protectiveStrategies = (data["protectiveStrategies"] as? [[String: Any]] ?? [])
            .compactMap { ProtectiveStrategy(from: $0) }
        self.avoidanceMarkers = (data["avoidanceMarkers"] as? [[String: Any]] ?? [])
            .compactMap { AvoidanceMarker(from: $0) }
        self.cognitivePatterns  = data["cognitivePatterns"]  as? [String] ?? []
        self.valuesPresent      = data["valuesPresent"]      as? [String] ?? []
        self.valuesConflict     = data["valuesConflict"]     as? [String] ?? []
        self.bodySignals        = data["bodySignals"]        as? [String] ?? []
        self.relationshipRoles  = data["relationshipRoles"]  as? [String] ?? []
        self.openLoops          = data["openLoops"]          as? [String] ?? []
        self.phrasesToTrack     = data["phrasesToTrack"]     as? [String] ?? []
        self.possibleTinyAct    = data["possibleTinyAct"]    as? String
        self.episodes           = (data["episodes"] as? [[String: Any]] ?? [])
            .compactMap { EpisodeFrame(from: $0) }
        self.promptVersion      = data["promptVersion"] as? String ?? "unknown"
        self.createdAt          = createdAt
        self.templateDelta      = (data["templateDelta"] as? [String: Any]).flatMap { TemplateDelta(from: $0) }
    }

    // MARK: - Firestore serialisation

    func toFirestoreData() -> [String: Any] {
        var d: [String: Any] = [
            "entryId":              entryId,
            "userId":               userId,
            "surfaceSummary":       surfaceSummary,
            "lifeDomains":          lifeDomains,
            "explicitEmotions":     explicitEmotions,
            "inferredEmotions":     inferredEmotions.map { $0.toFirestoreData() },
            "needs":                needs,
            "protectiveStrategies": protectiveStrategies.map { $0.toFirestoreData() },
            "avoidanceMarkers":     avoidanceMarkers.map { $0.toFirestoreData() },
            "cognitivePatterns":    cognitivePatterns,
            "valuesPresent":        valuesPresent,
            "valuesConflict":       valuesConflict,
            "bodySignals":          bodySignals,
            "relationshipRoles":    relationshipRoles,
            "openLoops":            openLoops,
            "phrasesToTrack":       phrasesToTrack,
            "episodes":             episodes.map { $0.toFirestoreData() },
            "promptVersion":        promptVersion,
            "createdAt":            Timestamp(date: createdAt)
        ]
        if let possibleTinyAct { d["possibleTinyAct"] = possibleTinyAct }
        if let templateDelta { d["templateDelta"] = templateDelta.toFirestoreData() }
        return d
    }

    /// Copy with `templateDelta` attached — used once, right after
    /// `parseMirrorExtractResponse` returns, to merge in the typed
    /// passthrough the model was never asked about.
    func withTemplateDelta(_ delta: TemplateDelta?) -> EntryAnalysis {
        EntryAnalysis(
            entryId: entryId, userId: userId, surfaceSummary: surfaceSummary,
            lifeDomains: lifeDomains, explicitEmotions: explicitEmotions,
            inferredEmotions: inferredEmotions, needs: needs,
            protectiveStrategies: protectiveStrategies, avoidanceMarkers: avoidanceMarkers,
            cognitivePatterns: cognitivePatterns, valuesPresent: valuesPresent,
            valuesConflict: valuesConflict, bodySignals: bodySignals,
            relationshipRoles: relationshipRoles, openLoops: openLoops,
            phrasesToTrack: phrasesToTrack, possibleTinyAct: possibleTinyAct,
            episodes: episodes, promptVersion: promptVersion, createdAt: createdAt,
            templateDelta: delta
        )
    }

    // MARK: - Empty default

    static let empty = EntryAnalysis(
        entryId: "",
        userId: "",
        surfaceSummary: "",
        lifeDomains: [],
        explicitEmotions: [],
        inferredEmotions: [],
        needs: [],
        protectiveStrategies: [],
        avoidanceMarkers: [],
        cognitivePatterns: [],
        valuesPresent: [],
        valuesConflict: [],
        bodySignals: [],
        relationshipRoles: [],
        openLoops: [],
        phrasesToTrack: [],
        possibleTinyAct: nil,
        episodes: [],
        promptVersion: "none"
    )

    // MARK: - Local heuristic fallback

    /// Simple offline analysis: scan text for common emotion words, set surfaceSummary
    /// to the first 80 characters. Everything else stays empty so the app degrades
    /// gracefully without an AI response.
    static func local(entryId: String, userId: String, text: String) -> EntryAnalysis {
        let emotionWords = ["anxious", "tired", "excited", "calm", "frustrated", "sad", "happy", "proud"]
        let lowercased = text.lowercased()
        let found = emotionWords.filter { lowercased.contains($0) }

        let summary = text.count > 80
            ? String(text.prefix(80))
            : text

        return EntryAnalysis(
            entryId: entryId,
            userId: userId,
            surfaceSummary: summary,
            lifeDomains: [],
            explicitEmotions: found,
            inferredEmotions: [],
            needs: [],
            protectiveStrategies: [],
            avoidanceMarkers: [],
            cognitivePatterns: [],
            valuesPresent: [],
            valuesConflict: [],
            bodySignals: [],
            relationshipRoles: [],
            openLoops: [],
            phrasesToTrack: [],
            possibleTinyAct: nil,
            episodes: [],
            promptVersion: "local"
        )
    }
}
