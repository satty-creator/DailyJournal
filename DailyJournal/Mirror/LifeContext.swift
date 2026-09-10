// LifeContext.swift
// DailyJournal
//
// User-supplied context that shapes Mirror Engine tone and topic selection.
// Persisted at: users/{uid}/lifeContext (single document per user).

import Foundation
import FirebaseFirestore

// MARK: - Enums

enum LifeSeason: String {
    case student        = "student"
    case buildingCareer = "building_career"
    case burnedOut      = "burned_out"
    case healing        = "healing"
    case newParent      = "new_parent"
    case betweenThings  = "between_things"
}

enum PreferredDepth: String {
    case gentle   = "gentle"
    case balanced = "balanced"
    case deep     = "deep"
}

// MARK: - LifeContext

struct LifeContext {

    let userId: String
    var currentSeason: LifeSeason?
    var primaryFocus: [String]
    var peopleLikelyToAppear: [String]
    var sensitiveTopicsDisabled: [String]
    var preferredDepth: PreferredDepth
    var updatedAt: Date

    // MARK: - Empty factory

    static func empty(userId: String) -> LifeContext {
        LifeContext(
            userId: userId,
            currentSeason: nil,
            primaryFocus: [],
            peopleLikelyToAppear: [],
            sensitiveTopicsDisabled: [],
            preferredDepth: .balanced,
            updatedAt: Date()
        )
    }

    // MARK: - Designated init

    init(
        userId: String,
        currentSeason: LifeSeason? = nil,
        primaryFocus: [String] = [],
        peopleLikelyToAppear: [String] = [],
        sensitiveTopicsDisabled: [String] = [],
        preferredDepth: PreferredDepth = .balanced,
        updatedAt: Date = Date()
    ) {
        self.userId                  = userId
        self.currentSeason           = currentSeason
        self.primaryFocus            = primaryFocus
        self.peopleLikelyToAppear    = peopleLikelyToAppear
        self.sensitiveTopicsDisabled = sensitiveTopicsDisabled
        self.preferredDepth          = preferredDepth
        self.updatedAt               = updatedAt
    }

    // MARK: - Firestore deserialisation

    init?(from data: [String: Any]) {
        guard
            let userId    = data["userId"]    as? String,
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        else { return nil }

        self.userId                  = userId
        self.currentSeason           = (data["currentSeason"] as? String).flatMap(LifeSeason.init(rawValue:))
        self.primaryFocus            = data["primaryFocus"]            as? [String] ?? []
        self.peopleLikelyToAppear    = data["peopleLikelyToAppear"]    as? [String] ?? []
        self.sensitiveTopicsDisabled = data["sensitiveTopicsDisabled"] as? [String] ?? []
        self.preferredDepth          = PreferredDepth(rawValue: data["preferredDepth"] as? String ?? "") ?? .balanced
        self.updatedAt               = updatedAt
    }

    // MARK: - Firestore serialisation

    func toFirestoreData() -> [String: Any] {
        var d: [String: Any] = [
            "userId":                  userId,
            "primaryFocus":            primaryFocus,
            "peopleLikelyToAppear":    peopleLikelyToAppear,
            "sensitiveTopicsDisabled": sensitiveTopicsDisabled,
            "preferredDepth":          preferredDepth.rawValue,
            "updatedAt":               Timestamp(date: updatedAt)
        ]
        if let currentSeason { d["currentSeason"] = currentSeason.rawValue }
        return d
    }
}
