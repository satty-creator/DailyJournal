//
//  SelfModelView.swift
//  DailyJournal
//
//  The "My Self Model" screen — shows all active hypotheses about the user,
//  organised by category. Allows correcting or hiding any hypothesis.
//

import SwiftUI
import FirebaseFirestore

// MARK: - ViewModel

@MainActor
final class SelfModelViewModel: ObservableObject {
    @Published var selfModel: SelfModel
    @Published var corrections: [ProfileCorrection] = []
    @Published var showCorrectionSheet = false
    @Published var selectedHypothesisId: String? = nil
    @Published var narrative: MirrorNarrative? = nil

    var userId: String

    init(userId: String, selfModel: SelfModel) {
        self.userId = userId
        self.selfModel = selfModel
    }

    /// Loads a PREVIOUSLY generated narrative, if one exists. Read-only.
    ///
    /// The generation half is gone (Mirror v3 §5.5, Week 6). This was the last
    /// client-side LLM call on the whole Mirror surface — a third prose writer
    /// over the same hypotheses the server already writes cards and the weekly
    /// letter from, with no lint on its output beyond a banned-term check, and
    /// it ran on tab open. The weekly letter replaces it with a DATED artefact
    /// built on counted facts plus exactly one observation, which is both
    /// better grounded and archived.
    ///
    /// Existing narratives keep rendering until they age out, so nobody loses
    /// a paragraph they had yesterday.
    func loadNarrative() async {
        guard let snap = try? await Firestore.firestore()
            .collection("users").document(userId)
            .collection("selfModel").document("narrative")
            .getDocument(),
              snap.exists, let data = snap.data()
        else { return }
        narrative = MirrorNarrative(from: data)
    }

    /// The ONLY producer of `UserHypothesisStatus` in the app, and therefore the
    /// only way a hypothesis can ever reach `user_confirmed`.
    ///
    /// That matters more than it looks: `this_is_me` pins confidence to 0.85,
    /// forces the `user_confirmed` lifecycle, and exempts the hypothesis from the
    /// 45-day decay. It is the single strongest signal in the whole profile, which
    /// is exactly why it lives here — on a screen where the user is deliberately
    /// reviewing a hypothesis with its evidence in front of them — and not on the
    /// daily card, where a reflexive tap is nearly free.
    ///
    /// It must also write to the hypothesis doc, not just the assembled model.
    /// The nightly miner reads `userStatus` off `patternHypotheses` to compute
    /// lifecycle and confidence; a confirmation that only ever landed in
    /// `selfModel/current` would be overwritten by the next run.
    func markHypothesis(id: String, status: UserHypothesisStatus) {
        SelfModelService.shared.markHypothesis(id: id, userStatus: status, userId: userId)
        // Optimistic local update
        for i in selfModel.coreRules.indices where selfModel.coreRules[i].id == id {
            selfModel.coreRules[i].userStatus = status
        }
        for i in selfModel.whatHelps.indices where selfModel.whatHelps[i].id == id {
            selfModel.whatHelps[i].userStatus = status
        }
        for i in selfModel.absences.indices where selfModel.absences[i].id == id {
            selfModel.absences[i].userStatus = status
        }
        for i in selfModel.values.indices where selfModel.values[i].id == id {
            selfModel.values[i].userStatus = status
        }
        for i in selfModel.contradictions.indices where selfModel.contradictions[i].id == id {
            selfModel.contradictions[i].userStatus = status
        }
        for i in selfModel.protectiveStrategies.indices where selfModel.protectiveStrategies[i].id == id {
            selfModel.protectiveStrategies[i].userStatus = status
        }
        for i in selfModel.innerParts.indices where selfModel.innerParts[i].id == id {
            selfModel.innerParts[i].userStatus = status
        }
    }

    func hideHypothesis(id: String) {
        SelfModelService.shared.hideHypothesis(id: id, userId: userId)
        AnalyticsManager.shared.logEvent(.mirrorHypothesisCollapsed)
        // Optimistic local update — mark as retired so filter drops it
        dropLocally(id)
    }

    /// "This is done" — the user has resolved this thread and it must never be
    /// mined or surfaced again. Distinct from Hide (not now) and Not me (wrong).
    func closeHypothesis(id: String) {
        SelfModelService.shared.closeHypothesis(id: id, userId: userId)
        dropLocally(id)
    }

    private func dropLocally(_ id: String) {
        selfModel.coreRules            = selfModel.coreRules.filter { $0.id != id }
        selfModel.whatHelps            = selfModel.whatHelps.filter { $0.id != id }
        selfModel.absences             = selfModel.absences.filter { $0.id != id }
        selfModel.protectiveStrategies = selfModel.protectiveStrategies.filter { $0.id != id }
        selfModel.values               = selfModel.values.filter { $0.id != id }
        selfModel.contradictions       = selfModel.contradictions.filter { $0.id != id }
    }

    func submitCorrection(text: String, category: String?) {
        let correction = ProfileCorrection(
            userId: userId,
            feedbackType: .missingContext,
            hypothesisId: selectedHypothesisId,
            userCorrection: text,
            correctionCategory: category
        )
        corrections.append(correction)
        SelfModelService.shared.submitCorrection(correction, userId: userId)
        AnalyticsManager.shared.logEvent(.mirrorHypothesisEdited)
    }
}

// MARK: - SelfModelView

struct SelfModelView: View {
    @StateObject private var vm: SelfModelViewModel
    @State private var correctionText = ""
    @State private var showingHypothesisId: String? = nil

    init(userId: String, selfModel: SelfModel) {
        _vm = StateObject(wrappedValue: SelfModelViewModel(userId: userId, selfModel: selfModel))
    }

    var body: some View {
        // Not its own NavigationStack — this view is always pushed via a
        // `.navigationDestination` from MirrorView, which already owns the
        // stack. A nested NavigationStack here doubled the nav bar and broke
        // the interactive swipe-back gesture (mirror-v3-prd-2026-09-10.md,
        // Week 1).
        Group {
            ZStack {
                AppTheme.paper.ignoresSafeArea()

                if vm.selfModel.version == 0 {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            maturityBanner
                            if let narrative = vm.narrative {
                                narrativeHeader(narrative)
                            }
                            if !vm.selfModel.coreRules.filter { $0.isActive && $0.isProfileSurfaceable }.isEmpty {
                                rulesSection
                            }
                            if !vm.selfModel.protectiveStrategies.filter { $0.isActive && $0.asHypothesis.isProfileSurfaceable }.isEmpty {
                                protectiveSection
                            }
                            if !vm.selfModel.innerParts.filter({ $0.confidence > 0.3 }).isEmpty {
                                innerPartsSection
                            }
                            if !vm.selfModel.whatHelps.filter { $0.isActive && $0.isProfileSurfaceable }.isEmpty {
                                whatHelpsSection
                            }
                            // Placed high: an absence is the most specific,
                            // least horoscope-ish thing on this screen, and it
                            // is the only section that cannot be wrong about its
                            // own arithmetic.
                            if !vm.selfModel.absences.filter(\.isActive).isEmpty {
                                absencesSection
                            }
                            // §5.6 "People and the part you play". This has
                            // been populated by updateSelfModel all along and
                            // rendered NOWHERE — one of three fields the
                            // server wrote every night into a screen that
                            // never read them.
                            if !vm.selfModel.relationshipRoles.isEmpty {
                                relationshipRolesSection
                            }
                            if !vm.selfModel.vocabulary.isEmpty {
                                vocabularySection
                            }
                            let openQuestions = vm.selfModel.coreRules.filter {
                                $0.userStatus == .unrated && $0.stability == .emerging
                            }
                            if !openQuestions.isEmpty {
                                openQuestionsSection(questions: openQuestions)
                            }
                            // Says what would fill each empty section, rather
                            // than leaving a blank screen that reads as
                            // "nothing here about you". At 7 entries most of
                            // this is empty and being straight about that is
                            // what earns belief at 30 (§7).
                            if isProfileEmpty {
                                profileEmptyState
                            }
                            Spacer(minLength: 60)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("My Mirror")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await vm.loadNarrative()
                AnalyticsManager.shared.logEvent(.mirrorHypothesisViewed)
            }
        }
        .sheet(isPresented: $vm.showCorrectionSheet) {
            correctionSheet
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.inkSoft.opacity(0.4))
            Text("Still learning")
                .font(AppTheme.editorialDisplay(size: 28, weight: .bold))
                .foregroundStyle(AppTheme.ink)
            Text("Spilr is building your first sketch. Keep writing.")
                .font(AppTheme.editorialBody(size: 16))
                .foregroundStyle(AppTheme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Maturity banner

    private var maturityBanner: some View {
        HStack(spacing: 14) {
            maturityRing(maturity: vm.selfModel.profileMaturity)
            VStack(alignment: .leading, spacing: 4) {
                Text("profile maturity")
                    .font(AppTheme.mono(size: 10))
                    .foregroundStyle(AppTheme.inkSoft)
                    .tracking(1.2)
                    .textCase(.uppercase)
                Text(vm.selfModel.profileMaturity.rawValue.capitalized)
                    .font(AppTheme.editorialDisplay(size: 20, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
            }
            Spacer()
        }
        .softCard(cornerRadius: 22, padding: 16)
    }

    private func maturityRing(maturity: ProfileMaturity) -> some View {
        let fill: CGFloat = {
            switch maturity {
            case .seed:        return 0.1
            case .sprouting:   return 0.35
            case .growing:     return 0.65
            case .established: return 1.0
            }
        }()
        return ZStack {
            Circle()
                .stroke(AppTheme.paperWarm, lineWidth: 7)
            Circle()
                .trim(from: 0, to: fill)
                .stroke(
                    AngularGradient(
                        colors: [AppTheme.terracotta, AppTheme.lav, AppTheme.terracotta],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 44, height: 44)
    }

    // MARK: - Narrative header ("The Story So Far")

    private func narrativeHeader(_ narrative: MirrorNarrative) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("the story so far")
                .font(AppTheme.mono(size: 10))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(1.2)
                .textCase(.uppercase)

            Text(narrative.narrative)
                .font(AppTheme.editorialBody(size: 15))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            if !narrative.shifting.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("what's shifting")
                        .font(AppTheme.mono(size: 9))
                        .foregroundStyle(AppTheme.inkSoft)
                        .tracking(1)
                        .textCase(.uppercase)
                    ForEach(Array(narrative.shifting.prefix(3).enumerated()), id: \.offset) { _, shift in
                        HStack(spacing: 8) {
                            Text(shift.direction == .growing ? "\u{2197}" : "\u{2198}")
                                .font(.system(size: 14))
                            Text(shift.signal)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.ink)
                        }
                    }
                }
            }

            if let question = narrative.openQuestion, !question.isEmpty {
                Text(question)
                    .font(AppTheme.editorialBody(size: 13).italic())
                    .foregroundStyle(AppTheme.inkSoft)
                    .padding(.top, 4)
            }
        }
        .softCard(cornerRadius: 22, padding: 18)
    }

    // MARK: - Rules section

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Rules you seem to run on")
            ForEach(vm.selfModel.coreRules.filter { $0.isActive && $0.isProfileSurfaceable }) { h in
                hypothesisCard(for: h)
            }
        }
    }

    // MARK: - Protective section

    private var protectiveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("What you do when it gets hard")
            ForEach(vm.selfModel.protectiveStrategies.filter { $0.isActive && $0.asHypothesis.isProfileSurfaceable }) { h in
                protectiveCard(for: h)
            }
        }
    }

    // MARK: - Inner parts section

    private var innerPartsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Parts that show up")
            ForEach(vm.selfModel.innerParts.filter { $0.confidence > 0.3 }) { part in
                innerPartCard(for: part)
            }
        }
    }

    // MARK: - What helps section

    private var whatHelpsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("What helps")
            ForEach(vm.selfModel.whatHelps.filter { $0.isActive && $0.isProfileSurfaceable }) { h in
                hypothesisCard(for: h, eyebrow: "what helps")
            }
        }
    }

    // MARK: - Vocabulary section

    private var vocabularySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Your words")
            FlowLayout(spacing: 8) {
                ForEach(vm.selfModel.vocabulary, id: \.word) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.word)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                        Text(entry.personalMeaning)
                            .font(AppTheme.mono(size: 9))
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppTheme.lav.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .softCard(cornerRadius: 22, padding: 16)
        }
    }

    // MARK: - People and the part you play (§5.6)

    private var relationshipRolesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("People and the part you play")
            ForEach(vm.selfModel.relationshipRoles) { role in
                VStack(alignment: .leading, spacing: 6) {
                    Text(role.context)
                        .font(AppTheme.editorialDisplay(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(role.role)
                        .font(AppTheme.editorialBody(size: 14))
                        .foregroundStyle(AppTheme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .softCard(cornerRadius: 20, padding: 16)
            }
        }
    }

    // MARK: - Empty state (§5.6)

    /// True when every gated section came up empty — which at 7 entries is the
    /// normal, correct state.
    private var isProfileEmpty: Bool {
        vm.selfModel.coreRules.filter { $0.isActive && $0.isProfileSurfaceable }.isEmpty &&
        vm.selfModel.protectiveStrategies.filter { $0.isActive && $0.asHypothesis.isProfileSurfaceable }.isEmpty &&
        vm.selfModel.whatHelps.filter { $0.isActive && $0.isProfileSurfaceable }.isEmpty &&
        vm.selfModel.absences.filter(\.isActive).isEmpty &&
        vm.selfModel.relationshipRoles.isEmpty &&
        vm.selfModel.vocabulary.isEmpty
    }

    private var profileEmptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing here yet")
                .font(AppTheme.editorialDisplay(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            Text("This fills in when something shows up on three different days and holds up when Spilr checks it against your other entries.")
                .font(AppTheme.editorialBody(size: 14))
                .foregroundStyle(AppTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(cornerRadius: 22, padding: 18)
    }

    // MARK: - Open questions section

    private func openQuestionsSection(questions: [SelfModelHypothesis]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Questions still open")
            ForEach(questions) { q in
                HStack(spacing: 14) {
                    Text("?")
                        .font(AppTheme.editorialDisplay(size: 28, weight: .bold))
                        .foregroundStyle(AppTheme.terracotta.opacity(0.5))
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(q.title)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                        Text("Still emerging — waiting for more data.")
                            .font(AppTheme.editorialBody(size: 12))
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                    Spacer()
                }
                .softCard(cornerRadius: 18, padding: 14)
            }
        }
    }

    // MARK: - hypothesisCard

    /// Shared card body for both `rulesSection` ("Rules I may be living by")
    /// and `whatHelpsSection` ("What softens it") — they used to be
    /// indistinguishable, both hardcoding the eyebrow "rule you may carry",
    /// so an exception mislabelled itself as a rule
    /// (mirror-v3-prd-2026-09-10.md §1). `eyebrow` lets each section speak
    /// for itself again.
    private func hypothesisCard(for h: SelfModelHypothesis, eyebrow: String = "rule you may carry") -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(eyebrow)
                    .font(AppTheme.mono(size: 9))
                    .foregroundStyle(AppTheme.inkSoft)
                    .tracking(1)
                    .textCase(.uppercase)
                Spacer()
                statusPill(lifecycle: h.lifecycle)
            }

            Text(h.title)
                .font(AppTheme.editorialDisplay(size: 22, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(h.hypothesis)
                .font(AppTheme.editorialBody(size: 15))
                .foregroundStyle(AppTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            metaChips(timesSeen: h.timesSeen, lastSeenAt: h.lastSeenAt, scope: h.scope.rawValue)

            cardActions(hypothesisId: h.id, isConfirmed: h.userStatus == .thisIsMe)
        }
        .softCard(cornerRadius: 24, padding: 18)
    }

    // MARK: - Absences section ("what's gone quiet")

    /// The one section in this screen whose *detection* is arithmetic rather
    /// than inferred. The server compares how often something appeared in a
    /// baseline window against a recent window that contains it zero times, and
    /// hands the model hard counts to phrase. Nothing here is a guess, which is
    /// why it's allowed to be the most specific thing on the screen.
    private var absencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("What's gone quiet")
            ForEach(vm.selfModel.absences.filter(\.isActive)) { h in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("stopped showing up")
                            .font(AppTheme.mono(size: 9))
                            .foregroundStyle(AppTheme.inkSoft)
                            .tracking(1)
                            .textCase(.uppercase)
                        Spacer()
                        statusPill(lifecycle: h.lifecycle)
                    }

                    Text(h.title)
                        .font(AppTheme.editorialDisplay(size: 22, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(h.hypothesis)
                        .font(AppTheme.editorialBody(size: 15))
                        .foregroundStyle(AppTheme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)

                    // No confidence hedge here: an absence is counted, not
                    // inferred. Hedging a fact reads as evasive.
                    metaChips(timesSeen: h.timesSeen,
                              lastSeenAt: h.lastSeenAt,
                              scope: h.scope.rawValue)

                    cardActions(hypothesisId: h.id,
                                isConfirmed: h.userStatus == .thisIsMe)
                }
                .softCard(cornerRadius: 24, padding: 18)
            }
        }
    }

    // MARK: - protectiveCard

    private func protectiveCard(for h: ProtectiveHypothesis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("protective move")
                    .font(AppTheme.mono(size: 9))
                    .foregroundStyle(AppTheme.inkSoft)
                    .tracking(1)
                    .textCase(.uppercase)
                Spacer()
                statusPill(lifecycle: h.lifecycle)
            }

            Text(h.title)
                .font(AppTheme.editorialDisplay(size: 22, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(h.hypothesis)
                .font(AppTheme.editorialBody(size: 15))
                .foregroundStyle(AppTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("May protect")
                        .font(AppTheme.mono(size: 10))
                        .foregroundStyle(AppTheme.inkSoft)
                    Text(h.protectsAgainst)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Possible cost")
                        .font(AppTheme.mono(size: 10))
                        .foregroundStyle(AppTheme.inkSoft)
                    Text(h.possibleCost)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                }
            }

            metaChips(timesSeen: h.timesSeen, lastSeenAt: h.lastSeenAt, scope: h.scope.rawValue)

            cardActions(hypothesisId: h.id, isConfirmed: h.userStatus == .thisIsMe)
        }
        .softCard(cornerRadius: 24, padding: 18)
    }

    // MARK: - innerPartCard

    private func innerPartCard(for part: InnerPart) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("part that shows up")
                .font(AppTheme.mono(size: 9))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(1)
                .textCase(.uppercase)

            Text(part.name)
                .font(AppTheme.editorialDisplay(size: 22, weight: .bold))
                .foregroundStyle(AppTheme.ink)

            Text(part.description)
                .font(AppTheme.editorialBody(size: 15))
                .foregroundStyle(AppTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            if !part.commonTriggers.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(part.commonTriggers, id: \.self) { trigger in
                        Text(trigger)
                            .font(AppTheme.mono(size: 10))
                            .foregroundStyle(AppTheme.ink)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(AppTheme.peach.opacity(0.3))
                            .clipShape(Capsule())
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    vm.selectedHypothesisId = part.id
                    vm.showCorrectionSheet = true
                } label: {
                    Text("Correct")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .overlay(Capsule().stroke(AppTheme.inkSoft.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .softCard(cornerRadius: 24, padding: 18)
    }

    // MARK: - Shared card sub-views

    private func statusPill(lifecycle: HypothesisLifecycle) -> some View {
        let label: String = {
            switch lifecycle {
            case .observedOnce:  return "emerging"
            case .emerging:      return "emerging"
            case .recurring:     return "recurring"
            case .userConfirmed: return "confirmed"
            case .weakened:      return "weakening"
            case .retired:       return "retired"
            }
        }()
        return Text(label)
            .font(AppTheme.mono(size: 9))
            .foregroundStyle(AppTheme.terracotta)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.terracotta.opacity(0.12))
            .clipShape(Capsule())
    }

    private func metaChips(timesSeen: Int, lastSeenAt: Date, scope: String) -> some View {
        HStack(spacing: 8) {
            // timesSeen now counts distinct supporting ENTRIES. It used to count
            // nightly cron runs, which made this chip a straightforward lie —
            // it climbed every night whether or not anything was written.
            metaChip("\(timesSeen) \(timesSeen == 1 ? "entry" : "entries")")
            metaChip("Last seen \(lastSeenAt.formatted(.dateTime.month().day()))")
            metaChip(scope.replacingOccurrences(of: "_", with: " "))
        }
    }

    /// The honesty row: how sure this is, and how well-tested.
    ///
    /// Deliberately words, never a percentage — a number implies a precision no
    /// language model has about a person. This is also the cheapest defence
    /// against the two failure modes that actually lose trust: "that's obvious"
    /// costs nothing when the app called it a hunch, and "that's wrong" costs
    /// nothing when the app already said it hadn't checked.
    // MARK: - confidenceRow — DELETED (Mirror v3 M7)
    //
    // Printed the ConfidenceBand ("A hunch" / "Might be a thing" / …) and the
    // evidence caveat under every card. Two problems, and the second is the
    // real one: it put the internal ontology on screen, and on 17 of 19 cards
    // the caveat it printed was "Not checked against other entries yet" —
    // the app volunteering that it had not done its own homework, as a
    // caption, on a claim about the reader. §5.6 shows only items that are
    // audited or user-confirmed, which makes a confidence caption redundant
    // by construction: everything on screen has already cleared the bar.

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(AppTheme.mono(size: 9))
            .foregroundStyle(AppTheme.inkSoft)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.paperWarm.opacity(0.8))
            .clipShape(Capsule())
    }

    /// TWO taps, not four (Mirror v3 §5.6).
    ///
    /// The old row was "This is me" / "Correct" / "This is done" / "Hide" on
    /// EVERY card — 76 buttons on the account in the 9 Sept screenshots. The
    /// two decisions a person actually makes about a claim are "yes that's me"
    /// and "no it isn't"; the other two are housekeeping and belong behind the
    /// overflow.
    ///
    /// "This is me" still lives here as well as on the Today card. Both write
    /// `userStatus: this_is_me`, which is what unlocks the `user_confirmed`
    /// lifecycle, the 0.85 confidence floor and the decay exemption.
    private func cardActions(hypothesisId: String, isConfirmed: Bool = false) -> some View {
        HStack(spacing: 10) {
            Button {
                vm.markHypothesis(id: hypothesisId,
                                  status: isConfirmed ? .unrated : .thisIsMe)
            } label: {
                Text(isConfirmed ? "Confirmed" : "That's me")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(isConfirmed ? AppTheme.mint : AppTheme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(isConfirmed ? AppTheme.mint.opacity(0.12) : .clear)
                    .overlay(Capsule().stroke(
                        isConfirmed ? AppTheme.mint : AppTheme.inkSoft.opacity(0.4),
                        lineWidth: 1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                vm.selectedHypothesisId = hypothesisId
                vm.showCorrectionSheet = true
            } label: {
                Text("Not quite")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .overlay(Capsule().stroke(AppTheme.inkSoft.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            // THE FORGET AFFORDANCE, kept but demoted. "Remembers everything"
            // and "keeps bringing up what I've moved past" are the same
            // feature, and the second is why people quit memory-heavy apps.
            // Without it, the only way to stop hearing about something you
            // have genuinely resolved is to tell the app it was wrong — which
            // poisons the corrections that are meant to be ground truth.
            Menu {
                Button("This is done") { vm.closeHypothesis(id: hypothesisId) }
                Button("Hide from profile", role: .destructive) {
                    vm.hideHypothesis(id: hypothesisId)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.inkSoft)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
            }
        }
    }

    // MARK: - Correction sheet

    private var correctionSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("What would you correct?")
                    .font(AppTheme.editorialDisplay(size: 22, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                TextEditor(text: $correctionText)
                    .font(AppTheme.editorialBody(size: 16))
                    .foregroundStyle(AppTheme.ink)
                    .frame(minHeight: 120)
                    .padding(14)
                    .background(AppTheme.cream.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 20)

                Button {
                    if !correctionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        vm.submitCorrection(text: correctionText, category: nil)
                    }
                    vm.showCorrectionSheet = false
                    correctionText = ""
                } label: {
                    Text("Submit correction")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.cream)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.terracotta)
                        .clipShape(Capsule())
                        .padding(.horizontal, 20)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .navigationTitle("Correct this")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { vm.showCorrectionSheet = false }
                        .foregroundStyle(AppTheme.inkSoft)
                }
            }
        }
    }

    // MARK: - Section label

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(AppTheme.inkSoft)
            .tracking(1.2)
    }
}
