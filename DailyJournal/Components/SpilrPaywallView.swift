//
//  SpilrPaywallView.swift
//  DailyJournal
//
//  The Spilr Pro paywall. Native SwiftUI in the app's own theme and voice,
//  replacing the RevenueCatUI template. Shown:
//    - once, right after onboarding (`PaywallTrigger.onboarding`)
//    - when the server says the free AI preview is over (`.aiLimit`)
//    - from Profile → Get Spilr Pro (`.profile`)
//  Presented via `PaywallPresenter` (or as a sheet from Profile).
//
//  Design notes (from the Sept 2026 growth review):
//    - The headline justifies the trial instead of asking for money.
//    - The button states the outcome ("Start 2 weeks free"); the price lives
//      in the fine print underneath, where it reads as a term.
//    - "Your spills stay yours either way" answers the privacy objection at
//      the moment of maximum suspicion.
//    - Writing is never gated; only AI is. The copy says so.
//  Prices and trial length come from App Store Connect via the store — see
//  PaywallModels.swift. Nothing here hardcodes a price.
//

import SwiftUI

struct SpilrPaywallView: View {
    let trigger: PaywallTrigger
    let onClose: () -> Void

    /// @State, not `let`: SwiftUI rebuilds this struct whenever a parent
    /// re-renders, and a fresh store would have forgotten the packages it
    /// loaded — the purchase would then fail with "plan unavailable".
    @State private var store: PaywallStore

    private enum LoadState: Equatable {
        case loading
        case loaded
        case failed
    }

    @State private var state: LoadState = .loading
    @State private var plans: [PaywallPlan] = []
    @State private var selectedID: String?
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var canDismiss = false
    @State private var restoreMessage: String?
    @State private var purchased = false

    init(trigger: PaywallTrigger, store: PaywallStore = PaywallStores.make(), onClose: @escaping () -> Void) {
        self.trigger = trigger
        self._store = State(initialValue: store)
        self.onClose = onClose
    }

    private var selectedPlan: PaywallPlan? {
        plans.first(where: { $0.id == selectedID })
    }

    private var monthlyPrice: Decimal? { plans.first(where: { $0.kind == .monthly })?.price }

    var body: some View {
        ZStack {
            AppTheme.paper.ignoresSafeArea()

            switch state {
            case .loading:
                ProgressView()
                    .tint(AppTheme.terracotta)
                    .accessibilityIdentifier("paywall.loading")
            case .failed:
                failureState
            case .loaded:
                content
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paywall")
        .interactiveDismissDisabled(!canDismiss)
        .task { await load() }
        .task {
            let delay = PaywallCopy.dismissDelay(for: trigger)
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            withAnimation(.easeIn(duration: 0.3)) { canDismiss = true }
        }
        .onAppear {
            AnalyticsManager.shared.logEvent(.paywallShown, parameters: ["trigger": trigger.rawValue])
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Text("SPILR PRO")
                        .font(AppTheme.mono(size: 11))
                        .tracking(2)
                        .foregroundStyle(AppTheme.terracotta)
                        .padding(.top, 36)

                    Text(PaywallCopy.headline(for: trigger))
                        .font(AppTheme.editorialDisplay(size: 30))
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("paywall.headline")

                    Text(PaywallCopy.subhead(for: trigger, trial: selectedPlan?.trial ?? plans.compactMap(\.trial).first))
                        .font(AppTheme.editorialBody(size: 15))
                        .foregroundStyle(AppTheme.inkSoft)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 12) {
                        featureRow("text.quote", "Reflections on every entry, in your own words")
                        featureRow("bubble.left.and.bubble.right", "Daily Chat that answers back")
                        featureRow("sparkles", "Your Mirror: threads, patterns, the Sunday letter")
                        featureRow("pencil", "Writing is free forever \u{2014} with or without Pro")
                    }
                    .padding(.vertical, 4)

                    VStack(spacing: 10) {
                        ForEach(plans) { plan in
                            planCard(plan)
                        }
                    }

                    Spacer(minLength: 180)
                }
                .padding(.horizontal, 24)
            }

            footer
        }
    }

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.terracotta)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func planCard(_ plan: PaywallPlan) -> some View {
        let selected = plan.id == selectedID
        let savings: Int? = {
            guard plan.kind == .annual, let monthly = monthlyPrice else { return nil }
            return PaywallCopy.annualSavingsPercent(monthly: monthly, annual: plan.price)
        }()

        return Button {
            withAnimation(.easeOut(duration: 0.15)) { selectedID = plan.id }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(selected ? AppTheme.terracottaDeep : AppTheme.inkSoft.opacity(0.35), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if selected {
                        Circle().fill(AppTheme.terracottaDeep).frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(plan.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                        if let savings {
                            badge("SAVE \(savings)%")
                        }
                        if let trial = plan.trial {
                            badge("\(trial.phrase.uppercased()) FREE")
                        }
                    }
                    Text(plan.priceLine)
                        .font(AppTheme.mono(size: 12))
                        .foregroundStyle(AppTheme.inkSoft)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(selected ? AppTheme.terracotta.opacity(0.10) : AppTheme.cream)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? AppTheme.terracottaDeep : AppTheme.inkSoft.opacity(0.14),
                            lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("paywall.plan.\(plan.kind)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(AppTheme.mono(size: 9))
            .tracking(1)
            .foregroundStyle(AppTheme.cream)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(AppTheme.terracottaDeep)
            .clipShape(Capsule())
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.terracottaDeep)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await buy() }
            } label: {
                ZStack {
                    Text(PaywallCopy.ctaTitle(for: selectedPlan))
                        .opacity(isPurchasing ? 0 : 1)
                    if isPurchasing { ProgressView().tint(AppTheme.cream) }
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.cream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(LinearGradient(colors: [AppTheme.terracotta, AppTheme.terracottaDeep],
                                           startPoint: .leading, endPoint: .trailing))
                .clipShape(Capsule())
                .shadow(color: AppTheme.terracotta.opacity(0.35), radius: 14, x: 0, y: 7)
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing || selectedPlan == nil)
            .accessibilityIdentifier("paywall.cta")

            Text(PaywallCopy.finePrint(for: selectedPlan))
                .font(.system(size: 11.5))
                .foregroundStyle(AppTheme.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("paywall.finePrint")

            HStack(spacing: 14) {
                Button("Restore purchases") { Task { await restore() } }
                    .accessibilityIdentifier("paywall.restore")
                Text("\u{00B7}").foregroundStyle(AppTheme.inkSoft.opacity(0.5))
                Link("Terms", destination: URL(string: "https://spilr-100f7.web.app/terms")!)
                    .accessibilityIdentifier("paywall.terms")
                Text("\u{00B7}").foregroundStyle(AppTheme.inkSoft.opacity(0.5))
                Link("Privacy", destination: URL(string: "https://spilr-100f7.web.app/privacy")!)
                    .accessibilityIdentifier("paywall.privacy")
            }
            .font(.system(size: 12))
            .foregroundStyle(AppTheme.inkSoft)

            if let restoreMessage {
                Text(restoreMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.inkSoft)
            }

            Button("Not yet") { close() }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.inkSoft)
                .padding(.top, 2)
                .opacity(canDismiss ? 1 : 0)
                .disabled(!canDismiss)
                .accessibilityIdentifier("paywall.notYet")
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .background(
            AppTheme.paper
                .ignoresSafeArea(edges: .bottom)
                .shadow(color: AppTheme.cardShadow, radius: 12, x: 0, y: -4)
        )
    }

    private var failureState: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(AppTheme.inkSoft)
            Text("Spilr Pro isn't available right now")
                .font(AppTheme.editorialDisplay(size: 18))
                .foregroundStyle(AppTheme.ink)
            Text("Please try again in a bit. Writing works as normal.")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.inkSoft)
            HStack(spacing: 20) {
                Button("Try again") { Task { await load() } }
                Button("Close") { close() }
                    .accessibilityIdentifier("paywall.close")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(AppTheme.terracotta)
            .padding(.top, 8)
        }
        .padding(32)
        .onAppear { canDismiss = true }
    }

    // MARK: - Actions

    private func load() async {
        state = .loading
        do {
            let loaded = PaywallCopy.sorted(try await store.loadPlans())
            plans = loaded
            selectedID = PaywallCopy.defaultSelection(loaded)?.id
            state = loaded.isEmpty ? .failed : .loaded
        } catch {
            AnalyticsManager.shared.trackError(error, context: "paywall_load_failed")
            state = .failed
        }
    }

    private func buy() async {
        guard let plan = selectedPlan else { return }
        errorMessage = nil
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let unlocked = try await store.purchase(plan)
            if unlocked {
                AnalyticsManager.shared.logEvent(.paywallPurchased, parameters: [
                    "trigger": trigger.rawValue, "plan": plan.id, "trial": plan.trial != nil,
                ])
                purchased = true
                await EntitlementService.shared.refresh()
                close()
            }
        } catch {
            AnalyticsManager.shared.trackError(error, context: "paywall_purchase_failed")
            errorMessage = "That didn\u{2019}t go through. You haven\u{2019}t been charged \u{2014} please try again."
        }
    }

    private func restore() async {
        restoreMessage = nil
        do {
            let restored = try await store.restore()
            await EntitlementService.shared.refresh()
            if restored { purchased = true; close() } else { restoreMessage = "No previous purchase found for this Apple ID." }
        } catch {
            AnalyticsManager.shared.trackError(error, context: "paywall_restore_failed")
            restoreMessage = "Couldn\u{2019}t restore right now. Please try again."
        }
    }

    private func close() {
        if !purchased {
            AnalyticsManager.shared.logEvent(.paywallDismissed, parameters: ["trigger": trigger.rawValue])
        }
        onClose()
    }
}
