//
//  DailyJournalApp.swift
//  DailyJournal
//
//  Created on 2026-05-25.
//

import SwiftUI
import FirebaseCore
import FirebaseFirestore

@main
struct DailyJournalApp: App {

    @StateObject private var authViewModel = AuthViewModel()

    init() {
        FirebaseApp.configure()

        // Explicitly enable the modern persistent on-disk cache. Setting only the
        // legacy `cacheSizeBytes` left reads going to the server first on every
        // load; with PersistentCacheSettings, queries can be served from disk
        // instantly (see JournalService's cache-first reads).
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings(
            sizeBytes: NSNumber(value: 100 * 1024 * 1024) // 100MB
        )
        Firestore.firestore().settings = settings
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authViewModel)
        }
    }
}
