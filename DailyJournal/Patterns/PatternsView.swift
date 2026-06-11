//
//  PatternsView.swift
//  DailyJournal
//
//  Resilience score + pattern detection. No streak counter.
//

import SwiftUI

@MainActor
final class PatternsViewModel: ObservableObject {
    @Published var entries: [JournalEntry] = []
    @Published var moodLogs: [MoodLog] = []
    @Published var isLoading = false

    private let service = JournalService()
    private let moodService = MoodLogService()
    let userId: String

    init(userId: String) { self.userId = userId }

    func load() async {
        isLoading = true
        async let allEntries = (try? await service.fetchAllEntries(for: userId)) ?? []
        async let recentMoods = (try? await moodService.fetchRecent(for: userId, days: 30)) ?? []
        entries  = await allEntries
        moodLogs = await recentMoods
        isLoading = false
    }

    // Days journaled out of last 30
    var resilienceScore: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let recent = entries.filter { $0.createdAt >= cutoff }
        let uniqueDays = Set(recent.map { Calendar.current.startOfDay(for: $0.createdAt) })
        return uniqueDays.count
    }

    var resilienceLabel: String {
        switch resilienceScore {
        case 0...5:   return "Getting started"
        case 6...12:  return "Building the habit"
        case 13...20: return "Consistent"
        case 21...26: return "Strong"
        default:      return "Exceptional"
        }
    }

    // Last 30 days as calendar grid
    var last30Days: [(date: Date, hasEntry: Bool)] {
        let cal = Calendar.current
        return (0..<30).reversed().map { daysAgo in
            let date = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: Date()))!
            let has  = entries.contains { cal.isDate($0.createdAt, inSameDayAs: date) }
            return (date, has)
        }
    }

    // Mood distribution (last 30 entries + standalone daily mood logs)
    var moodDistribution: [(mood: Mood, count: Int)] {
        let recent = Array(entries.prefix(30))
        var counts: [Mood: Int] = [:]
        for entry in recent {
            if let mood = entry.mood { counts[mood, default: 0] += 1 }
        }
        // Fold in journal-free daily mood check-ins.
        for log in moodLogs {
            counts[log.mood, default: 0] += 1
        }
        return Mood.allCases.compactMap { mood in
            guard let count = counts[mood], count > 0 else { return nil }
            return (mood, count)
        }.sorted { $0.count > $1.count }
    }

    // Frequent tags (3+ occurrences)
    var frequentTags: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for entry in entries {
            for tag in entry.tags { counts[tag, default: 0] += 1 }
        }
        return counts
            .filter { $0.value >= 2 }
            .map { (tag: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(10)
            .map { $0 }
    }

    // Frequent words in content (excluding stop words)
    var frequentWords: [(word: String, count: Int)] {
        let stopWords = Set(["the","a","an","and","or","but","in","on","at","to","for","of",
                             "with","i","is","it","my","me","was","be","have","had","that",
                             "this","are","not","do","did","so","as","we","he","she","they",
                             "you","just","can","will","would","could","should","what","when",
                             "how","why","been","from","all","by","if","about","up","out",
                             "like","his","her","its","their","our","your","im","dont","cant",
                             "wont","feel","think","know","get","got","go","went","still",
                             "than","more","really","very","too","even","then","there","here",
                             "also","back","time","way","some","into","over","after","before"])
        var counts: [String: Int] = [:]
        for entry in entries {
            let words = entry.content
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
            for word in words where word.count > 3 && !stopWords.contains(word) {
                counts[word, default: 0] += 1
            }
        }
        return counts
            .filter { $0.value >= 3 }
            .map { (word: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(12)
            .map { $0 }
    }

    var totalEntries: Int { entries.count }
    var totalWords: Int { entries.reduce(0) { $0 + $1.wordCount } }

    var sessionsThisWeek: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        return entries.filter { $0.createdAt >= cutoff }.count
    }

    var ninetySecondSessions: Int {
        entries.filter { $0.sessionType == .ninetySecond }.count
    }

    // MARK: - Weekly "wrapped" recap (last 7 days)

    private var weekCutoff: Date { Calendar.current.date(byAdding: .day, value: -7, to: Date())! }
    private var weekEntries: [JournalEntry] { entries.filter { $0.createdAt >= weekCutoff } }

    var weekWordCount: Int { weekEntries.reduce(0) { $0 + $1.wordCount } }

    /// Unique days journaled this week.
    var weekActiveDays: Int {
        Set(weekEntries.map { Calendar.current.startOfDay(for: $0.createdAt) }).count
    }

    /// Most frequent mood across this week's entries + daily mood logs.
    var weekTopMood: Mood? {
        var counts: [Mood: Int] = [:]
        for e in weekEntries { if let m = e.mood { counts[m, default: 0] += 1 } }
        for log in moodLogs where log.createdAt >= weekCutoff { counts[log.mood, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key
    }

    /// A representative line from the week — the latest entry's first AI bullet,
    /// or a short excerpt.
    var weekStandoutLine: String? {
        guard let latest = weekEntries.max(by: { $0.createdAt < $1.createdAt }) else { return nil }
        if let bullet = latest.aiSummaryBullets.first, !bullet.isEmpty { return bullet }
        let text = latest.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return String(text.prefix(120)) + (text.count > 120 ? "…" : "")
    }

    var hasWeeklyRecap: Bool { !weekEntries.isEmpty }
}

// MARK: - Patterns View
struct PatternsView: View {
    @StateObject private var vm: PatternsViewModel

    init(userId: String) {
        _vm = StateObject(wrappedValue: PatternsViewModel(userId: userId))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                pastelBackground.ignoresSafeArea()

                if vm.isLoading {
                    ProgressView("Reading your patterns…")
                        .tint(AppTheme.terracotta)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if vm.hasWeeklyRecap { weeklyRecapSection }
                            resilienceCard
                            activityGrid
                            if !vm.moodDistribution.isEmpty { moodSection }
                            statsRow
                            if !vm.frequentWords.isEmpty { wordsCloud }
                            if !vm.frequentTags.isEmpty  { tagsSection }
                            Spacer(minLength: 90)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("Patterns")
            .navigationBarTitleDisplayMode(.large)
            .task { await vm.load() }
            .refreshable { await vm.load() }
        }
    }

    // MARK: - Background
    // Same soft pastel wash the River tab uses, so the two analytic surfaces
    // feel like siblings rather than two different apps.
    private var pastelBackground: some View {
        LinearGradient(
            colors: [AppTheme.paper, AppTheme.rose2.opacity(0.4), AppTheme.blue.opacity(0.3)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    // MARK: - Weekly recap
    private var weeklyRecapSection: some View {
        VStack(alignment: .trailing, spacing: 10) {
            WeeklyWrappedCard(
                activeDays:   vm.weekActiveDays,
                wordCount:    vm.weekWordCount,
                topMood:      vm.weekTopMood,
                standoutLine: vm.weekStandoutLine
            )
            ShareWeeklyButton(
                activeDays:   vm.weekActiveDays,
                wordCount:    vm.weekWordCount,
                topMood:      vm.weekTopMood,
                standoutLine: vm.weekStandoutLine
            )
        }
    }

    // MARK: - Resilience card
    // A soft pastel card with a conic-gradient ring (echoes the 90-second timer
    // ring and the River's vocabulary) instead of the old dark editorial slab.
    private var resilienceCard: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(AppTheme.paperWarm, lineWidth: 13)
                Circle()
                    .trim(from: 0, to: max(0.02, CGFloat(vm.resilienceScore) / 30.0))
                    .stroke(
                        AngularGradient(
                            colors: [AppTheme.rose, AppTheme.lav, AppTheme.blue, AppTheme.mint, AppTheme.rose],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 13, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.8), value: vm.resilienceScore)
                VStack(spacing: 0) {
                    Text("\(vm.resilienceScore)")
                        .font(AppTheme.editorialDisplay(size: 38))
                        .foregroundStyle(AppTheme.ink)
                    Text("of 30")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.inkSoft)
                }
            }
            .frame(width: 118, height: 118)

            VStack(alignment: .leading, spacing: 7) {
                sectionLabel("Resilience")
                Text(vm.resilienceLabel)
                    .font(AppTheme.editorialDisplay(size: 25))
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("No streak to break. Just showing up.")
                    .font(AppTheme.editorialBody(size: 13))
                    .foregroundStyle(AppTheme.inkSoft)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .softCard(cornerRadius: 28)
    }

    // MARK: - Activity grid (last 30 days)
    // Soft pastel "pebbles" — journaled days glow rose→lavender, quiet days
    // sit as pale mist. Cute, but still a legible 30-day read.
    private var pebbleFill: LinearGradient {
        LinearGradient(colors: [AppTheme.rose, AppTheme.lav],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var activityGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Last 30 days")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 10), spacing: 6) {
                ForEach(vm.last30Days, id: \.date) { day in
                    Circle()
                        .fill(day.hasEntry ? AnyShapeStyle(pebbleFill) : AnyShapeStyle(AppTheme.paperWarm))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(
                            Circle().stroke(AppTheme.cream, lineWidth: day.hasEntry ? 1.5 : 0)
                        )
                        .shadow(color: day.hasEntry ? AppTheme.rose.opacity(0.25) : .clear,
                                radius: 4, x: 0, y: 2)
                }
            }
            HStack(spacing: 7) {
                Circle().fill(AppTheme.paperWarm).frame(width: 11, height: 11)
                Text("quiet").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(AppTheme.inkSoft)
                Spacer().frame(width: 14)
                Circle().fill(pebbleFill).frame(width: 11, height: 11)
                Text("journaled").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(AppTheme.inkSoft)
            }
            .padding(.top, 4)
        }
        .softCard(cornerRadius: 28)
    }

    // MARK: - Mood distribution
    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Mood (last 30)")
            ForEach(vm.moodDistribution, id: \.mood) { item in
                HStack(spacing: 10) {
                    Text(item.mood.faceEmoji)
                        .font(.title3)
                    Text(item.mood.scaleLabel)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    GeometryReader { geo in
                        Capsule()
                            .fill(LinearGradient(
                                colors: [AppTheme.moodColor(item.mood).opacity(0.95),
                                         AppTheme.moodColor(item.mood).opacity(0.45)],
                                startPoint: .leading, endPoint: .trailing))
                            .frame(
                                width: max(12, geo.size.width * CGFloat(item.count) / CGFloat(max(vm.moodDistribution.first?.count ?? 1, 1))),
                                height: 11
                            )
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 11)
                    Text("\(item.count)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.inkSoft)
                        .frame(width: 24, alignment: .trailing)
                }
            }
        }
        .softCard(cornerRadius: 28)
    }

    // MARK: - Stats row
    private var statsRow: some View {
        HStack(spacing: 6) {
            statCell(value: "\(vm.totalEntries)", label: "entries")
            statCell(value: "\(vm.totalWords)", label: "words")
            statCell(value: "\(vm.sessionsThisWeek)", label: "this week")
            statCell(value: "\(vm.ninetySecondSessions)", label: "90-sec")
        }
        .softCard(cornerRadius: 28, padding: 18)
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(AppTheme.editorialDisplay(size: 24))
                .foregroundStyle(AppTheme.ink)
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    // Rotating soft pastel chip tints for words & tags.
    private func chipTint(_ i: Int) -> Color {
        [AppTheme.rose2,
         AppTheme.blue.opacity(0.45),
         AppTheme.lav.opacity(0.5),
         AppTheme.mint.opacity(0.6),
         AppTheme.peach.opacity(0.5)][i % 5]
    }

    // MARK: - Word cloud
    private var wordsCloud: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Words you return to")
            FlowLayout(spacing: 8) {
                ForEach(Array(vm.frequentWords.enumerated()), id: \.element.word) { idx, item in
                    HStack(spacing: 5) {
                        Text(item.word)
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                        Text("×\(item.count)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(chipTint(idx))
                    .clipShape(Capsule())
                    .foregroundStyle(AppTheme.ink)
                }
            }
        }
        .softCard(cornerRadius: 28)
    }

    // MARK: - Tags section
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Recurring tags")
            ForEach(Array(vm.frequentTags.enumerated()), id: \.element.tag) { idx, item in
                HStack {
                    Text("#\(item.tag)")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    Text("\(item.count) entries")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.inkSoft)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(chipTint(idx))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .softCard(cornerRadius: 28)
    }

    // MARK: - Section label
    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(AppTheme.inkSoft)
            .tracking(1.2)
    }
}
