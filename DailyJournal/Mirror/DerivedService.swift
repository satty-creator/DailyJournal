//
//  DerivedService.swift
//  DailyJournal
//
//  The client's read side of the Mirror v3 / v3.1 derived layer:
//    users/{uid}/derived/facts        — Tier 0 counts (MirrorFacts)
//    users/{uid}/derived/firstSeven   — the 7-entry unlock card
//    users/{uid}/derived/personModel  — needs, open hypotheses (PersonModelAggregate)
//    users/{uid}/readings/{date}      — today's one thing (Reading)
//    users/{uid}/personModel/*        — Person Model items (PersonModelItem)
//
//  All server-written. The only client writes are the three feedback fields on
//  a reading, which firestore.rules narrows to exactly those keys — see §5.2's
//  feedback semantics and the rules file.
//

import Foundation
import FirebaseFirestore

@MainActor
final class DerivedService: ObservableObject {

    static let shared = DerivedService()
    private init() {}

    @Published private(set) var facts: MirrorFacts = .empty(userId: "")
    @Published private(set) var reading: Reading?
    @Published private(set) var firstSeven: FirstSevenCard?
    /// Mirror v3.1 — active Person Model items, newest evidence first. Feeds
    /// "WHAT SPILR THINKS IT KNOWS" (signatures) on the Mirror tab.
    @Published private(set) var personModelItems: [PersonModelItem] = []
    /// `derived/personModel` — needs, open hypotheses, tonight's question.
    @Published private(set) var personModel: PersonModelAggregate = .empty
    @Published private(set) var isLoading = false
    /// True when the LAST `load()` could not reach either the server or a
    /// warm local cache for some part of this layer — distinct from the docs
    /// genuinely not existing yet (a brand-new / never-computed account,
    /// which is `false` here and shows as `!facts.isFresh` instead). Drives
    /// the "couldn't reach the server" empty state rather than the ordinary
    /// unlock-hint one — see MirrorView's empty-state branch.
    @Published private(set) var loadFailed = false

    private var db: Firestore { Firestore.firestore() }

    // MARK: - Load

    /// Loads the whole derived layer, in dependency order: `derived/*` first,
    /// THEN today's reading — because the reading's document id is a date key
    /// computed from `facts.timezone` (`todayKey()`), and asking for it before
    /// `facts` has loaded means asking under whatever timezone happened to be
    /// in memory from the previous session (or the device's own, on a cold
    /// launch), which can be a day off from what the server actually keyed it
    /// under. Costs one extra sequential round trip, only on the very first
    /// load of a session.
    ///
    /// Reads use `.default` (server-then-cache), not `.server`. These
    /// documents are rewritten once a night by a job the device knows nothing
    /// about, so `FirestoreCacheFirst`'s "an empty cache answer is a real
    /// answer" contract is wrong here — a cache-first read can show
    /// yesterday's numbers next to today's date, which is exactly the class
    /// of quiet wrongness Mirror v3 exists to remove. But a strict `.server`
    /// read has no working fallback on a cold install: the on-disk cache is
    /// empty (a reinstall wipes it), so ANY transient failure — including
    /// just not having finished bringing the connection up yet — nils out the
    /// whole layer with nothing to fall back to. `.default` keeps the
    /// "prefer fresh" intent (it always tries the server first when online)
    /// while actually degrading to cache instead of failing outright when
    /// truly offline.
    func load(for userId: String) async {
        guard !userId.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        var failed = false

        let derived = await fetchDerived(userId: userId)
        if derived.succeeded {
            if let f = derived.facts { facts = f }
            firstSeven = derived.firstSeven
            personModel = derived.personModel ?? .empty
        } else {
            failed = true
        }

        let key = todayKey()
        let today = await fetchReading(userId: userId, dateKey: key)
        if today.succeeded {
            reading = today.reading
        } else {
            failed = true
        }

        let items = await fetchPersonModelItems(userId: userId)
        if items.succeeded {
            personModelItems = items.items
        } else {
            failed = true
        }

        loadFailed = failed
    }

    private func fetchDerived(userId: String) async
    -> (facts: MirrorFacts?, firstSeven: FirstSevenCard?,
        personModel: PersonModelAggregate?, succeeded: Bool) {
        let col = db.collection("users").document(userId).collection("derived")
        guard let snapshot = try? await col.getDocuments(source: .default) else {
            return (nil, nil, nil, false)
        }

        var facts: MirrorFacts?
        var firstSeven: FirstSevenCard?
        var personModel: PersonModelAggregate?
        for doc in snapshot.documents {
            switch doc.documentID {
            case "facts":       facts = MirrorFacts(from: doc.data())
            case "firstSeven":  firstSeven = FirstSevenCard(from: doc.data())
            case "personModel": personModel = PersonModelAggregate(from: doc.data())
            default:            break
            }
        }
        return (facts, firstSeven, personModel, true)
    }

    /// Active Person Model items, most recent evidence first, capped the same
    /// as the server's own bounded reads (PERSON_MODEL_ITEM_LIMIT).
    private func fetchPersonModelItems(userId: String) async -> (items: [PersonModelItem], succeeded: Bool) {
        let col = db.collection("users").document(userId).collection("personModel")
        guard let snapshot = try? await col.limit(to: 60).getDocuments(source: .default) else {
            return ([], false)
        }
        let items = snapshot.documents
            .compactMap { PersonModelItem(id: $0.documentID, from: $0.data()) }
            .filter(\.isActive)
            .sorted { ($0.lastEvidenceAt ?? .distantPast) > ($1.lastEvidenceAt ?? .distantPast) }
        return (items, true)
    }

    private func fetchReading(userId: String, dateKey: String) async -> (reading: Reading?, succeeded: Bool) {
        let readingsCol = db.collection("users").document(userId).collection("readings")
        guard let snap = try? await readingsCol.document(dateKey).getDocument(source: .default) else {
            return (nil, false)
        }
        if snap.exists, let data = snap.data() {
            return (Reading(from: data), true)
        }

        // No doc at exactly today's key. Before calling this "no reading
        // today" (a legitimate, common state), check for the off-by-one this
        // account might be carrying: readings written before `timezone` was
        // set on the user doc are keyed in UTC (functions/index.js), while
        // `dateKey` here is computed in the device's local time. Take the
        // newest reading doc and accept it only if its own date is within a
        // day of today — anything older really is "nothing for today".
        guard let latest = try? await readingsCol
            .order(by: FieldPath.documentID(), descending: true)
            .limit(to: 1)
            .getDocuments(source: .default)
        else {
            // The primary lookup succeeded (we know there's no doc at
            // `dateKey`); a failure here is just "no fallback available",
            // not a load failure.
            return (nil, true)
        }
        guard let doc = latest.documents.first,
              isWithinOneDay(of: doc.documentID, comparedTo: dateKey)
        else {
            return (nil, true)
        }
        return (Reading(from: doc.data()), true)
    }

    /// `a` and `b` are `yyyy-MM-dd` date-key strings. True when they're the
    /// same day or adjacent — the span a UTC/local timezone mismatch can
    /// introduce, never more.
    private func isWithinOneDay(of a: String, comparedTo b: String) -> Bool {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        guard let dateA = fmt.date(from: a), let dateB = fmt.date(from: b) else { return false }
        return abs(dateA.timeIntervalSince(dateB)) <= 36 * 3600
    }

    /// Today's local date key, in the timezone the SERVER used to build the
    /// documents. Using the device's current timezone instead would miss the
    /// reading entirely for anyone who has travelled.
    func todayKey() -> String {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: facts.timezone) ?? .current
        return fmt.string(from: Date())
    }

    // MARK: - Feedback (§5.2)

    /// "That's me" / "Not quite" on today's reading.
    ///
    /// Writes to three places, each for a different reason:
    ///   - the reading, so the card shows its own state immediately;
    ///   - the source observation/personModel item, so the ranking learns
    ///     (two "not quite"s retire it — `notQuiteCount` is what the server
    ///     checks);
    ///   - StylePreferences, but ONLY when the follow-up chip says "too much".
    ///     "Wrong" and "half" are not requests for a softer voice, and
    ///     treating them as one is how an app ends up mushy for everyone who
    ///     ever disagreed with it.
    ///
    /// `.huh` ("new to me") writes the reading's own status for the "Didn't
    /// know that" metric but never touches `notQuiteCount` or sharpness — it
    /// is not a rejection, it's the strongest kind of praise this surface can
    /// get short of "That's me".
    func recordReadingFeedback(
        _ feedback: ReadingFeedback,
        reason: ReadingMissReason? = nil,
        reading: Reading,
        userId: String
    ) {
        guard !userId.isEmpty else { return }
        let userRef = db.collection("users").document(userId)

        userRef.collection("readings").document(reading.date).updateData([
            "userStatus": feedback.rawValue,
            "shownAt": Timestamp(date: Date()),
            "followUp": reason?.rawValue as Any
        ]) { _ in }

        if let sourceId = reading.sourceId, feedback != .huh {
            var patch: [String: Any] = [
                "userStatus": feedback.rawValue,
                "shownAt": Timestamp(date: Date())
            ]
            if feedback == .almost {
                patch["notQuiteCount"] = FieldValue.increment(Int64(1))
            }
            // v3.1 signatures live in personModel; a v3.0-only reading's
            // source is an observation. Both collections accept the same
            // field-scoped update shape (firestore.rules).
            let collection = reading.sourceType == "SIGNATURE" ? "personModel" : "observations"
            userRef.collection(collection).document(sourceId)
                .updateData(patch) { _ in }
        }

        if feedback == .almost, reason == .tooMuch {
            StylePreferencesService.shared.recordFeedback(
                .tooIntense, patternType: reading.sourceType ?? "observation", userId: userId)
        }

        // Local echo so the card updates without a refetch.
        if let current = self.reading, current.date == reading.date {
            self.reading = current.withUserStatus(feedback.rawValue) ?? current
        }
    }

    /// Records that today's reading was actually displayed, for the 14-day
    /// novelty gate. Writes `observationId` + `terms` alongside the existing
    /// `mirrorShown` fields so the server's ObservationScore can penalise a
    /// repeat — a day doc without them counts as maximum novelty, never zero.
    func markReadingShown(_ reading: Reading, userId: String) {
        guard !userId.isEmpty, !reading.silence, let observationId = reading.sourceId else { return }
        db.collection("users").document(userId)
            .collection("mirrorShown").document(reading.date)
            .setData([
                "observationId": observationId,
                "line": reading.line,
                "terms": reading.proof.map { proof in
                    proof.quotes.compactMap { $0.text }
                } ?? [],
                "evidenceEntryIds": reading.proof?.entryIds ?? [],
                "shownAt": Timestamp(date: Date())
            ], merge: true) { _ in }
    }

    /// User-set correction on a Person Model item — "That's me" / "Not me",
    /// including the version of that gesture that now happens inside a Daily
    /// Chat conversation (see AIService+Chat's `extractModelOps` and
    /// SelfModelService's write-back). Writes directly to the item doc; the
    /// client may patch only `userStatus`/`shownAt`/`notQuiteCount`/
    /// `respondedAt` (firestore.rules) — this call only ever touches the first
    /// and last of those.
    ///
    /// No optimistic local echo: `PersonModelItem`'s fields are all `let` (it
    /// decodes straight off a snapshot, like every other model in this file),
    /// so reflecting this instantly would mean rebuilding the whole item from
    /// its raw dict here too. The next `load()` picks it up; this collection
    /// isn't rendered anywhere that's visible mid-conversation.
    func markPersonModelItemStatus(itemId: String, userStatus: String, userId: String) {
        guard !userId.isEmpty, !itemId.isEmpty else { return }
        db.collection("users").document(userId)
            .collection("personModel").document(itemId)
            .updateData([
                "userStatus": userStatus,
                "respondedAt": Timestamp(date: Date())
            ]) { _ in }
    }
}

// MARK: - Reading mutation helper

private extension Reading {
    /// Structs are immutable here by design (everything but feedback is
    /// server-owned), so a local echo rebuilds rather than mutates.
    func withUserStatus(_ status: String) -> Reading? {
        var data: [String: Any] = [
            "date": date, "userId": userId, "line": line,
            "lintPassed": lintPassed, "silence": silence, "userStatus": status,
            "computedAt": Timestamp(date: computedAt)
        ]
        if let templateText { data["templateText"] = templateText }
        if let move { data["move"] = move }
        if let question { data["question"] = question }
        if let lintReason { data["lintReason"] = lintReason }
        if let reason { data["reason"] = reason }
        if let unlockHint { data["unlockHint"] = unlockHint }
        if let sourceId, let sourceType {
            data["source"] = ["id": sourceId, "type": sourceType, "kind": "observation"]
        }
        if let shape { data["shape"] = shape }
        if let receipt {
            data["receipt"] = [
                "quote": receipt.quote,
                "entryId": receipt.entryId as Any,
                "date": receipt.date as Any,
                "relativeLabel": receipt.relativeLabel as Any
            ]
        }
        return Reading(from: data)
    }
}

// MARK: - FirstSevenCard

/// `users/{uid}/derived/firstSeven` — replaces First Sketch (M8).
struct FirstSevenCard {
    struct Card: Identifiable {
        let eyebrow: String
        let text: String
        var id: String { eyebrow + text }
    }

    let cards: [Card]
    let threadTitle: String?
    let threadN: Int?
    let observationText: String?
    let question: String?
    let entriesAtUnlock: Int

    init?(from data: [String: Any]) {
        let raw = data["cards"] as? [[String: Any]] ?? []
        self.cards = raw.compactMap { c in
            guard let eyebrow = c["eyebrow"] as? String,
                  let text = c["text"] as? String else { return nil }
            return Card(eyebrow: eyebrow, text: text)
        }
        let thread = data["thread"] as? [String: Any]
        self.threadTitle = thread?["title"] as? String
        self.threadN = thread?["n"] as? Int
        self.observationText = (data["observation"] as? [String: Any])?["text"] as? String
        self.question = data["question"] as? String
        self.entriesAtUnlock = data["entriesAtUnlock"] as? Int ?? 7
        if cards.isEmpty && threadTitle == nil && observationText == nil { return nil }
    }
}
