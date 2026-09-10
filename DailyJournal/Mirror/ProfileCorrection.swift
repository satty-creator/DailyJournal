// ProfileCorrection.swift
// DailyJournal
//
// A user-submitted correction to their evolving self-model.
// Persisted at: users/{uid}/profileCorrections/{id}

import Foundation
import FirebaseFirestore

// MARK: - CorrectionFeedbackType

enum CorrectionFeedbackType: String {
    case thisIsMe       = "this_is_me"
    case halfTrue       = "half_true"
    case notMe          = "not_me"
    case missingContext = "missing_context"
}

// MARK: - ProfileCorrection

struct ProfileCorrection: Identifiable {

    let id: String
    let userId: String
    let feedbackType: CorrectionFeedbackType
    let patternId: String?
    let hypothesisId: String?
    let userCorrection: String
    let correctionCategory: String?
    let shouldUpdateSelfModel: Bool
    let createdAt: Date
    var appliedAt: Date?

    // MARK: - Designated init

    init(
        id: String = UUID().uuidString,
        userId: String,
        feedbackType: CorrectionFeedbackType,
        patternId: String? = nil,
        hypothesisId: String? = nil,
        userCorrection: String,
        correctionCategory: String? = nil,
        shouldUpdateSelfModel: Bool = true,
        createdAt: Date = Date(),
        appliedAt: Date? = nil
    ) {
        self.id                    = id
        self.userId                = userId
        self.feedbackType          = feedbackType
        self.patternId             = patternId
        self.hypothesisId          = hypothesisId
        self.userCorrection        = userCorrection
        self.correctionCategory    = correctionCategory
        self.shouldUpdateSelfModel = shouldUpdateSelfModel
        self.createdAt             = createdAt
        self.appliedAt             = appliedAt
    }

    // MARK: - Firestore deserialisation

    init?(from data: [String: Any]) {
        guard
            let id             = data["id"]             as? String,
            let userId         = data["userId"]         as? String,
            let feedbackRaw    = data["feedbackType"]   as? String,
            let feedbackType   = CorrectionFeedbackType(rawValue: feedbackRaw),
            let userCorrection = data["userCorrection"] as? String,
            let createdAt      = (data["createdAt"] as? Timestamp)?.dateValue()
        else { return nil }

        self.id                    = id
        self.userId                = userId
        self.feedbackType          = feedbackType
        self.patternId             = data["patternId"]          as? String
        self.hypothesisId          = data["hypothesisId"]       as? String
        self.userCorrection        = userCorrection
        self.correctionCategory    = data["correctionCategory"] as? String
        self.shouldUpdateSelfModel = data["shouldUpdateSelfModel"] as? Bool ?? true
        self.createdAt             = createdAt
        self.appliedAt             = (data["appliedAt"] as? Timestamp)?.dateValue()
    }

    // MARK: - Firestore serialisation

    func toFirestoreData() -> [String: Any] {
        var d: [String: Any] = [
            "id":                    id,
            "userId":                userId,
            "feedbackType":          feedbackType.rawValue,
            "userCorrection":        userCorrection,
            "shouldUpdateSelfModel": shouldUpdateSelfModel,
            "createdAt":             Timestamp(date: createdAt)
        ]
        if let patternId          { d["patternId"]          = patternId }
        if let hypothesisId       { d["hypothesisId"]       = hypothesisId }
        if let correctionCategory { d["correctionCategory"] = correctionCategory }
        if let appliedAt          { d["appliedAt"]          = Timestamp(date: appliedAt) }
        return d
    }
}
