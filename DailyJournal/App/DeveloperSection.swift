//
//  DeveloperSection.swift
//  DailyJournal
//
//  Profile → Developer. Visible only to OwnerAccess accounts (and debug
//  builds), in every build type including TestFlight and the App Store, so
//  the founder can check push and the paywall on a real release build.
//
//    - Push diagnostics: permission → APNs → FCM token → Firestore, one line
//      each, so "push isn't working" becomes "this link is broken".
//    - Send test push: calls `sendTestPush` (rate-limited to the caller's own
//      uid server-side, not owner-only) and shows FCM's verdict per device token.
//    - Preview paywall: owners never see it otherwise.
//

import SwiftUI
import UserNotifications
import FirebaseAuth

struct DeveloperSection: View {
    @Binding var showPaywall: Bool

    @State private var diagnostics: PushNotificationManager.Diagnostics?
    @State private var isChecking = false
    @State private var testPushResult: String?
    @State private var isSendingTest = false

    var body: some View {
        Section {
            Button {
                Task { await runDiagnostics() }
            } label: {
                Label(isChecking ? "Checking\u{2026}" : "Check push setup", systemImage: "stethoscope")
                    .font(.system(size: 15))
            }
            .disabled(isChecking)
            .listRowBackground(AppTheme.cream)

            if let d = diagnostics {
                row("Permission", permissionText(d.permission), ok: d.permission == .authorized || d.permission == .provisional)
                row("Registered with APNs", d.registeredForRemote ? "Yes" : "No", ok: d.registeredForRemote)
                row("APNs token", d.apnsTokenPresent ? "Present" : "Missing", ok: d.apnsTokenPresent)
                row("FCM token", d.fcmToken.map { "\u{2026}" + String($0.suffix(10)) } ?? (d.fcmError ?? "None"),
                    ok: d.fcmToken != nil)
                row("Saved to Firestore", d.tokenSavedInFirestore ? "Yes" : "No (re-saving now)",
                    ok: d.tokenSavedInFirestore)
                if let token = d.fcmToken {
                    Button {
                        UIPasteboard.general.string = token
                    } label: {
                        Label("Copy FCM token (for Firebase console test)", systemImage: "doc.on.doc")
                            .font(.system(size: 14))
                    }
                    .listRowBackground(AppTheme.cream)
                }
            }

            Button {
                Task { await sendTestPush() }
            } label: {
                Label(isSendingTest ? "Sending\u{2026}" : "Send me a test push", systemImage: "bell.badge")
                    .font(.system(size: 15))
            }
            .disabled(isSendingTest)
            .listRowBackground(AppTheme.cream)

            if let testPushResult {
                Text(testPushResult)
                    .font(AppTheme.mono(size: 11))
                    .foregroundStyle(AppTheme.inkSoft)
                    .listRowBackground(AppTheme.cream)
            }

            Button {
                showPaywall = true
            } label: {
                Label("Preview Spilr Pro paywall", systemImage: "sparkles")
                    .font(.system(size: 15))
            }
            .listRowBackground(AppTheme.cream)
            .accessibilityIdentifier("developer.previewPaywall")
        } header: {
            Text("Developer")
                .foregroundStyle(AppTheme.inkSoft)
        } footer: {
            Text("Only visible to owner accounts. \u{201C}third-party-auth-error\u{201D} on a test push means the APNs key is missing in Firebase \u{2192} Project settings \u{2192} Cloud Messaging.")
                .font(.caption)
                .foregroundStyle(AppTheme.inkSoft)
        }
    }

    private func row(_ label: String, _ value: String, ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? AppTheme.moss : AppTheme.terracottaDeep)
            Text(label).font(.system(size: 14))
            Spacer()
            Text(value)
                .font(AppTheme.mono(size: 11))
                .foregroundStyle(AppTheme.inkSoft)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
        .listRowBackground(AppTheme.cream)
    }

    private func permissionText(_ s: UNAuthorizationStatus) -> String {
        switch s {
        case .authorized:    return "Allowed"
        case .denied:        return "Denied"
        case .notDetermined: return "Not asked yet"
        case .provisional:   return "Provisional"
        case .ephemeral:     return "Ephemeral"
        @unknown default:    return "Unknown"
        }
    }

    private func runDiagnostics() async {
        isChecking = true
        PushNotificationManager.shared.registerIfAuthorized()
        diagnostics = await PushNotificationManager.shared.diagnostics()
        isChecking = false
    }

    private func sendTestPush() async {
        isSendingTest = true
        defer { isSendingTest = false }
        guard let token = await AIService.shared.idToken(),
              let url = URL(string: AIService.sendTestPushURLString) else {
            testPushResult = "Not signed in."
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200:
                break
            case 403:
                // sendTestPush now rejects only an anonymous sign-in — any real
                // account can test its own push setup.
                testPushResult = "Sign in with a real account (not a guest) to send a test push."
                return
            case 429:
                // Per-uid rate limit server-side (functions/index.js, TEST_PUSH_MIN_GAP_MS).
                testPushResult = "Sent one too recently \u{2014} wait a few seconds and try again."
                return
            case 404:
                testPushResult = "sendTestPush isn\u{2019}t deployed yet \u{2014} run firebase deploy --only functions."
                return
            default:
                testPushResult = "Server said HTTP \(status)."
                return
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                testPushResult = "Unexpected response from sendTestPush."
                return
            }
            let tokens = json["tokens"] as? Int ?? 0
            let sent = json["sent"] as? Int ?? 0
            let failed = (json["failed"] as? [[String: Any]] ?? [])
                .map { "\($0["tokenSuffix"] as? String ?? "?"): \($0["code"] as? String ?? "?")" }
            if tokens == 0 {
                testPushResult = "No device tokens saved for this account \u{2014} run \u{201C}Check push setup\u{201D} first."
            } else {
                testPushResult = "Tokens: \(tokens) \u{00B7} sent: \(sent)" +
                    (failed.isEmpty ? "" : "\n" + failed.joined(separator: "\n"))
            }
        } catch {
            testPushResult = "Request failed: \(error.localizedDescription)"
        }
    }
}
