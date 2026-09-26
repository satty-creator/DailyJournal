//
//  FirestoreSchema.swift
//  DailyJournal
//
//  The single source of truth for every Firestore path this app writes to.
//
//  WHY THIS FILE EXISTS
//  --------------------
//  Collection names used to be string literals scattered across a dozen services,
//  with a second, hand-maintained copy of the list inside
//  `AuthService.eraseFirestoreData`. The two drifted, and the consequence was a
//  privacy bug: the delete list said "reads" and "moods" while the services wrote
//  to "dailyReads" and "moodLogs", and `riverMarks` / `pushTokens` were never in
//  the list at all. Four collections — including `riverMarks`, which stores
//  verbatim phrases lifted from entries — survived "permanently delete my account".
//
//  RULE: any new user subcollection MUST be added to `userSubcollections` below,
//  and services MUST reference these constants instead of inlining a string.
//  Account deletion iterates this list, so a collection that isn't here is a
//  collection that never gets erased.
//
//  The project has no test target, and this folder is an Xcode synchronized root
//  group (every .swift here compiles into the app), so the drift guard lives
//  outside the build instead: `scripts/check-firestore-schema.sh` greps for every
//  `.collection("…")` literal in the Swift sources and fails if one isn't listed
//  below. Wire it into CI ahead of archive.
//

import Foundation

enum FirestoreSchema {

    // MARK: - Root

    /// Top-level collection of user documents. Each user doc holds only account
    /// metadata (`id`, `email`, `displayName`, `createdAt`, `lastActiveAt`,
    /// `timezone`, `aiConsentGranted`) — never entry content.
    static let users = "users"

    // MARK: - User subcollections

    /// Journal entries. Contains `content` — the user's raw entry text.
    static let entries = "entries"

    /// Per-entry structured analysis (emotions, needs, strategies, evidence quotes).
    static let entryAnalyses = "entryAnalyses"

    /// First-class, queryable episodes — situation → move → outcome — promoted
    /// out of `entryAnalyses[].episodes` (see JournalEvent.swift, EventService).
    /// Written by the same Prompt A extraction that already produces episodes;
    /// no new AI cost. Plaintext, like `entryAnalyses` — episodes never carry
    /// raw entry text, only extracted structure and short quoted phrases.
    static let events = "events"

    /// Mined cross-entry hypotheses awaiting or past surfacing.
    static let patternHypotheses = "patternHypotheses"

    /// Surfaced pattern callbacks, including evidence quotes and named entities.
    static let patternCallbacks = "patternCallbacks"

    /// Single doc (`current`) — the derived self model.
    static let selfModel = "selfModel"

    /// User corrections to inferences ("this doesn't sound like me").
    static let profileCorrections = "profileCorrections"

    /// Single doc (`current`) — declared focus, people likely to appear, disabled topics.
    static let lifeContext = "lifeContext"

    /// RETIRED (Mirror re-architecture). Daily Mirror cards, keyed by calendar
    /// date, including receipt quotes. Replaced by `mirrorCards`, keyed by
    /// hypothesis id and written server-side. No code reads or writes this
    /// collection any more; it stays in the list because existing accounts may
    /// still hold documents here. Do not remove the name.
    static let mirrors = "mirrors"

    /// The Mirror card deck: one card per surfaceable hypothesis, keyed by
    /// hypothesis id (not by date). Written server-side by
    /// `functions:mineUserInsights` / `functions:bootstrapMirror`
    /// (`generateMirrorDeck`); the client patches `userFeedback` onto an
    /// existing doc but never creates one. Includes receipt quotes, like the
    /// retired `mirrors` collection above.
    static let mirrorCards = "mirrorCards"

    /// Today's Read, one doc per local date (`yyyy-MM-dd`).
    /// NOTE: the name is `dailyReads`, not `reads`. The old delete list had this wrong.
    static let dailyReads = "dailyReads"

    /// Echoes — callbacks built on a verbatim `quote` from a past entry.
    static let echoes = "echoes"

    /// Mood logs, one doc per local date (`yyyy-MM-dd`).
    /// NOTE: the name is `moodLogs`, not `moods`. The old delete list had this wrong.
    static let moodLogs = "moodLogs"

    /// RETIRED (2026-08-13). The River feature was deleted: no code reads or writes
    /// this collection any more. It stays in the list because existing accounts still
    /// hold documents here — including `quoteAnchor`, an exact phrase lifted from an
    /// entry — and account deletion must keep erasing them. Do not remove the name.
    static let riverMarks = "riverMarks"

    /// FCM device tokens, one doc per token.
    static let pushTokens = "pushTokens"

    /// Single doc (`stats`) — derived entry count + cadence, see
    /// RollupStats.swift. Written incrementally by `JournalService` on every
    /// create/delete. Exists so a screen that only needs a number (Mirror's
    /// maturity gate) doesn't have to fetch and decrypt the full entry corpus
    /// to get one.
    static let rollups = "rollups"

    /// Daily Chat conversations, one doc per session, so a backgrounded chat
    /// survives and can be resumed. See ChatSession.swift — the `transcript`
    /// field is encrypted client-side exactly like `entries.content`, and
    /// weaving (conversation → journal entry) still happens entirely
    /// client-side; this collection exists for resumability, not so the
    /// server can read a conversation.
    static let chatSessions = "chatSessions"

    /// One doc per local date (`yyyy-MM-dd`) recording which hypothesis/line
    /// was shown on the Mirror tab that day, for the 14-day novelty gate.
    /// Client-written (`MirrorGraphService.markShown`). Was missing from this
    /// file — per the RULE above, that means it silently survived account
    /// deletion despite holding a `line` and `contentWords` lifted from the
    /// user's own writing (mirror-v3-prd-2026-09-10.md, Week 1).
    static let mirrorShown = "mirrorShown"

    /// Single doc (`current`) — "how Spilr writes" for this user: sharpness,
    /// muted pattern types, free-text style notes. Client-written
    /// (`StylePreferencesService`). Was missing from this file; same fix as
    /// `mirrorShown` above.
    static let stylePreferences = "stylePreferences"

    /// One doc per ISO week key — the Sunday weekly letter. Server-written
    /// (`functions:buildUserWeeklyLetter`); the client patches `openedAt`.
    /// Was missing from this file; same fix as `mirrorShown` above.
    static let mirrorLetters = "mirrorLetters"

    /// Mirror v3 Tier 0/3 — `facts`, `threads`, `firstSeven`. Server-written
    /// by `functions:computeUserDerived`, client read-only. Purely derived: a
    /// deleted `derived` doc costs nothing but a night's wait, which is why
    /// the whole collection is safe to overwrite wholesale every run.
    static let derived = "derived"

    /// Mirror v3 Tier 1 — deterministic observations, ids being
    /// `sha1(type + sorted terms)` so counts can change nightly while the
    /// user's own `shownAt`/`userStatus`/`notQuiteCount` survive. Server-owned;
    /// the client may update only those three fields (see firestore.rules).
    static let observations = "observations"

    /// Mirror v3 Tier 2 — one doc per local date, "today's one thing".
    /// Server-written; the client may update only `userStatus`, `shownAt` and
    /// `followUp`. Carries verbatim quotes from entries, so it must be erased
    /// with the account.
    static let readings = "readings"

    /// Mirror v3.1 — the Person Model (mirror-v3.1-person-model-2026-09-10.md
    /// §4). `patternHypotheses`' successor: one doc per hypothesis item
    /// (signature/rule/need/loop/distortion/person/coreBelief/value/strength),
    /// written server-side by Prompt F. The client patches `userStatus`,
    /// `shownAt`, `notQuiteCount` and `respondedAt` only (see firestore.rules).
    /// The non-correctable aggregate (needs, openHypotheses, trajectory)
    /// lives at `derived/personModel`, alongside `derived/facts`.
    static let personModel = "personModel"

    /// The audit trail for Daily Chat's write-back into the Person Model /
    /// LifeContext — one doc per applied op, with the verbatim quote that
    /// licensed it, listed and undoable in "What changed" (SelfModelView).
    /// Client-written (`SelfModelService.recordModelOp`). See ModelOp.swift.
    static let modelOps = "modelOps"

    /// Every user subcollection this app has ever written to.
    ///
    /// Account deletion walks this list. Order is irrelevant. Retired collections
    /// stay in the list forever — existing accounts may still hold their documents,
    /// and removing the name would silently orphan that data.
    static let userSubcollections: [String] = [
        entries,
        entryAnalyses,
        events,
        patternHypotheses,
        patternCallbacks,
        selfModel,
        profileCorrections,
        lifeContext,
        mirrors,
        mirrorCards,
        dailyReads,
        echoes,
        moodLogs,
        riverMarks,
        pushTokens,
        rollups,
        chatSessions,
        mirrorShown,
        stylePreferences,
        mirrorLetters,
        derived,
        observations,
        readings,
        personModel,
        modelOps,
    ]

    // MARK: - Storage

    /// Storage folder holding entry photos, relative to a user id.
    static func entryPhotosPath(for uid: String) -> String {
        "\(users)/\(uid)/entryPhotos"
    }
}
