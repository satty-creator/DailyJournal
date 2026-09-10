// SelfModel.swift
// DailyJournal
//
// The user's evolving self-model: a structured collection of hypotheses about
// how they work, what protects them, their inner parts, values, and vocabulary.
// Persisted at: users/{uid}/selfModel (single document per user).

import Foundation
import FirebaseFirestore

// MARK: - Enums

enum HypothesisScope: String {
    case today          = "today"
    case thisWeek       = "this_week"
    case thisMonth      = "this_month"
    case recurring      = "recurring"
    case userConfirmed  = "user_confirmed"
}

enum HypothesisStability: String {
    case temporary = "temporary"
    case emerging  = "emerging"
    case stable    = "stable"
    case retired   = "retired"
}

enum UserHypothesisStatus: String {
    case unrated    = "unrated"
    case thisIsMe   = "this_is_me"
    case halfTrue   = "half_true"
    case notMe      = "not_me"
}

enum HypothesisLifecycle: String {
    case observedOnce  = "observed_once"
    case emerging      = "emerging"
    case recurring     = "recurring"
    case userConfirmed = "user_confirmed"
    case weakened      = "weakened"
    case retired       = "retired"
}

enum ProfileMaturity: String {
    case seed        = "seed"
    case sprouting   = "sprouting"
    case growing     = "growing"
    case established = "established"
}

// MARK: - SelfModelHypothesis

struct SelfModelHypothesis: Identifiable {

    let id: String
    let title: String
    let hypothesis: String
    let confidence: Double
    let scope: HypothesisScope
    let stability: HypothesisStability
    let lifecycle: HypothesisLifecycle
    var userStatus: UserHypothesisStatus
    var evidenceEntryIds: [String]
    var counterEvidenceEntryIds: [String]
    var lastSeenAt: Date
    let decayAfterDays: Int
    var timesSeen: Int
    var userConfirmations: Int
    var userRejections: Int
    var counterexamples: Int
    var lastTestedAt: Date?

    /// How many entries the disconfirmation pass checked this claim against —
    /// entries the claim had *not* already cited. `0` means it has never been
    /// independently tested, and the UI must say so rather than implying
    /// certainty the claim never earned.
    var testedAgainstEntries: Int

    /// `"hold"`, `"weaken"`, `"drop"`, or `""` if never audited.
    var disconfirmationVerdict: String

    var isActive: Bool { stability != .retired }

    /// Plain-language certainty. Never a percentage — a number implies a
    /// precision that a language model's guess about a person does not have.
    /// This is the Exist.io discipline: strength and confidence are separate
    /// axes, and a hedged claim that misses costs nothing while a confident
    /// claim that misses burns trust permanently.
    enum ConfidenceBand: String {
        case hunch  = "A hunch"
        case maybe  = "Might be a thing"
        case likely = "Showing up repeatedly"
        case yours  = "You confirmed this"
    }

    var confidenceBand: ConfidenceBand {
        if userStatus == .thisIsMe { return .yours }
        if confidence >= 0.7 && timesSeen >= 3 { return .likely }
        if confidence >= 0.45 { return .maybe }
        return .hunch
    }

    /// One honest line about how well-tested this is. Empty when there is
    /// nothing truthful to say, because silence beats false reassurance.
    /// May this item appear in the profile at all? (Mirror v3 §5.6.)
    ///
    /// Either the user confirmed it, or it recurred on 3+ distinct entries AND
    /// an audit actually ran and did not drop it. Everything else stays in the
    /// corpus, invisible — which is what makes the "A hunch · Not checked
    /// against other entries yet" caption unnecessary rather than merely
    /// hidden. The app should not show you something and simultaneously tell
    /// you it hasn't checked it.
    var isProfileSurfaceable: Bool {
        if userStatus == .thisIsMe { return true }
        guard timesSeen >= 3 else { return false }
        guard testedAgainstEntries > 0 else { return false }
        return disconfirmationVerdict != "drop"
    }

    var evidenceCaveat: String {
        if disconfirmationVerdict == "weaken" {
            return "Softened after checking other entries"
        }
        // The "Not checked against other entries yet" string is GONE (Mirror
        // v3 M7). It appeared on 17 of 19 cards — the UI printing the ABSENCE
        // of QA as though it were a finding about the user. Unaudited items
        // are no longer shown at all (see `isProfileSurfaceable`), so this
        // branch is unreachable rather than merely hidden; returning empty
        // keeps it that way if the gate above is ever relaxed.
        if testedAgainstEntries == 0 { return "" }
        if counterEvidenceEntryIds.isEmpty {
            return "Held up against \(testedAgainstEntries) other entries"
        }
        return "\(counterEvidenceEntryIds.count) entr\(counterEvidenceEntryIds.count == 1 ? "y" : "ies") pushed back on this"
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        hypothesis: String,
        confidence: Double,
        scope: HypothesisScope = .recurring,
        stability: HypothesisStability = .emerging,
        lifecycle: HypothesisLifecycle = .observedOnce,
        userStatus: UserHypothesisStatus = .unrated,
        evidenceEntryIds: [String] = [],
        counterEvidenceEntryIds: [String] = [],
        lastSeenAt: Date = Date(),
        decayAfterDays: Int = 45,
        timesSeen: Int = 1,
        userConfirmations: Int = 0,
        userRejections: Int = 0,
        counterexamples: Int = 0,
        lastTestedAt: Date? = nil,
        testedAgainstEntries: Int = 0,
        disconfirmationVerdict: String = ""
    ) {
        self.id                     = id
        self.title                  = title
        self.hypothesis             = hypothesis
        self.confidence             = confidence
        self.scope                  = scope
        self.stability              = stability
        self.lifecycle              = lifecycle
        self.userStatus             = userStatus
        self.evidenceEntryIds       = evidenceEntryIds
        self.counterEvidenceEntryIds = counterEvidenceEntryIds
        self.lastSeenAt             = lastSeenAt
        self.decayAfterDays         = decayAfterDays
        self.timesSeen              = timesSeen
        self.userConfirmations      = userConfirmations
        self.userRejections         = userRejections
        self.counterexamples        = counterexamples
        self.lastTestedAt           = lastTestedAt
        self.testedAgainstEntries   = testedAgainstEntries
        self.disconfirmationVerdict = disconfirmationVerdict
    }

    init?(from data: [String: Any]) {
        guard
            let id         = data["id"]         as? String,
            let title      = data["title"]      as? String,
            let hypothesis = data["hypothesis"] as? String,
            let confidence = data["confidence"] as? Double,
            let lastSeenAt = (data["lastSeenAt"] as? Timestamp)?.dateValue()
        else { return nil }

        self.id                      = id
        self.title                   = title
        self.hypothesis              = hypothesis
        self.confidence              = confidence
        self.scope                   = HypothesisScope(rawValue: data["scope"] as? String ?? "") ?? .recurring
        self.stability               = HypothesisStability(rawValue: data["stability"] as? String ?? "") ?? .emerging
        self.lifecycle               = HypothesisLifecycle(rawValue: data["lifecycle"] as? String ?? "") ?? .observedOnce
        self.userStatus              = UserHypothesisStatus(rawValue: data["userStatus"] as? String ?? "") ?? .unrated
        self.evidenceEntryIds        = data["evidenceEntryIds"]        as? [String] ?? []
        self.counterEvidenceEntryIds = data["counterEvidenceEntryIds"] as? [String] ?? []
        self.lastSeenAt              = lastSeenAt
        self.decayAfterDays          = data["decayAfterDays"]     as? Int ?? 45
        self.timesSeen               = data["timesSeen"]          as? Int ?? 1
        self.userConfirmations       = data["userConfirmations"]  as? Int ?? 0
        self.userRejections          = data["userRejections"]     as? Int ?? 0
        self.counterexamples         = data["counterexamples"]    as? Int ?? 0
        self.lastTestedAt            = (data["lastTestedAt"] as? Timestamp)?.dateValue()
        self.testedAgainstEntries    = data["testedAgainstEntries"] as? Int ?? 0
        self.disconfirmationVerdict  = data["disconfirmationVerdict"] as? String ?? ""
    }

    func toFirestoreData() -> [String: Any] {
        var d: [String: Any] = [
            "id":                      id,
            "title":                   title,
            "hypothesis":              hypothesis,
            "confidence":              confidence,
            "scope":                   scope.rawValue,
            "stability":               stability.rawValue,
            "lifecycle":               lifecycle.rawValue,
            "userStatus":              userStatus.rawValue,
            "evidenceEntryIds":        evidenceEntryIds,
            "counterEvidenceEntryIds": counterEvidenceEntryIds,
            "lastSeenAt":              Timestamp(date: lastSeenAt),
            "decayAfterDays":          decayAfterDays,
            "timesSeen":               timesSeen,
            "userConfirmations":       userConfirmations,
            "userRejections":          userRejections,
            "counterexamples":         counterexamples,
            "testedAgainstEntries":    testedAgainstEntries,
            "disconfirmationVerdict":  disconfirmationVerdict
        ]
        if let lastTestedAt { d["lastTestedAt"] = Timestamp(date: lastTestedAt) }
        return d
    }
}

// MARK: - ProtectiveHypothesis

struct ProtectiveHypothesis: Identifiable {

    let id: String
    let title: String
    let hypothesis: String
    let confidence: Double
    let scope: HypothesisScope
    let stability: HypothesisStability
    let lifecycle: HypothesisLifecycle
    var userStatus: UserHypothesisStatus
    var evidenceEntryIds: [String]
    var counterEvidenceEntryIds: [String]
    var lastSeenAt: Date
    let decayAfterDays: Int
    var timesSeen: Int
    var userConfirmations: Int
    var userRejections: Int
    var counterexamples: Int
    var lastTestedAt: Date?

    let protectsAgainst: String
    let shortTermBenefit: String
    let possibleCost: String

    var testedAgainstEntries: Int
    var disconfirmationVerdict: String

    var isActive: Bool { stability != .retired }

    /// Mirrors `SelfModelHypothesis` so the card views can render either shape
    /// through one code path.
    var asHypothesis: SelfModelHypothesis {
        SelfModelHypothesis(
            id: id, title: title, hypothesis: hypothesis, confidence: confidence,
            scope: scope, stability: stability, lifecycle: lifecycle,
            userStatus: userStatus, evidenceEntryIds: evidenceEntryIds,
            counterEvidenceEntryIds: counterEvidenceEntryIds, lastSeenAt: lastSeenAt,
            decayAfterDays: decayAfterDays, timesSeen: timesSeen,
            userConfirmations: userConfirmations, userRejections: userRejections,
            counterexamples: counterexamples, lastTestedAt: lastTestedAt,
            testedAgainstEntries: testedAgainstEntries,
            disconfirmationVerdict: disconfirmationVerdict
        )
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        hypothesis: String,
        confidence: Double,
        scope: HypothesisScope = .recurring,
        stability: HypothesisStability = .emerging,
        lifecycle: HypothesisLifecycle = .observedOnce,
        userStatus: UserHypothesisStatus = .unrated,
        evidenceEntryIds: [String] = [],
        counterEvidenceEntryIds: [String] = [],
        lastSeenAt: Date = Date(),
        decayAfterDays: Int = 45,
        timesSeen: Int = 1,
        userConfirmations: Int = 0,
        userRejections: Int = 0,
        counterexamples: Int = 0,
        lastTestedAt: Date? = nil,
        testedAgainstEntries: Int = 0,
        disconfirmationVerdict: String = "",
        protectsAgainst: String,
        shortTermBenefit: String,
        possibleCost: String
    ) {
        self.id                      = id
        self.title                   = title
        self.hypothesis              = hypothesis
        self.confidence              = confidence
        self.scope                   = scope
        self.stability               = stability
        self.lifecycle               = lifecycle
        self.userStatus              = userStatus
        self.evidenceEntryIds        = evidenceEntryIds
        self.counterEvidenceEntryIds = counterEvidenceEntryIds
        self.lastSeenAt              = lastSeenAt
        self.decayAfterDays          = decayAfterDays
        self.timesSeen               = timesSeen
        self.userConfirmations       = userConfirmations
        self.userRejections          = userRejections
        self.counterexamples         = counterexamples
        self.lastTestedAt            = lastTestedAt
        self.testedAgainstEntries    = testedAgainstEntries
        self.disconfirmationVerdict  = disconfirmationVerdict
        self.protectsAgainst         = protectsAgainst
        self.shortTermBenefit        = shortTermBenefit
        self.possibleCost            = possibleCost
    }

    init?(from data: [String: Any]) {
        guard
            let id               = data["id"]               as? String,
            let title            = data["title"]            as? String,
            let hypothesis       = data["hypothesis"]       as? String,
            let confidence       = data["confidence"]       as? Double,
            let lastSeenAt       = (data["lastSeenAt"] as? Timestamp)?.dateValue(),
            let protectsAgainst  = data["protectsAgainst"]  as? String,
            let shortTermBenefit = data["shortTermBenefit"] as? String,
            let possibleCost     = data["possibleCost"]     as? String
        else { return nil }

        self.id                      = id
        self.title                   = title
        self.hypothesis              = hypothesis
        self.confidence              = confidence
        self.scope                   = HypothesisScope(rawValue: data["scope"] as? String ?? "") ?? .recurring
        self.stability               = HypothesisStability(rawValue: data["stability"] as? String ?? "") ?? .emerging
        self.lifecycle               = HypothesisLifecycle(rawValue: data["lifecycle"] as? String ?? "") ?? .observedOnce
        self.userStatus              = UserHypothesisStatus(rawValue: data["userStatus"] as? String ?? "") ?? .unrated
        self.evidenceEntryIds        = data["evidenceEntryIds"]        as? [String] ?? []
        self.counterEvidenceEntryIds = data["counterEvidenceEntryIds"] as? [String] ?? []
        self.lastSeenAt              = lastSeenAt
        self.decayAfterDays          = data["decayAfterDays"]     as? Int ?? 45
        self.timesSeen               = data["timesSeen"]          as? Int ?? 1
        self.userConfirmations       = data["userConfirmations"]  as? Int ?? 0
        self.userRejections          = data["userRejections"]     as? Int ?? 0
        self.counterexamples         = data["counterexamples"]    as? Int ?? 0
        self.lastTestedAt            = (data["lastTestedAt"] as? Timestamp)?.dateValue()
        self.testedAgainstEntries    = data["testedAgainstEntries"] as? Int ?? 0
        self.disconfirmationVerdict  = data["disconfirmationVerdict"] as? String ?? ""
        self.protectsAgainst         = protectsAgainst
        self.shortTermBenefit        = shortTermBenefit
        self.possibleCost            = possibleCost
    }

    func toFirestoreData() -> [String: Any] {
        var d: [String: Any] = [
            "id":                      id,
            "title":                   title,
            "hypothesis":              hypothesis,
            "confidence":              confidence,
            "scope":                   scope.rawValue,
            "stability":               stability.rawValue,
            "lifecycle":               lifecycle.rawValue,
            "userStatus":              userStatus.rawValue,
            "evidenceEntryIds":        evidenceEntryIds,
            "counterEvidenceEntryIds": counterEvidenceEntryIds,
            "lastSeenAt":              Timestamp(date: lastSeenAt),
            "decayAfterDays":          decayAfterDays,
            "timesSeen":               timesSeen,
            "userConfirmations":       userConfirmations,
            "userRejections":          userRejections,
            "counterexamples":         counterexamples,
            "testedAgainstEntries":    testedAgainstEntries,
            "disconfirmationVerdict":  disconfirmationVerdict,
            "protectsAgainst":         protectsAgainst,
            "shortTermBenefit":        shortTermBenefit,
            "possibleCost":            possibleCost
        ]
        if let lastTestedAt { d["lastTestedAt"] = Timestamp(date: lastTestedAt) }
        return d
    }
}

// MARK: - InnerPart

struct InnerPart: Identifiable {

    let id: String
    let name: String
    let description: String
    let commonTriggers: [String]
    let commonLanguage: [String]
    let confidence: Double
    var userStatus: UserHypothesisStatus

    init(
        id: String = UUID().uuidString,
        name: String,
        description: String,
        commonTriggers: [String] = [],
        commonLanguage: [String] = [],
        confidence: Double,
        userStatus: UserHypothesisStatus = .unrated
    ) {
        self.id             = id
        self.name           = name
        self.description    = description
        self.commonTriggers = commonTriggers
        self.commonLanguage = commonLanguage
        self.confidence     = confidence
        self.userStatus     = userStatus
    }

    init?(from data: [String: Any]) {
        guard
            let id          = data["id"]          as? String,
            let name        = data["name"]        as? String,
            let description = data["description"] as? String,
            let confidence  = data["confidence"]  as? Double
        else { return nil }

        self.id             = id
        self.name           = name
        self.description    = description
        self.commonTriggers = data["commonTriggers"] as? [String] ?? []
        self.commonLanguage = data["commonLanguage"] as? [String] ?? []
        self.confidence     = confidence
        self.userStatus     = UserHypothesisStatus(rawValue: data["userStatus"] as? String ?? "") ?? .unrated
    }

    func toFirestoreData() -> [String: Any] {
        [
            "id":             id,
            "name":           name,
            "description":    description,
            "commonTriggers": commonTriggers,
            "commonLanguage": commonLanguage,
            "confidence":     confidence,
            "userStatus":     userStatus.rawValue
        ]
    }
}

// MARK: - RelationshipRole

struct RelationshipRole: Identifiable {

    let id: String
    let context: String
    let role: String
    let confidence: Double
    var evidenceEntryIds: [String]

    init(
        id: String = UUID().uuidString,
        context: String,
        role: String,
        confidence: Double,
        evidenceEntryIds: [String] = []
    ) {
        self.id               = id
        self.context          = context
        self.role             = role
        self.confidence       = confidence
        self.evidenceEntryIds = evidenceEntryIds
    }

    init?(from data: [String: Any]) {
        guard
            let id         = data["id"]         as? String,
            let context    = data["context"]    as? String,
            let role       = data["role"]       as? String,
            let confidence = data["confidence"] as? Double
        else { return nil }

        self.id               = id
        self.context          = context
        self.role             = role
        self.confidence       = confidence
        self.evidenceEntryIds = data["evidenceEntryIds"] as? [String] ?? []
    }

    func toFirestoreData() -> [String: Any] {
        [
            "id":               id,
            "context":          context,
            "role":             role,
            "confidence":       confidence,
            "evidenceEntryIds": evidenceEntryIds
        ]
    }
}

// MARK: - VocabularyEntry

struct VocabularyEntry {

    let word: String
    let personalMeaning: String
    let confidence: Double
    let exampleUsage: String

    init(word: String, personalMeaning: String, confidence: Double, exampleUsage: String) {
        self.word           = word
        self.personalMeaning = personalMeaning
        self.confidence     = confidence
        self.exampleUsage   = exampleUsage
    }

    init?(from data: [String: Any]) {
        guard
            let word           = data["word"]           as? String,
            let personalMeaning = data["personalMeaning"] as? String,
            let confidence     = data["confidence"]     as? Double,
            let exampleUsage   = data["exampleUsage"]   as? String
        else { return nil }

        self.word            = word
        self.personalMeaning = personalMeaning
        self.confidence      = confidence
        self.exampleUsage    = exampleUsage
    }

    func toFirestoreData() -> [String: Any] {
        [
            "word":            word,
            "personalMeaning": personalMeaning,
            "confidence":      confidence,
            "exampleUsage":    exampleUsage
        ]
    }
}

// MARK: - SelfModel

struct SelfModel {

    let userId: String
    var version: Int
    var updatedAt: Date
    var profileMaturity: ProfileMaturity

    var coreRules: [SelfModelHypothesis]
    var protectiveStrategies: [ProtectiveHypothesis]
    var innerParts: [InnerPart]
    var values: [SelfModelHypothesis]
    var contradictions: [SelfModelHypothesis]
    var whatHelps: [SelfModelHypothesis]

    /// "What's gone quiet" — things the person used to write about and hasn't
    /// for a while. Derived arithmetically on the server (baseline frequency vs
    /// a silent recent window), never guessed by the model, because "you stopped
    /// mentioning X" is a factual claim about frequency and getting it wrong is
    /// the fastest way to prove the app isn't actually reading.
    var absences: [SelfModelHypothesis]

    /// `patternType == .bodySignal` hypotheses. Previously mined, scored, and
    /// then silently dropped — `updateSelfModel` had no bucket for them at all
    /// (Mirror v3 bucketing fix, mirror-v3-prd-2026-09-10.md §11.1).
    var bodySignals: [SelfModelHypothesis]

    var relationshipRoles: [RelationshipRole]
    var vocabulary: [VocabularyEntry]

    /// `"server"` when the nightly pipeline wrote this document. The client-side
    /// fallback assembler must not overwrite a server model with its own thinner
    /// bucketing — both used to write this doc with `merge: true` and
    /// incompatible rules, so whichever ran last won.
    var writtenBy: String

    /// Topics that must never be inferred about the user.
    var doNotInfer: [String]

    var isSurfaceable: Bool { version > 0 }

    private static let defaultDoNotInfer: [String] = [
        "diagnosis", "trauma_origin", "attachment_style", "mental_disorder"
    ]

    // MARK: - Empty factory

    static func empty(userId: String) -> SelfModel {
        SelfModel(
            userId: userId,
            version: 0,
            updatedAt: Date(),
            profileMaturity: .seed,
            coreRules: [],
            protectiveStrategies: [],
            innerParts: [],
            values: [],
            contradictions: [],
            whatHelps: [],
            absences: [],
            bodySignals: [],
            relationshipRoles: [],
            vocabulary: [],
            doNotInfer: defaultDoNotInfer
        )
    }

    // MARK: - Designated init

    init(
        userId: String,
        version: Int,
        updatedAt: Date = Date(),
        profileMaturity: ProfileMaturity = .seed,
        coreRules: [SelfModelHypothesis] = [],
        protectiveStrategies: [ProtectiveHypothesis] = [],
        innerParts: [InnerPart] = [],
        values: [SelfModelHypothesis] = [],
        contradictions: [SelfModelHypothesis] = [],
        whatHelps: [SelfModelHypothesis] = [],
        absences: [SelfModelHypothesis] = [],
        bodySignals: [SelfModelHypothesis] = [],
        relationshipRoles: [RelationshipRole] = [],
        vocabulary: [VocabularyEntry] = [],
        doNotInfer: [String] = defaultDoNotInfer,
        writtenBy: String = "client"
    ) {
        self.userId               = userId
        self.version              = version
        self.updatedAt            = updatedAt
        self.profileMaturity      = profileMaturity
        self.coreRules            = coreRules
        self.protectiveStrategies = protectiveStrategies
        self.innerParts           = innerParts
        self.values               = values
        self.contradictions       = contradictions
        self.whatHelps            = whatHelps
        self.absences             = absences
        self.bodySignals          = bodySignals
        self.relationshipRoles    = relationshipRoles
        self.vocabulary           = vocabulary
        self.writtenBy            = writtenBy
        // Always guarantee the hard-blocked topics are present
        var merged = Set(Self.defaultDoNotInfer)
        merged.formUnion(doNotInfer)
        self.doNotInfer = Array(merged)
    }

    // MARK: - Firestore deserialisation

    init?(from data: [String: Any]) {
        guard
            let userId    = data["userId"]    as? String,
            let version   = data["version"]   as? Int,
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        else { return nil }

        self.userId          = userId
        self.version         = version
        self.updatedAt       = updatedAt
        self.profileMaturity = ProfileMaturity(rawValue: data["profileMaturity"] as? String ?? "") ?? .seed

        self.coreRules = (data["coreRules"] as? [[String: Any]] ?? [])
            .compactMap { SelfModelHypothesis(from: $0) }
        self.protectiveStrategies = (data["protectiveStrategies"] as? [[String: Any]] ?? [])
            .compactMap { ProtectiveHypothesis(from: $0) }
        self.innerParts = (data["innerParts"] as? [[String: Any]] ?? [])
            .compactMap { InnerPart(from: $0) }
        self.values = (data["values"] as? [[String: Any]] ?? [])
            .compactMap { SelfModelHypothesis(from: $0) }
        self.contradictions = (data["contradictions"] as? [[String: Any]] ?? [])
            .compactMap { SelfModelHypothesis(from: $0) }
        self.whatHelps = (data["whatHelps"] as? [[String: Any]] ?? [])
            .compactMap { SelfModelHypothesis(from: $0) }
        self.absences = (data["absences"] as? [[String: Any]] ?? [])
            .compactMap { SelfModelHypothesis(from: $0) }
        self.bodySignals = (data["bodySignals"] as? [[String: Any]] ?? [])
            .compactMap { SelfModelHypothesis(from: $0) }
        self.writtenBy = data["writtenBy"] as? String ?? "client"
        self.relationshipRoles = (data["relationshipRoles"] as? [[String: Any]] ?? [])
            .compactMap { RelationshipRole(from: $0) }
        self.vocabulary = (data["vocabulary"] as? [[String: Any]] ?? [])
            .compactMap { VocabularyEntry(from: $0) }

        let stored = data["doNotInfer"] as? [String] ?? []
        var merged = Set(SelfModel.defaultDoNotInfer)
        merged.formUnion(stored)
        self.doNotInfer = Array(merged)
    }

    // MARK: - Firestore serialisation

    func toFirestoreData() -> [String: Any] {
        [
            "userId":               userId,
            "version":              version,
            "updatedAt":            Timestamp(date: updatedAt),
            "profileMaturity":      profileMaturity.rawValue,
            "coreRules":            coreRules.map { $0.toFirestoreData() },
            "protectiveStrategies": protectiveStrategies.map { $0.toFirestoreData() },
            "innerParts":           innerParts.map { $0.toFirestoreData() },
            "values":               values.map { $0.toFirestoreData() },
            "contradictions":       contradictions.map { $0.toFirestoreData() },
            "whatHelps":            whatHelps.map { $0.toFirestoreData() },
            "absences":             absences.map { $0.toFirestoreData() },
            "bodySignals":          bodySignals.map { $0.toFirestoreData() },
            "relationshipRoles":    relationshipRoles.map { $0.toFirestoreData() },
            "vocabulary":           vocabulary.map { $0.toFirestoreData() },
            "doNotInfer":           doNotInfer,
            "writtenBy":            writtenBy
        ]
    }

    // MARK: - Chat prompt context

    /// A compact block of only the person's user-CONFIRMED self-knowledge, for
    /// Daily Chat. Mirrors `MemoryProfile.promptContext()`'s style and framing.
    ///
    /// Deliberately excludes anything the user hasn't confirmed. Everywhere else
    /// in this file, an unconfirmed `SelfModelHypothesis` is shown to the user
    /// hedged, with a way to correct it (PI-010: corrections outrank inference).
    /// A live chat turn has neither — the model states things and moves on, so
    /// surfacing a merely-inferred core rule or value here would let the app
    /// assert as settled fact something it only ever guessed. Only
    /// `userStatus == .thisIsMe` entries qualify.
    func confirmedChatContext() -> String {
        let confirmedRules = coreRules.filter { $0.userStatus == .thisIsMe }.prefix(2)
        let confirmedValues = values.filter { $0.userStatus == .thisIsMe }.prefix(2)
        let roles = relationshipRoles.prefix(2)

        var lines: [String] = []
        for r in confirmedRules { lines.append("- \(r.hypothesis)") }
        for v in confirmedValues { lines.append("- Values: \(v.hypothesis)") }
        for role in roles { lines.append("- Role with \(role.context): \(role.role)") }

        guard !lines.isEmpty else { return "" }
        // Cap at 3 total regardless of how many qualified above.
        let capped = lines.prefix(3)

        return """

        THINGS THIS PERSON HAS CONFIRMED ABOUT THEMSELVES (context only — use to
        sound like you know them, never recite this list back or announce that
        you "noticed" it just now):
        \(capped.joined(separator: "\n"))
        """
    }
}
