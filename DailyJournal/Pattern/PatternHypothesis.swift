// PatternHypothesis.swift
// DailyJournal
//
// A richer, scored hypothesis about a behavioural or emotional pattern. This is
// the pattern-recognition system that actually ships (via Mirror); the earlier
// Pattern Callback system it grew out of was cut as redundant with this one
// (see PATTERNS_MERGE_PLAN.md).
// Firestore collection: patternHypotheses (subcollection under users/{uid})

import Foundation
import FirebaseFirestore

// MARK: - PatternType

enum PatternType: String {
    case protectiveLoop          = "protective_loop"
    case avoidedSubject          = "avoided_subject"
    case identityRule            = "identity_rule"
    case relationshipRole        = "relationship_role"
    case bodySignal              = "body_signal"
    case valuesConflict          = "values_conflict"
    case exception               = "exception"
    case timeRhythm              = "time_rhythm"
    case vocabularyFingerprint   = "vocabulary_fingerprint"

    /// "What's gone quiet." A theme the person wrote about repeatedly and then
    /// stopped. Unlike every other type, the *detection* is arithmetic — the
    /// server compares baseline frequency against a silent recent window and
    /// hands the model hard counts to phrase. The model may not invent one.
    case absence                 = "absence"
}

// MARK: - PatternHypothesis
// NOTE: PatternEvidence, PatternArchetype, PatternCallbackStatus are defined in PatternTypes.swift

struct PatternHypothesis: Identifiable {

    // ── Existing Pattern ecosystem fields ──────────────────────────────
    let id: String
    let userId: String
    let archetype: PatternArchetype
    let evidence: [PatternEvidence]
    let salienceScore: Double
    var status: PatternCallbackStatus
    let createdAt: Date
    var shownAt: Date?
    var respondedAt: Date?

    // ── Mirror Engine enrichment fields ────────────────────────────────
    let patternType: PatternType
    let userFacingTitle: String
    let coreHypothesis: String
    let protection: String?
    let cost: String?
    var counterEvidence: [String]
    let noveltyScore: Double
    let emotionalWeight: Double
    let actionabilityScore: Double
    let shameRisk: Double
    let diagnosticRisk: Double
    let tinyExperiment: String?
    let callbackQuestion: String?
    let firstSeenAt: Date
    var timesSeen: Int
    var scope: HypothesisScope
    var stability: HypothesisStability

    // MARK: - Computed

    var isSurfaceable: Bool { status == .pending && stability != .retired }

    var mirrorScore: Double { MirrorScore.score(for: self) }

    // MARK: - Designated init

    init(
        id: String = UUID().uuidString,
        userId: String,
        archetype: PatternArchetype,
        evidence: [PatternEvidence] = [],
        salienceScore: Double,
        status: PatternCallbackStatus = .pending,
        createdAt: Date = Date(),
        shownAt: Date? = nil,
        respondedAt: Date? = nil,
        patternType: PatternType,
        userFacingTitle: String,
        coreHypothesis: String,
        protection: String? = nil,
        cost: String? = nil,
        counterEvidence: [String] = [],
        noveltyScore: Double = 0.5,
        emotionalWeight: Double = 0.5,
        actionabilityScore: Double = 0.5,
        shameRisk: Double = 0,
        diagnosticRisk: Double = 0,
        tinyExperiment: String? = nil,
        callbackQuestion: String? = nil,
        firstSeenAt: Date = Date(),
        timesSeen: Int = 1,
        scope: HypothesisScope = .recurring,
        stability: HypothesisStability = .emerging
    ) {
        self.id                = id
        self.userId            = userId
        self.archetype         = archetype
        self.evidence          = evidence
        self.salienceScore     = salienceScore
        self.status            = status
        self.createdAt         = createdAt
        self.shownAt           = shownAt
        self.respondedAt       = respondedAt
        self.patternType       = patternType
        self.userFacingTitle   = userFacingTitle
        self.coreHypothesis    = coreHypothesis
        self.protection        = protection
        self.cost              = cost
        self.counterEvidence   = counterEvidence
        self.noveltyScore      = noveltyScore
        self.emotionalWeight   = emotionalWeight
        self.actionabilityScore = actionabilityScore
        self.shameRisk         = shameRisk
        self.diagnosticRisk    = diagnosticRisk
        self.tinyExperiment    = tinyExperiment
        self.callbackQuestion  = callbackQuestion
        self.firstSeenAt       = firstSeenAt
        self.timesSeen         = timesSeen
        self.scope             = scope
        self.stability         = stability
    }

    // MARK: - Firestore deserialisation

    init?(from data: [String: Any]) {
        guard
            let id            = data["id"]            as? String,
            let userId        = data["userId"]        as? String,
            let archetypeRaw  = data["archetype"]     as? String,
            let archetype     = PatternArchetype(rawValue: archetypeRaw),
            let salienceScore = data["salienceScore"] as? Double,
            let statusRaw     = data["status"]        as? String,
            let status        = PatternCallbackStatus(rawValue: statusRaw),
            let createdAt     = (data["createdAt"]    as? Timestamp)?.dateValue(),
            let patternTypeRaw  = data["patternType"]     as? String,
            let patternType     = PatternType(rawValue: patternTypeRaw),
            let userFacingTitle = data["userFacingTitle"] as? String,
            let coreHypothesis  = data["coreHypothesis"]  as? String,
            let firstSeenAt     = (data["firstSeenAt"] as? Timestamp)?.dateValue()
        else { return nil }

        self.id               = id
        self.userId           = userId
        self.archetype        = archetype
        self.evidence         = (data["evidence"] as? [[String: Any]] ?? [])
            .compactMap { PatternEvidence(from: $0) }
        self.salienceScore    = salienceScore
        self.status           = status
        self.createdAt        = createdAt
        self.shownAt          = (data["shownAt"]      as? Timestamp)?.dateValue()
        self.respondedAt      = (data["respondedAt"]  as? Timestamp)?.dateValue()
        self.patternType      = patternType
        self.userFacingTitle  = userFacingTitle
        self.coreHypothesis   = coreHypothesis
        self.protection       = data["protection"]      as? String
        self.cost             = data["cost"]            as? String
        self.counterEvidence  = data["counterEvidence"] as? [String] ?? []
        self.noveltyScore     = data["noveltyScore"]      as? Double ?? 0.5
        self.emotionalWeight  = data["emotionalWeight"]   as? Double ?? 0.5
        self.actionabilityScore = data["actionabilityScore"] as? Double ?? 0.5
        self.shameRisk        = data["shameRisk"]       as? Double ?? 0
        self.diagnosticRisk   = data["diagnosticRisk"]  as? Double ?? 0
        self.tinyExperiment   = data["tinyExperiment"]  as? String
        self.callbackQuestion = data["callbackQuestion"] as? String
        self.firstSeenAt      = firstSeenAt
        self.timesSeen        = data["timesSeen"] as? Int ?? 1
        self.scope            = HypothesisScope(rawValue: data["scope"] as? String ?? "") ?? .recurring
        self.stability        = HypothesisStability(rawValue: data["stability"] as? String ?? "") ?? .emerging
    }

    // MARK: - Firestore serialisation

    func toFirestoreData() -> [String: Any] {
        var d: [String: Any] = [
            "id":                 id,
            "userId":             userId,
            "archetype":          archetype.rawValue,
            "evidence":           evidence.map { $0.toFirestoreData() },
            "salienceScore":      salienceScore,
            "status":             status.rawValue,
            "createdAt":          Timestamp(date: createdAt),
            "patternType":        patternType.rawValue,
            "userFacingTitle":    userFacingTitle,
            "coreHypothesis":     coreHypothesis,
            "counterEvidence":    counterEvidence,
            "noveltyScore":       noveltyScore,
            "emotionalWeight":    emotionalWeight,
            "actionabilityScore": actionabilityScore,
            "shameRisk":          shameRisk,
            "diagnosticRisk":     diagnosticRisk,
            "firstSeenAt":        Timestamp(date: firstSeenAt),
            "timesSeen":          timesSeen,
            "scope":              scope.rawValue,
            "stability":          stability.rawValue
        ]
        if let shownAt          { d["shownAt"]          = Timestamp(date: shownAt) }
        if let respondedAt      { d["respondedAt"]      = Timestamp(date: respondedAt) }
        if let protection       { d["protection"]       = protection }
        if let cost             { d["cost"]             = cost }
        if let tinyExperiment   { d["tinyExperiment"]   = tinyExperiment }
        if let callbackQuestion { d["callbackQuestion"] = callbackQuestion }
        return d
    }
}
