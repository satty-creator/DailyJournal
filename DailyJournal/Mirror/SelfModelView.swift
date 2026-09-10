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

    func loadNarrative() async {
        let key = "mirrorNarrativeDate_\(userId)"
        let lastGenerated = UserDefaults.standard.object(forKey: key) as? Date
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)

        // Try cached narrative from Firestore first
        if let cached = await fetchCachedNarrative() {
            narrative = cached
            if let lastGenerated, lastGenerated > weekAgo { return }
        }

        // Generate fresh if stale or absent
        let hypotheses = MirrorGraphService.shared.hypotheses
        guard hypotheses.count >= 3 else { return }

        guard let fresh = await AIService.shared.generateMirrorNarrative(
            userId: userId,
            hypotheses: hypotheses
        ) else { return }

        narrative = fresh
        UserDefaults.standard.set(Date(), forKey: key)

        // Persist
        Firestore.firestore()
            .collection("users").document(userId)
            .collection("selfModel").document("narrative")
            .setData(fresh.toFirestoreData()) { _ in }
    }

    private func fetchCachedNarrative() async -> MirrorNarrative? {
        guard let snap = try? await Firestore.firestore()
            .collection("users").document(userId)
            .collection("selfModel").document("narrative")
            .getDocument(),
              snap.exists,
              let data = snap.data()
        else { return nil }
        return MirrorNarrative(from: data)
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
        NavigationStack {
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
                            if !vm.selfModel.coreRules.filter(\.isActive).isEmpty {
                                rulesSection
                            }
                            if !vm.selfModel.protectiveStrategies.filter(\.isActive).isEmpty {
                                protectiveSection
                            }
                            if !vm.selfModel.innerParts.filter({ $0.confidence > 0.3 }).isEmpty {
                                innerPartsSection
                            }
                            if !vm.selfModel.whatHelps.filter(\.isActive).isEmpty {
                                whatHelpsSection
                            }
                            // Placed high: an absence is the most specific,
                            // least horoscope-ish thing on this screen, and it
                            // is the only section that cannot be wrong about its
                            // own arithmetic.
                            if !vm.selfModel.absences.filter(\.isActive).isEmpty {
                                absencesSection
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
            sectionLabel("Rules I may be living by")
            ForEach(vm.selfModel.coreRules.filter(\.isActive)) { h in
                hypothesisCard(for: h)
            }
        }
    }

    // MARK: - Protective section

    private var protectiveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Protective moves")
            ForEach(vm.selfModel.protectiveStrategies.filter(\.isActive)) { h in
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
            sectionLabel("What softens it")
            ForEach(vm.selfModel.whatHelps.filter(\.isActive)) { h in
                hypothesisCard(for: h)
            }
        }
    }

    // MARK: - Vocabulary section

    private var vocabularySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Words that mean something here")
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

    private func hypothesisCard(for h: SelfModelHypothesis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("rule you may carry")
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

            confidenceRow(for: h)

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

            confidenceRow(for: h.asHypothesis)

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
    private func confidenceRow(for h: SelfModelHypothesis) -> some View {
        let caveat = h.evidenceCaveat
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(confidenceTint(h.confidenceBand))
                    .frame(width: 6, height: 6)
                Text(h.confidenceBand.rawValue)
                    .font(AppTheme.mono(size: 10))
                    .foregroundStyle(AppTheme.inkSoft)
                    .tracking(0.5)
            }
            if !caveat.isEmpty {
                Text(caveat)
                    .font(AppTheme.mono(size: 9))
                    .foregroundStyle(AppTheme.inkSoft.opacity(0.75))
            }
        }
    }

    private func confidenceTint(_ band: SelfModelHypothesis.ConfidenceBand) -> Color {
        switch band {
        case .hunch:  return AppTheme.inkSoft.opacity(0.4)
        case .maybe:  return AppTheme.terracotta.opacity(0.6)
        case .likely: return AppTheme.terracotta
        case .yours:  return AppTheme.mint
        }
    }

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(AppTheme.mono(size: 9))
            .foregroundStyle(AppTheme.inkSoft)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.paperWarm.opacity(0.8))
            .clipShape(Capsule())
    }

    private func cardActions(hypothesisId: String, isConfirmed: Bool = false) -> some View {
        HStack(spacing: 10) {
            // "This is me" lives HERE and nowhere else. Removing it from the daily
            // card left the app with zero producers of `this_is_me`, which quietly
            // made three things unreachable: the `user_confirmed` lifecycle, the
            // "you confirmed this" confidence band, and the decay exemption — so
            // no hypothesis could ever survive 45 days. This is the deliberate
            // review context the signal was always meant to come from.
            Button {
                vm.markHypothesis(id: hypothesisId,
                                  status: isConfirmed ? .unrated : .thisIsMe)
            } label: {
                Text(isConfirmed ? "Confirmed" : "This is me")
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
                Text("Correct")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .overlay(Capsule().stroke(AppTheme.inkSoft.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)

            // THE FORGET AFFORDANCE. "Remembers everything" and "keeps bringing
            // up what I've moved past" are the same feature, and users of every
            // memory-heavy app describe the second one as the reason they quit.
            // Without this, the only way to stop hearing about something you
            // have genuinely resolved is to tell the app it was wrong — which
            // poisons the corrections that are meant to be ground truth.
            Button {
                vm.closeHypothesis(id: hypothesisId)
            } label: {
                Text("This is done")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.mint)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .overlay(Capsule().stroke(AppTheme.mint.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button {
                vm.hideHypothesis(id: hypothesisId)
            } label: {
                Text("Hide")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.inkSoft)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
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
