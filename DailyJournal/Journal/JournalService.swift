//
//  JournalService.swift
//  DailyJournal
//

import Foundation
import FirebaseFirestore

final class JournalService {

    private let db = Firestore.firestore()

    private func entriesCollection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("entries")
    }

    // Cache-first read: serve the local on-disk cache instantly when it's warm,
    // and only fall back to the network when the cache is cold (first run / new
    // user). This is what makes Home, Patterns and the entry list paint without
    // waiting on a server round-trip. `.default` (not `.server`) is the fallback
    // so the call still succeeds when offline.
    private func getDocuments(_ query: Query) async throws -> QuerySnapshot {
        if let cached = try? await query.getDocuments(source: .cache), !cached.isEmpty {
            return cached
        }
        return try await query.getDocuments(source: .default)
    }

    // MARK: - Create
    // Fire-and-forget: Firestore writes to local cache immediately and syncs to the
    // server in the background. We never await server ACK for writes — that's what
    // caused the spinner to hang on any slow / offline connection.
    func createEntry(_ entry: JournalEntry) {
        entriesCollection(for: entry.userId)
            .document(entry.id)
            .setData(entry.toFirestoreData())
        // Keeps `rollups/stats.entryCount` current without anyone having to fetch
        // (and decrypt) the corpus to count it — see RollupStats.swift.
        RollupService.shared.recordEntryCreated(userId: entry.userId, at: entry.createdAt)
    }

    // MARK: - Update
    func updateEntry(_ entry: JournalEntry) {
        var data = entry.toFirestoreData()
        data["updatedAt"] = Timestamp(date: Date())
        // setData(merge:true) is the fire-and-forget equivalent of updateData
        entriesCollection(for: entry.userId)
            .document(entry.id)
            .setData(data, merge: true)
    }

    // MARK: - Schedule future-self letter
    func scheduleFutureSelf(entryId: String, userId: String, deliveryDate: Date) {
        entriesCollection(for: userId)
            .document(entryId)
            .updateData([
                "futureSelfDeliveryDate": Timestamp(date: deliveryDate),
                "futureSelfOpened": false
            ])
    }

    // MARK: - Mark arrived letter as opened
    func markLetterOpened(entryId: String, userId: String) {
        entriesCollection(for: userId)
            .document(entryId)
            .updateData(["futureSelfOpened": true])
    }

    // MARK: - Delete
    func deleteEntry(_ entry: JournalEntry) {
        entriesCollection(for: entry.userId)
            .document(entry.id)
            .delete(completion: nil)
        // Also remove the entry's Storage photo, if any — otherwise deleting an
        // entry orphans its `.jpg`. Best-effort / no-op when none exists.
        PhotoUploadService.shared.deleteEntryPhoto(userId: entry.userId, entryId: entry.id)
        RollupService.shared.recordEntryDeleted(userId: entry.userId)
    }

    // MARK: - Update AI insights (called after Gemini returns)
    // Fire-and-forget: same pattern as all other writes.
    func updateEntryInsights(entryId: String, userId: String, insights: JournalInsights) {
        entriesCollection(for: userId)
            .document(entryId)
            .updateData([
                "aiSummaryBullets": insights.bullets,
                "aiQuestion":       insights.question,
                "sentimentLabel":   insights.sentiment
            ])
    }

    // MARK: - Observe a single entry
    // Every other read here is one-shot, which is fine for lists that are re-fetched
    // on appear. It is NOT fine for a surface that is already on screen while a
    // detached enrichment task is still writing to the entry it is displaying — the
    // first-entry celebration sheet is opened from a snapshot taken milliseconds
    // after `createEntry`, so `updateEntryInsights` always lands after it. This
    // returns a live listener so that surface can redraw when the patch arrives.
    //
    // The caller owns the returned registration and MUST `remove()` it — see
    // `EntryInsightsObserver`, which ties it to the view's lifetime.
    func observeEntry(
        entryId: String,
        userId: String,
        onChange: @escaping (JournalEntry) -> Void
    ) -> ListenerRegistration {
        entriesCollection(for: userId)
            .document(entryId)
            .addSnapshotListener { snapshot, _ in
                guard
                    let data = snapshot?.data(),
                    let entry = JournalEntry(from: data)
                else { return }
                onChange(entry)
            }
    }

    // MARK: - Update attached photo URL (called after Storage upload returns)
    // Fire-and-forget: same pattern as all other writes.
    func updateEntryPhotoURL(entryId: String, userId: String, url: String) {
        entriesCollection(for: userId)
            .document(entryId)
            .updateData(["photoURL": url])

        // The upload that produced `url` runs detached, well after the editor has
        // already dismissed and handed a photo-less entry to the list via
        // `upsert(_:)` (the entry object is built and inserted before the upload
        // even starts — see `JournalEditorViewModel.save(photo:)`). Firestore's own
        // write completes fine, but nothing was telling the already-visible list
        // row about it, so the photo silently never appeared until the next full
        // reload. This is the only signal that closes that gap without adding a
        // live Firestore listener, which nothing else in the app uses.
        NotificationCenter.default.post(
            name: .journalEntryPhotoUploaded,
            object: nil,
            userInfo: ["entryId": entryId, "userId": userId, "photoURL": url]
        )
    }

    // MARK: - Fetch all (descending)
    //
    // Capped at 300 so a cold-start network fetch doesn't download an unbounded
    // collection. Pull-to-refresh in JournalListView will still reconcile against
    // the cache once it's warm. 300 covers the vast majority of users; heavy
    // journalers who exceed this will see older entries on the next refresh.
    func fetchEntries(for userId: String) async throws -> [JournalEntry] {
        let snapshot = try await getDocuments(
            entriesCollection(for: userId)
                .order(by: "createdAt", descending: true)
                .limit(to: 300)
        )
        return snapshot.documents.compactMap { JournalEntry(from: $0.data()) }
    }

    // MARK: - Fetch, one page at a time (Journal list first paint)
    //
    // Same query as `fetchEntries`, but capped and cursored, so
    // `JournalListViewModel` can paint the first ~10 rows immediately instead
    // of waiting on the full 300-doc / cold-install fetch — then keep calling
    // this in the background to fill in the rest for search, tag chips and
    // the header count, which all compute over the full in-memory array.
    func fetchEntriesPage(
        for userId: String, limit: Int, after cursor: DocumentSnapshot?
    ) async throws -> (entries: [JournalEntry], lastDoc: DocumentSnapshot?) {
        var query = entriesCollection(for: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
        if let cursor { query = query.start(afterDocument: cursor) }
        let snapshot = try await getDocuments(query)
        return (
            snapshot.documents.compactMap { JournalEntry(from: $0.data()) },
            snapshot.documents.last
        )
    }

    // MARK: - Fetch recent (home screen)
    func fetchRecentEntries(for userId: String, limit: Int = 5) async throws -> [JournalEntry] {
        let snapshot = try await getDocuments(
            entriesCollection(for: userId)
                .order(by: "createdAt", descending: true)
                .limit(to: limit)
        )
        return snapshot.documents.compactMap { JournalEntry(from: $0.data()) }
    }

    // MARK: - Fetch arrived letters
    //
    // Uses FirestoreCacheFirst, not the local `getDocuments`, because "no letters"
    // is the correct answer for most users — and `getDocuments` treats an empty
    // cache result as a miss, so this query went to the server on every Home load
    // forever while gating first paint. Also `.limit(to:)`: an unbounded
    // two-field query on the entries collection is the wrong shape for a lookup
    // that renders at most a couple of cards.
    func fetchArrivedLetters(for userId: String) async throws -> [JournalEntry] {
        let now = Timestamp(date: Date())
        let snapshot = try await FirestoreCacheFirst.documents(
            entriesCollection(for: userId)
                .whereField("futureSelfOpened", isEqualTo: false)
                .whereField("futureSelfDeliveryDate", isLessThanOrEqualTo: now)
                .limit(to: 10),
            key: "arrivedLetters.\(userId)"
        )
        return snapshot.documents.compactMap { JournalEntry(from: $0.data()) }
    }

    // MARK: - Fetch all (ascending) for pattern analysis
    func fetchAllEntries(for userId: String) async throws -> [JournalEntry] {
        let snapshot = try await getDocuments(
            entriesCollection(for: userId)
                .order(by: "createdAt", descending: false)
        )
        return snapshot.documents.compactMap { JournalEntry(from: $0.data()) }
    }

    // MARK: - Fetch capped, newest-first (Mirror's maturity gating + Ask)
    //
    // Mirror used `fetchAllEntries` — the only UNBOUNDED entry query in the app —
    // just to get a count and a corpus for `AskView`. Every maturity gate tops out
    // at 90 entries (`MirrorMaturity`), and Ask ranks/filters its own candidates
    // from whatever it's given, so neither needs the true full history. This is
    // `fetchEntries`'s proven cache-friendly shape (capped, descending) at a limit
    // sized for Mirror instead of the list screen's 300 — deliberately NOT a
    // change to `fetchAllEntries` itself, since PatternsView, MemoryProfileService,
    // PatternDetectionService and ThemeCompilationView all call that expecting the
    // real full corpus.
    func fetchEntriesForMirror(for userId: String, limit: Int = 100) async throws -> [JournalEntry] {
        let snapshot = try await getDocuments(
            entriesCollection(for: userId)
                .order(by: "createdAt", descending: true)
                .limit(to: limit)
        )
        return snapshot.documents.compactMap { JournalEntry(from: $0.data()) }
    }

    // MARK: - Count (for RollupService backfill)
    //
    // A Firestore COUNT aggregation query — the server returns a number, not
    // documents, so this is the one entry "read" that costs neither a download
    // nor a decryption. Used only to backfill `rollups/stats` for a user whose
    // counter doc doesn't exist yet (pre-rollup accounts, or a first write that
    // hasn't synced). `.server`, not cache-first: a stale cached count would
    // defeat the point of a backfill.
    func countEntries(for userId: String) async throws -> Int {
        let snapshot = try await entriesCollection(for: userId).count.getAggregation(source: .server)
        return snapshot.count.intValue
    }

}

extension Notification.Name {
    /// Posted by `JournalService.updateEntryPhotoURL` once a detached photo
    /// upload has patched an entry's `photoURL` in Firestore. `userInfo` carries
    /// `"entryId"`, `"userId"`, and `"photoURL"` (all `String`).
    static let journalEntryPhotoUploaded = Notification.Name("journalEntryPhotoUploaded")
}
