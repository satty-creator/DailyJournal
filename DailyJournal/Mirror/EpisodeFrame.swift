// EpisodeFrame.swift
// DailyJournal
//
// A single narrative episode extracted from a journal entry.
// Embedded in EntryAnalysis.episodes[] — not a separate Firestore document.

import Foundation
import FirebaseFirestore

struct EpisodeFrame: Identifiable {

    let episodeId: String
    let situation: String
    let emotions: [String]
    let bodySignals: [String]
    let protectiveStrategy: String?
    let need: String?
    let outcome: String?

    var id: String { episodeId }

    // MARK: - Designated init

    init(
        episodeId: String = UUID().uuidString,
        situation: String,
        emotions: [String],
        bodySignals: [String],
        protectiveStrategy: String? = nil,
        need: String? = nil,
        outcome: String? = nil
    ) {
        self.episodeId           = episodeId
        self.situation           = situation
        self.emotions            = emotions
        self.bodySignals         = bodySignals
        self.protectiveStrategy  = protectiveStrategy
        self.need                = need
        self.outcome             = outcome
    }

    // MARK: - Firestore deserialisation

    init?(from data: [String: Any]) {
        guard
            let episodeId = data["episodeId"] as? String,
            let situation = data["situation"] as? String
        else { return nil }

        self.episodeId          = episodeId
        self.situation          = situation
        self.emotions           = data["emotions"]    as? [String] ?? []
        self.bodySignals        = data["bodySignals"] as? [String] ?? []
        self.protectiveStrategy = data["protectiveStrategy"] as? String
        self.need               = data["need"]    as? String
        self.outcome            = data["outcome"] as? String
    }

    // MARK: - Firestore serialisation

    func toFirestoreData() -> [String: Any] {
        var d: [String: Any] = [
            "episodeId":  episodeId,
            "situation":  situation,
            "emotions":   emotions,
            "bodySignals": bodySignals
        ]
        if let protectiveStrategy { d["protectiveStrategy"] = protectiveStrategy }
        if let need               { d["need"]               = need }
        if let outcome            { d["outcome"]            = outcome }
        return d
    }
}
