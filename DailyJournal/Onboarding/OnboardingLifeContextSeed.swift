//
//  OnboardingLifeContextSeed.swift
//  DailyJournal
//
//  Folds the intake answers from onboarding's struggle and people steps
//  into `LifeContext` — the same doc Mirror and Daily Chat read from
//  (`SelfModelService.lifeContext`/`saveLifeContext`) — so the Person Model
//  and chat already know what the user is dealing with on day one, instead
//  of waiting for it to surface naturally over several entries.
//
//  Runs once, right after the AI consent step (the earliest point onboarding
//  has every intake answer AND a decided `isAIAvailable`). Fire-and-forget,
//  same as every other LifeContext write in the app.
//

import Foundation

@MainActor
enum OnboardingLifeContextSeed {

    static func run(userId: String) async {
        guard !userId.isEmpty else { return }
        guard OnboardingIntent.struggle != nil || !OnboardingIntent.people.isEmpty else { return }

        var ctx = await SelfModelService.shared.lifeContext(for: userId)

        if let struggle = OnboardingIntent.struggle {
            let detail = OnboardingIntent.struggleDetail?.trimmingCharacters(in: .whitespacesAndNewlines)
            var newFocus = [struggle]
            if let detail, !detail.isEmpty, detail.count <= 80 {
                newFocus.append(detail)
            }
            var focus = ctx.primaryFocus
            for entry in newFocus where !focus.contains(where: { $0.caseInsensitiveCompare(entry) == .orderedSame }) {
                focus.append(entry)
            }
            // Mirrors `DailyChatView`'s own primaryFocus merge (see
            // `AIService+Mirror.swift` around `primaryFocus`) — keep only the
            // most recent 5 so this never grows unbounded.
            ctx.primaryFocus = Array(focus.suffix(5))
        }

        let names = OnboardingIntent.people.map(\.displayLabel).filter { !$0.isEmpty }
        if !names.isEmpty {
            var known = ctx.peopleLikelyToAppear
            for name in names where !known.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                known.append(name)
            }
            ctx.peopleLikelyToAppear = Array(known.suffix(8))
        }

        ctx.updatedAt = Date()
        SelfModelService.shared.saveLifeContext(ctx, userId: userId)
        AIService.cacheLifeContext(ctx)
    }
}
