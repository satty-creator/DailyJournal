// MirrorCard.swift
// DailyJournal
//
// The Mirror Engine's daily card — a five-part, evidence-backed reflection
// surfaced once per day. Reuses the tone/sharpness/safety vocabulary from
// `DailyReadModels.swift`.
// Firestore path: users/{uid}/mirrorCards/{localDate}

import Foundation
import FirebaseFirestore

// MARK: - MirrorNarrative

/// AI-generated narrative synthesis of the user's top patterns ("Story So Far").
/// Regenerated weekly or when hypotheses change significantly.
struct MirrorNarrative {
    struct ShiftSignal {
        enum Direction: String { case growing, fading }
        let direction: Direction
        let signal: String
        let evidence: String
    }

    let narrative: String
    let shifting: [ShiftSignal]
    let openQuestion: String?
    let generatedAt: Date

    init(narrative: String, shifting: [ShiftSignal] = [], openQuestion: String? = nil, generatedAt: Date = Date()) {
        self.narrative    = narrative
        self.shifting     = shifting
        self.openQuestion = openQuestion
        self.generatedAt  = generatedAt
    }

    init?(from data: [String: Any]) {
        guard let narrative = data["narrative"] as? String, !narrative.isEmpty else { return nil }
        self.narrative    = narrative
        self.openQuestion = data["openQuestion"] as? String
        self.generatedAt  = (data["generatedAt"] as? Timestamp)?.dateValue() ?? Date()
        self.shifting     = (data["shifting"] as? [[String: Any]] ?? []).compactMap { item in
            guard let dir = item["direction"] as? String, let sig = item["signal"] as? String else { return nil }
            return ShiftSignal(direction: dir == "growing" ? .growing : .fading, signal: sig, evidence: item["evidence"] as? String ?? "")
        }
    }

    func toFirestoreData() -> [String: Any] {
        var d: [String: Any] = [
            "narrative":   narrative,
            "generatedAt": Timestamp(date: generatedAt),
            "shifting":    shifting.map { ["direction": $0.direction.rawValue, "signal": $0.signal, "evidence": $0.evidence] }
        ]
        if let openQuestion { d["openQuestion"] = openQuestion }
        return d
    }
}

// MARK: - MirrorReceipt

/// A single piece of evidence shown below the mirror sentence.
struct MirrorReceipt {
    let quote: String
    let whyItMatters: String
    let entryDate: Date?

    init(quote: String, whyItMatters: String, entryDate: Date? = nil) {
        self.quote         = quote
        self.whyItMatters  = whyItMatters
        self.entryDate     = entryDate
    }

    init?(from data: [String: Any]) {
        guard
            let quote        = data["quote"]        as? String,
            let whyItMatters = data["whyItMatters"] as? String
        else { return nil }
        self.quote         = quote
        self.whyItMatters  = whyItMatters
        self.entryDate     = (data["entryDate"] as? Timestamp)?.dateValue()
    }

    func toFirestoreData() -> [String: Any] {
        var d: [String: Any] = [
            "quote":        quote,
            "whyItMatters": whyItMatters
        ]
        if let entryDate { d["entryDate"] = Timestamp(date: entryDate) }
        return d
    }
}

// MARK: - MirrorFeedback

enum MirrorFeedback: String {
    case thisIsMe    = "this_is_me"
    case almost      = "almost"
    case notMe       = "not_me"
    case tooIntense  = "too_intense"
    case askTomorrow = "ask_tomorrow"
}

// MARK: - MirrorComponents

struct MirrorComponents {
    let trigger: String?
    let move: String?
    let benefit: String?
    let cost: String?
    let exception: String?

    init?(from data: [String: Any]) {
        guard !data.isEmpty else { return nil }
        self.trigger   = data["trigger"]   as? String
        self.move      = data["move"]      as? String
        self.benefit   = data["benefit"]   as? String
        self.cost      = data["cost"]      as? String
        self.exception = data["exception"] as? String
    }

    init(trigger: String?, move: String?, benefit: String?, cost: String?, exception: String?) {
        self.trigger   = trigger
        self.move      = move
        self.benefit   = benefit
        self.cost      = cost
        self.exception = exception
    }

    func toFirestoreData() -> [String: Any] {
        var d: [String: Any] = [:]
        if let trigger   { d["trigger"]   = trigger }
        if let move      { d["move"]      = move }
        if let benefit   { d["benefit"]   = benefit }
        if let cost      { d["cost"]      = cost }
        if let exception { d["exception"] = exception }
        return d
    }

    var isComplete: Bool {
        trigger != nil && move != nil && benefit != nil && cost != nil
    }
}

// MARK: - MirrorCard

struct MirrorCard: Identifiable {

    // ── Core fields ──────────────────────────────────────────────────────
    let id: String
    let userId: String
    let localDate: Date
    let readText: String
    let receiptChips: [String]
    let replyPrompt: String
    let shareSafeText: String
    let notificationCopy: String
    let tone: ReadTone
    let sharpnessLevel: ReadSharpness
    let safetyLevel: ReadSafetyLevel
    let confidence: Double
    let shouldShow: Bool
    let doNotShowReason: String?
    let sourceEntryIds: [String]
    let sourcePatternIds: [String]
    var userFeedback: MirrorFeedback?
    var detailedFeedbackCode: ReadRejectionCode?
    let modelProvider: String
    let modelName: String
    let promptVersion: String
    let createdAt: Date

    // ── Five-part Mirror body ───────────────────────────────────────────
    let headline: String
    let mirrorSentence: String
    let whyThisCameUp: String
    let patternName: String?
    let receipts: [MirrorReceipt]
    let possibleRead: String?
    let tinyExperiment: String?
    let tomorrowCallbackQuestion: String?
    let shareSafeSummary: String

    // ── Structural components (quality constraint, not rendered directly) ──
    let components: MirrorComponents?
    let temporalAnchor: String?

    // ── L0/L1 fields (mirror-line-v1, Phase 3) ──────────────────────────
    // Optional / defaulted so a card written by the older mirror-write-v2
    // pipeline still decodes — see `displayLine` below for the fallback.
    let line: String?
    let move: String?
    let shape: MirrorShape?
    let question: String?
    let lintPassed: Bool?
    let deckRank: Int?

    // MARK: - Computed

    var isSurfaceable: Bool {
        shouldShow && safetyLevel.isSurfaceable && !readText.isEmpty
    }

    /// The L0 line to render. Falls back to `mirrorSentence` for any card
    /// written before the `line` field existed, so Phase 1/2 UI can ship
    /// ahead of the Phase 3 writer without a blank card in between.
    var displayLine: String {
        if let line, !line.isEmpty { return line }
        return mirrorSentence
    }

    // MARK: - Designated init

    init(
        id: String? = nil,
        userId: String,
        localDate: Date = Date(),
        readText: String,
        receiptChips: [String] = [],
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
        userFeedback: MirrorFeedback? = nil,
        detailedFeedbackCode: ReadRejectionCode? = nil,
        modelProvider: String,
        modelName: String,
        promptVersion: String,
        createdAt: Date = Date(),
        headline: String,
        mirrorSentence: String,
        whyThisCameUp: String,
        patternName: String? = nil,
        receipts: [MirrorReceipt] = [],
        possibleRead: String? = nil,
        tinyExperiment: String? = nil,
        tomorrowCallbackQuestion: String? = nil,
        shareSafeSummary: String,
        components: MirrorComponents? = nil,
        temporalAnchor: String? = nil,
        line: String? = nil,
        move: String? = nil,
        shape: MirrorShape? = nil,
        question: String? = nil,
        lintPassed: Bool? = nil,
        deckRank: Int? = nil
    ) {
        // No longer falls back to a per-date key (MirrorCard.dateKey, deleted
        // — a leftover of the retired per-date `mirrors/{yyyy-MM-dd}` scheme;
        // real docs are keyed by hypothesis id). A UUID is a safer default
        // for a caller that genuinely has no id yet than silently colliding
        // two same-day cards under one key.
        self.id                       = id ?? UUID().uuidString
        self.userId                   = userId
        self.localDate                = Calendar.current.startOfDay(for: localDate)
        self.readText                 = readText
        self.receiptChips             = receiptChips
        self.replyPrompt              = replyPrompt
        self.shareSafeText            = shareSafeText
        self.notificationCopy         = notificationCopy
        self.tone                     = tone
        self.sharpnessLevel           = sharpnessLevel
        self.safetyLevel              = safetyLevel
        self.confidence               = confidence
        self.shouldShow               = shouldShow
        self.doNotShowReason          = doNotShowReason
        self.sourceEntryIds           = sourceEntryIds
        self.sourcePatternIds         = sourcePatternIds
        self.userFeedback             = userFeedback
        self.detailedFeedbackCode     = detailedFeedbackCode
        self.modelProvider            = modelProvider
        self.modelName                = modelName
        self.promptVersion            = promptVersion
        self.createdAt                = createdAt
        self.headline                 = headline
        self.mirrorSentence           = mirrorSentence
        self.whyThisCameUp            = whyThisCameUp
        self.patternName              = patternName
        self.receipts                 = receipts
        self.possibleRead             = possibleRead
        self.tinyExperiment           = tinyExperiment
        self.tomorrowCallbackQuestion = tomorrowCallbackQuestion
        self.shareSafeSummary         = shareSafeSummary
        self.components               = components
        self.temporalAnchor           = temporalAnchor
        self.line                     = line
        self.move                     = move
        self.shape                    = shape
        self.question                 = question
        self.lintPassed               = lintPassed
        self.deckRank                 = deckRank
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

        self.id             = id
        self.userId         = userId
        // Normalised to match the designated init — decoded cards used to
        // keep whatever time-of-day the server wrote instead of startOfDay,
        // so a card round-tripped through the memberwise init disagreed with
        // one read straight from Firestore.
        self.localDate      = Calendar.current.startOfDay(for: localDate)
        self.readText       = readText
        self.receiptChips   = data["receiptChips"]   as? [String] ?? []
        self.replyPrompt    = replyPrompt
        self.shareSafeText  = data["shareSafeText"]  as? String ?? readText
        self.notificationCopy = data["notificationCopy"] as? String ?? ""
        self.tone           = tone
        self.sharpnessLevel = ReadSharpness(rawValue: data["sharpnessLevel"] as? String ?? "") ?? .direct
        self.safetyLevel    = ReadSafetyLevel(rawValue: data["safetyLevel"]  as? String ?? "") ?? .none
        self.confidence     = data["confidence"] as? Double ?? 0
        self.shouldShow     = data["shouldShow"] as? Bool ?? true
        self.doNotShowReason    = data["doNotShowReason"]    as? String
        self.sourceEntryIds     = data["sourceEntryIds"]     as? [String] ?? []
        self.sourcePatternIds   = data["sourcePatternIds"]   as? [String] ?? []
        self.userFeedback   = (data["userFeedback"] as? String).flatMap(MirrorFeedback.init(rawValue:))
        self.detailedFeedbackCode = (data["detailedFeedbackCode"] as? String).flatMap(ReadRejectionCode.init(rawValue:))
        self.modelProvider  = data["modelProvider"] as? String ?? "local"
        self.modelName      = data["modelName"]     as? String ?? "local-engine"
        self.promptVersion  = data["promptVersion"] as? String ?? "unknown"
        self.createdAt      = createdAt

        self.headline                 = data["headline"]       as? String ?? ""
        self.mirrorSentence           = data["mirrorSentence"] as? String ?? ""
        self.whyThisCameUp            = data["whyThisCameUp"]  as? String ?? ""
        self.patternName              = data["patternName"]    as? String
        self.receipts                 = (data["receipts"] as? [[String: Any]] ?? [])
            .compactMap { MirrorReceipt(from: $0) }
        self.possibleRead             = data["possibleRead"]             as? String
        self.tinyExperiment           = data["tinyExperiment"]           as? String
        self.tomorrowCallbackQuestion = data["tomorrowCallbackQuestion"] as? String
        self.shareSafeSummary         = data["shareSafeSummary"] as? String ?? ""
        self.components               = (data["components"] as? [String: Any]).flatMap { MirrorComponents(from: $0) }
        self.temporalAnchor           = data["temporalAnchor"] as? String

        self.line       = data["line"] as? String
        self.move       = data["move"] as? String
        self.shape      = (data["shape"] as? String).flatMap(MirrorShape.init(rawValue:))
        self.question   = data["question"] as? String
        self.lintPassed = data["lintPassed"] as? Bool
        self.deckRank   = data["deckRank"] as? Int
    }

    // MARK: - Firestore serialisation

    func toFirestoreData() -> [String: Any] {
        var d: [String: Any] = [
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
            "modelProvider":      modelProvider,
            "modelName":          modelName,
            "promptVersion":      promptVersion,
            "createdAt":          Timestamp(date: createdAt),
            "headline":           headline,
            "mirrorSentence":     mirrorSentence,
            "whyThisCameUp":      whyThisCameUp,
            "receipts":           receipts.map { $0.toFirestoreData() },
            "shareSafeSummary":   shareSafeSummary
        ]
        if let doNotShowReason        { d["doNotShowReason"]          = doNotShowReason }
        if let userFeedback           { d["userFeedback"]             = userFeedback.rawValue }
        if let detailedFeedbackCode   { d["detailedFeedbackCode"]     = detailedFeedbackCode.rawValue }
        if let patternName            { d["patternName"]              = patternName }
        if let possibleRead           { d["possibleRead"]             = possibleRead }
        if let tinyExperiment         { d["tinyExperiment"]           = tinyExperiment }
        if let tomorrowCallbackQuestion { d["tomorrowCallbackQuestion"] = tomorrowCallbackQuestion }
        if let components             { d["components"]               = components.toFirestoreData() }
        if let temporalAnchor         { d["temporalAnchor"]           = temporalAnchor }
        if let line                   { d["line"]                     = line }
        if let move                   { d["move"]                     = move }
        if let shape                  { d["shape"]                    = shape.rawValue }
        if let question               { d["question"]                 = question }
        if let lintPassed             { d["lintPassed"]               = lintPassed }
        if let deckRank               { d["deckRank"]                 = deckRank }
        return d
    }
}
