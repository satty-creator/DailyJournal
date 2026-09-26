//
//  PrivacyPolicyView.swift
//  DailyJournal
//
//  The in-app privacy policy.
//
//  WHY THIS IS A VIEW AND NOT A LINK
//  ---------------------------------
//  The Profile row used to open `mailto:support@spilr.app?subject=Privacy Policy
//  Request` — i.e. the user asking a human to send them a policy. That is not a
//  privacy policy. It fails App Store Review Guideline 5.1.1(i) (apps must include
//  a link to their privacy policy) and it cannot answer a GDPR or enterprise
//  question. Rendering the text in-app means it works offline, ships with the
//  binary, and cannot rot independently of the code.
//
//  App Store Connect ALSO requires a publicly reachable privacy policy URL for the
//  product page — that is a separate field and this view does not satisfy it. The
//  hostable copy of this exact text lives at `PRIVACY_POLICY.md` in the repo root;
//  publish it and paste the URL into App Store Connect. Keep the two in sync.
//
//  ACCURACY IS THE POINT
//  ---------------------
//  Every claim below was written against the code, not against intent. In
//  particular it says plainly that entry text IS stored on our servers and IS
//  linked to the account, because it is: `JournalService.createEntry` writes the
//  full plaintext `content` to `users/{uid}/entries`. Earlier onboarding and
//  settings copy claimed the opposite. If you change what the app stores, change
//  this file in the same commit.
//

import SwiftUI

struct PrivacyPolicyView: View {

    /// Update whenever the substance changes. Shown to the user so they can tell
    /// which version they read.
    static let lastUpdated = "18 September 2026"

    var body: some View {
        ZStack {
            AppTheme.paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // MARK: Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Privacy")
                            .font(AppTheme.editorialDisplay(size: 30))
                            .foregroundStyle(AppTheme.ink)
                        Text("Last updated \(Self.lastUpdated)")
                            .font(AppTheme.mono(size: 11))
                            .foregroundStyle(AppTheme.inkSoft)
                    }

                    // MARK: The short version
                    section(
                        "The short version",
                        """
                        You write private things here, so you should know exactly where they go.

                        What you write is stored in your account on our servers, and it is linked to \
                        your account — that is how it is still there tomorrow and on your other \
                        devices. It is not anonymous, and we are not going to pretend it is.

                        Nobody else reads it. We do not sell it, we do not advertise against it, and \
                        we do not use it to train AI models. You can delete all of it, permanently, \
                        from Settings.
                        """
                    )

                    // MARK: What we store
                    section(
                        "What we store",
                        """
                        Your entries. The full text of everything you write, plus any title, tags, \
                        mood and photo attached to it. Stored under your account.

                        What we work out from your entries. To make Today's Read, Echoes, Mirror and \
                        Patterns work, the app derives and saves things like recurring themes, \
                        emotional vocabulary, short quotes lifted from your own entries, and the \
                        names of people or places you mention. These are stored under your account \
                        too. They are not anonymised or pooled with other users.

                        Your account details. Email address, display name, sign-in method, time zone, \
                        and the notification token for your device.

                        Your Google Calendar, if you connect it. This is entirely optional and off by \
                        default. If you connect it, the app reads your primary calendar's event \
                        titles, times, and locations, directly from Google, to show them to you in \
                        Spilr's own Calendar view. We request read-only access and never create, edit, \
                        or delete anything on your calendar. This data is not stored on our servers \
                        and not sent to any AI — it's fetched live from Google each time you open the \
                        Calendar view, and only stays in memory on your device. You can disconnect at \
                        any time from Settings, or revoke access entirely from your Google Account's \
                        permissions page.

                        That is the whole list. We do not collect your contacts, your location \
                        (beyond what you've chosen to put in a connected calendar event), your \
                        health data, or your activity in other apps.
                        """
                    )

                    // MARK: Who can see it
                    section(
                        "Who can see it",
                        """
                        You. Other users cannot see your entries, and there is no social feed, \
                        following, or sharing by default.

                        Our infrastructure providers, as processors. Your data lives in Google \
                        Firebase (Firestore, Authentication, Cloud Storage, Cloud Functions).

                        Us, in narrow circumstances. Technically we hold the keys to the database, so \
                        we could read your entries. We do not, as a matter of practice: no employee \
                        browses user journals. We would only access specific data if you asked us to \
                        for support, or if we were legally compelled. Your entries are not encrypted \
                        in a way that would make us unable to read them — see "What we have not built".

                        Nobody else. We do not sell, rent, or share your data with advertisers, data \
                        brokers, or analytics companies.
                        """
                    )

                    // MARK: AI
                    section(
                        "AI, and what it is sent",
                        """
                        The reflective features are powered by Google Gemini, reached through our own \
                        server so that no AI key ever sits in the app.

                        When AI Insights is on, the text of your recent entries is sent to Gemini to \
                        generate reflections, questions and patterns. Google processes it to return a \
                        result and does not use it to train their models. We do not keep a separate \
                        copy of the prompt.

                        When AI Insights is off, nothing is sent to Gemini. The app falls back to \
                        on-device logic, and every feature still works — just more simply. You can \
                        switch this in Settings at any time.

                        What the AI is not. It is not a therapist, a doctor, or a diagnostic tool. It \
                        is instructed never to diagnose you, never to use clinical language, and never \
                        to treat a repeated feeling as a medical conclusion. It is a language model \
                        and it can still get things wrong — if something it says does not sound like \
                        you, it isn't you, and you can tell it so.
                        """
                    )

                    // MARK: Deleting
                    section(
                        "Deleting your data",
                        """
                        Settings → Delete account permanently erases your entries, everything derived \
                        from them, your photos, and your account itself. It is immediate and it is not \
                        recoverable — there is no restore.

                        If you want a copy of your data, or want specific entries removed rather than \
                        all of them, email support@spilr.app and we will do it by hand. There is no \
                        self-service export in the app yet.
                        """
                    )

                    // MARK: Honest gaps
                    section(
                        "What we have not built",
                        """
                        We would rather tell you this than let you assume otherwise.

                        Your entries are not end-to-end encrypted. They are encrypted in transit and \
                        encrypted at rest by our hosting provider, which is standard — but we hold the \
                        keys, not you. A journal that only you could ever decrypt is a genuinely \
                        better design and it is not what ships today.

                        There is no in-app data export yet. Ask us and we will send it.

                        We will update this page when either of those changes, rather than quietly \
                        leaving it vague.
                        """
                    )

                    // MARK: Contact
                    section(
                        "Contact",
                        """
                        Questions, deletion requests, or a copy of your data: support@spilr.app.

                        If you are in the UK or EU, journal content counts as special-category data, \
                        and you have rights of access, correction, erasure and objection. Email us and \
                        we will action it.
                        """
                    )

                    Link(destination: URL(string: "mailto:support@spilr.app?subject=Privacy%20question")!) {
                        Text("Email support@spilr.app")
                            .font(AppTheme.mono(size: 12))
                            .foregroundStyle(AppTheme.terracotta)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            AnalyticsManager.shared.logEvent(.privacyPolicyViewed)
        }
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func section(_ heading: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading)
                .font(AppTheme.editorialDisplay(size: 19))
                .foregroundStyle(AppTheme.ink)

            // Split on blank lines so each paragraph gets its own spacing rather
            // than relying on newlines inside one Text.
            ForEach(paragraphs(of: body), id: \.self) { para in
                Text(para)
                    .font(AppTheme.editorialBody(size: 15))
                    .foregroundStyle(AppTheme.inkSoft)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func paragraphs(of text: String) -> [String] {
        text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

#Preview {
    NavigationStack { PrivacyPolicyView() }
}
