//
//  OwnerAccess.swift
//  DailyJournal
//
//  The founder's accounts, which never see the Spilr Pro paywall.
//
//  This is UI only. The real bypass is server-side — `OWNER_EMAILS` /
//  `OWNER_UIDS` in functions/lib/entitlement.js, checked against the verified
//  ID token on every AI call. Keep the two lists identical: if an address is
//  here but not there, the app hides the paywall while the server still
//  returns 402s, and AI silently stops.
//
//  Deliberately NOT on this list: test@spilr.com, the App Review demo account.
//  Reviewers have to see the paywall and the purchase flow (Guideline 2.1).
//

import Foundation

enum OwnerAccess {

    /// Must match `OWNER_EMAILS` in functions/lib/entitlement.js.
    static let emails: Set<String> = [
        "satakshi1710@gmail.com",
        "sataksp@gmail.com",
        "ssahni30@gmail.com",
    ]

    /// Must match `OWNER_UIDS` in functions/lib/entitlement.js.
    static let uids: Set<String> = [
        "KrLOcdVDPKVjmmxhu85N3tibeRH3", // satakshi1710@gmail.com
        "cy7T8gtnH9bqmYC0JeWAvXdkbLM2", // ssahni30@gmail.com
    ]

    static func isOwner(email: String?, uid: String?) -> Bool {
        if let uid, uids.contains(uid) { return true }
        guard let email = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !email.isEmpty else { return false }
        return emails.contains(email)
    }
}
