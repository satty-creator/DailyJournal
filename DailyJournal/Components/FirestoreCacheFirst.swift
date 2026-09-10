// FirestoreCacheFirst.swift
// DailyJournal
//
// Cache-first Firestore reads that also work when the correct answer is EMPTY.
//
// THE BUG THIS EXISTS TO FIX
// -------------------------
// Three services independently implemented cache-first reads like this:
//
//     if let cached = try? await query.getDocuments(source: .cache), !cached.isEmpty {
//         return cached
//     }
//     return try await query.getDocuments(source: .default)
//
// The intent is right, but `!cached.isEmpty` conflates two different states that
// Firestore's local cache cannot tell apart on its own:
//
//     "I have never fetched this query"   → must go to the network
//     "I fetched this query; it is empty" → the cache answer is CORRECT
//
// Treating both as a miss means any query whose real answer is empty pays a full
// server round-trip on every single call, forever. That is not an edge case — it
// is the normal state of the three queries that gate Home's first paint:
//
//     fetchArrivedLetters   most users have zero future-self letters
//     fetchTopPendingEcho   most users have zero pending echoes
//     fetchToday (mood)     empty whenever they haven't logged a mood yet today
//
// So the "cache-first, paints instantly" design degraded to "three guaranteed
// network round-trips before the screen can render", and it got *worse* the
// emptier the account was — i.e. worst for brand-new users.
//
// THE FIX
// -------
// Remember, per query, whether we have ever successfully hydrated it from the
// server. Once we have, an empty cache result is a real answer and is served
// immediately, with a background refresh to keep the cache warm
// (stale-while-revalidate). Before we have, we go to the network as before.
//
// One flag per query key in UserDefaults. Cheap, survives relaunch, and resets
// naturally on reinstall — which is exactly when we *do* need the network.

import Foundation
import FirebaseFirestore

enum FirestoreCacheFirst {

    private static let prefix = "fsHydrated."

    private static func isHydrated(_ key: String) -> Bool {
        UserDefaults.standard.bool(forKey: prefix + key)
    }

    private static func markHydrated(_ key: String) {
        UserDefaults.standard.set(true, forKey: prefix + key)
    }

    /// Clears every hydration flag. Call on sign-out so the next account doesn't
    /// inherit this one's "already fetched" claims.
    static func reset() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(prefix) || key.hasPrefix(dayPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    /// Cache-first query read.
    ///
    /// - Parameter key: stable identity for this query, scoped per user, e.g.
    ///   `"letters.\(userId)"`. Must NOT vary run to run or the flag never sticks.
    static func documents(_ query: Query, key: String) async throws -> QuerySnapshot {
        if isHydrated(key), let cached = try? await query.getDocuments(source: .cache) {
            // Refresh behind the answer we just served. Detached and unawaited —
            // this must never be on the caller's critical path.
            Task.detached(priority: .utility) {
                _ = try? await query.getDocuments(source: .default)
            }
            return cached
        }
        let fresh = try await query.getDocuments(source: .default)
        // Only claim hydration when the data actually came from the SERVER.
        // `.default` happily serves the local cache when offline, so marking
        // unconditionally could set the flag without ever having fetched — the
        // precise thing the flag is supposed to prove.
        if !fresh.metadata.isFromCache { markHydrated(key) }
        return fresh
    }

    /// Cache-first single-document read. `nil` means "no such document", which is
    /// a valid cached answer once hydrated.
    static func document(_ ref: DocumentReference, key: String) async throws -> DocumentSnapshot? {
        if isHydrated(key), let cached = try? await ref.getDocument(source: .cache) {
            Task.detached(priority: .utility) {
                _ = try? await ref.getDocument(source: .default)
            }
            return cached.exists ? cached : nil
        }
        let fresh = try await ref.getDocument(source: .default)
        if !fresh.metadata.isFromCache { markHydrated(key) }
        return fresh.exists ? fresh : nil
    }

    // MARK: - Day-scoped variant
    //
    // For reads whose "empty" answer is only valid for one calendar day (today's
    // mood). Keying the flag by day would mint a new permanent UserDefaults key
    // every day — ~365/year for a user who never signs out, cleared only on sign
    // out. Instead we keep ONE key per logical read and store the day it was
    // hydrated for, so yesterday's flag is naturally invalid today.

    private static let dayPrefix = "fsHydratedDay."

    static func documentForToday(
        _ ref: DocumentReference, key: String, dayKey: String
    ) async throws -> DocumentSnapshot? {
        let flagKey = dayPrefix + key
        if UserDefaults.standard.string(forKey: flagKey) == dayKey,
           let cached = try? await ref.getDocument(source: .cache) {
            Task.detached(priority: .utility) {
                _ = try? await ref.getDocument(source: .default)
            }
            return cached.exists ? cached : nil
        }
        let fresh = try await ref.getDocument(source: .default)
        if !fresh.metadata.isFromCache {
            UserDefaults.standard.set(dayKey, forKey: flagKey)
        }
        return fresh.exists ? fresh : nil
    }
}
