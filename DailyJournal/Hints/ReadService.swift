//
//  ReadService.swift
//  DailyJournal
//
//  Firestore CRUD for the `users/{uid}/dailyReads` subcollection plus the
//  get-or-build path the Home screen uses.
//
//  Reads are written overnight by the `generateDailyReads` Cloud Function (one
//  doc per user per local date, doc id == yyyy-MM-dd). The client never blocks on
//  that: `todayRead(...)` returns the server doc if it exists, otherwise it builds
//  a grounded LOCAL read on the spot so there is always something behind the
//  sealed card. Feedback writes are fire-and-forget, matching the rest of the app.
//

import Foundation
import FirebaseFirestore

final class ReadService {

    private let db = Firestore.firestore()
    private let journal = JournalService()

    private func collection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("dailyReads")
    }

    // MARK: - Fetch one day's read

    /// The server-generated read for `date`, or nil if the overnight job hasn't
    /// written one (or it was held back). Cache-first so Home paints instantly.
    func fetchRead(for userId: String, date: Date = Date()) async throws -> DailyRead? {
        let docId = DailyRead.dateKey(for: date)
        let ref = collection(for: userId).document(docId)

        // Cache-first, fall back to server only on a cold cache.
        if let cached = try? await ref.getDocument(source: .cache), cached.exists,
           let data = cached.data() {
            return DailyRead(from: data)
        }
        let snapshot = try await ref.getDocument(source: .default)
        guard snapshot.exists, let data = snapshot.data() else { return nil }
        return DailyRead(from: data)
    }

    // MARK: - Get or build (the Home path)

    /// Returns the read to show today. Prefers the server doc; on miss, builds a
    /// local read from recent entries and persists it (fire-and-forget) so the
    /// feedback loop has a stable id to write back to. Returns nil only when even
    /// the local engine has nothing to ground a read on (`shouldShow == false`),
    /// in which case Home falls back to the plain prompt card.
    func todayRead(for userId: String, date: Date = Date()) async -> DailyRead? {
        // 1. Server read wins if present and surfaceable.
        if let server = try? await fetchRead(for: userId, date: date) {
            return server.isSurfaceable ? server : nil
        }

        // 2. Build locally from recent entries.
        let recent = (try? await journal.fetchRecentEntries(for: userId, limit: 14)) ?? []
        let settings = ReadSettings(userId: userId)
        let local = LocalReadEngine.makeRead(
            userId: userId,
            localDate: date,
            recentEntries: recent,
            settings: settings
        )

        guard local.isSurfaceable else { return nil }

        // Persist the local read so feedback targets a real doc, and so we don't
        // regenerate a different line later the same day. Fire-and-forget.
        save(local)
        return local
    }

    // MARK: - Create

    /// Fire-and-forget. `merge: false` so the canonical row is replaced wholesale.
    func save(_ read: DailyRead) {
        collection(for: read.userId)
            .document(read.id)
            .setData(read.toFirestoreData())
    }

    // MARK: - Feedback

    /// Records a top-level reaction on the read. Fire-and-forget.
    /// Also applies the matching LOCAL recalibration via ReadSettings so the next
    /// local read (and the next server pass, which reads these fields) shifts.
    func recordFeedback(_ feedback: ReadFeedback, on read: DailyRead) {
        collection(for: read.userId)
            .document(read.id)
            .updateData(["userFeedback": feedback.rawValue])

        let settings = ReadSettings(userId: read.userId)
        switch feedback {
        case .feltTrue, .moreLikeThis:
            settings.reward(patternIds: read.sourcePatternIds)
        case .tooSharp:
            settings.softenSharpness()
        case .notMe:
            break   // the detailed code arrives via recordRejection(...)
        }
    }

    /// Records the "not me" micro-menu classification. Fire-and-forget.
    func recordRejection(_ code: ReadRejectionCode, on read: DailyRead) {
        collection(for: read.userId)
            .document(read.id)
            .updateData([
                "userFeedback":         ReadFeedback.notMe.rawValue,
                "detailedFeedbackCode": code.rawValue
            ])
        ReadSettings(userId: read.userId).recordRejection(readId: read.id, code: code)
    }
}
