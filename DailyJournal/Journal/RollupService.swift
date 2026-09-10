//
//  RollupService.swift
//  DailyJournal
//
//  Firestore CRUD for `users/{uid}/rollups/stats` — see RollupStats.swift for why
//  this document exists. Same fire-and-forget write discipline as JournalService.
//

import Foundation
import FirebaseFirestore

final class RollupService {

    static let shared = RollupService()

    private let db = Firestore.firestore()
    private let journalService = JournalService()

    private func statsRef(for userId: String) -> DocumentReference {
        db.collection("users").document(userId).collection("rollups").document("stats")
    }

    // MARK: - Increment on write (called from JournalService's own write paths)

    /// Fire-and-forget. `FieldValue.increment` needs no prior read, so this is as
    /// cheap as any other entry write — it does not turn `createEntry`/`saveTrace`
    /// into an awaited call.
    func recordEntryCreated(userId: String, at date: Date = Date()) {
        statsRef(for: userId).setData([
            "userId": userId,
            "entryCount": FieldValue.increment(Int64(1)),
            "lastEntryAt": Timestamp(date: date),
            "updatedAt": Timestamp(date: date),
            "schemaVersion": RollupStats.currentSchemaVersion
        ], merge: true)
    }

    /// Fire-and-forget. Deletion doesn't move `lastEntryAt` backwards — the
    /// nightly reconcile (once it exists) is the authoritative source for that;
    /// this is just the cheap running counter.
    func recordEntryDeleted(userId: String, at date: Date = Date()) {
        statsRef(for: userId).setData([
            "userId": userId,
            "entryCount": FieldValue.increment(Int64(-1)),
            "updatedAt": Timestamp(date: date),
            "schemaVersion": RollupStats.currentSchemaVersion
        ], merge: true)
    }

    // MARK: - Read

    /// Cache-first read. If the document has never been written at all (a user
    /// who existed before this rollup shipped, or one whose first write hasn't
    /// synced yet), backfills it from a Firestore COUNT aggregation query —
    /// which returns a number without downloading or decrypting any entry
    /// document — rather than falling back to `fetchEntriesForMirror`'s capped
    /// fetch, which would undercount anyone past that cap.
    func fetchStats(for userId: String) async -> RollupStats {
        if let snapshot = try? await FirestoreCacheFirst.document(
            statsRef(for: userId), key: "rollupStats.\(userId)"
        ), let data = snapshot.data(), let stats = RollupStats(from: data) {
            return stats
        }
        return await backfill(for: userId)
    }

    /// On a cold install with no rollup doc yet, a `countEntries` failure
    /// (offline, or just not online yet — App Attest is being minted for the
    /// first time in this exact window) used to be swallowed by `?? 0` and
    /// then PERSISTED as `entryCount: 0` — silently flattening a real
    /// account's `MirrorMaturity` back to `.seed` until its next entry write.
    /// Only write the backfill when the count actually came back; on failure,
    /// return an unpersisted zero so the caller has *something* to render
    /// this pass without corrupting Firestore's copy for the next one.
    private func backfill(for userId: String) async -> RollupStats {
        guard let count = try? await journalService.countEntries(for: userId) else {
            return RollupStats(
                userId: userId, entryCount: 0, lastEntryAt: nil,
                updatedAt: Date(), schemaVersion: RollupStats.currentSchemaVersion
            )
        }
        let stats = RollupStats(
            userId: userId, entryCount: count, lastEntryAt: nil,
            updatedAt: Date(), schemaVersion: RollupStats.currentSchemaVersion
        )
        writeBackfilled(stats, userId: userId)
        return stats
    }

    // MARK: - Write helper
    //
    // Deliberately a separate, non-async function. `setData(_:merge:)` called
    // directly inside an `async` function resolves to this Firebase SDK's
    // auto-imported `async throws` overload of the same signature (Swift
    // synthesizes one from the completion-handler variant), which then requires
    // `try await` and would make backfill wait on a server round-trip it
    // doesn't need to. Calling it from a plain sync function, as every other
    // write in this codebase does, keeps this the fire-and-forget write it's
    // meant to be.
    private func writeBackfilled(_ stats: RollupStats, userId: String) {
        statsRef(for: userId).setData(stats.toFirestoreData(), merge: true)
    }
}
