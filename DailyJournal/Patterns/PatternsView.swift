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
                AppTheme.paper.ignoresSafeArea()

                if vm.isLoading {
                    ProgressView("Reading your patterns…")
                        .tint(AppTheme.terracotta)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 32) {
                            if vm.hasWeeklyRecap { weeklyRecapSection }
                            resilienceCard
                            activityGrid
                            if !vm.moodDistribution.isEmpty { moodSection }
                            statsRow
                            if !vm.frequentWords.isEmpty { wordsCloud }
                            if !vm.frequentTags.isEmpty  { tagsSection }
                            Spacer(minLength: 80)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    }
                }
            }
            .navigationTitle("Patterns")
            .navigationBarTitleDisplayMode(.large)
            .task { await vm.load() }
            .refreshable { await vm.load() }
        }
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
    private var resilienceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RESILIENCE SCORE")
                        .font(AppTheme.mono(size: 10))
                        .foregroundStyle(AppTheme.inkSoft)
                        .tracking(2)
                    Text(vm.resilienceLabel)
                        .font(AppTheme.editorialDisplay(size: 28))
                        .foregroundStyle(AppTheme.cream)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("\(vm.resilienceScore)")
                        .font(AppTheme.editorialDisplay(size: 52))
                        .foregroundStyle(AppTheme.cream)
                    Text("of 30 days")
                        .font(AppTheme.mono(size: 11))
                        .foregroundStyle(AppTheme.cream.opacity(0.6))
                        .tracking(1)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppTheme.cream.opacity(0.2))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppTheme.cream)
                        .frame(width: geo.size.width * CGFloat(vm.resilienceScore) / 30.0, height: 6)
                        .animation(.spring(response: 0.8), value: vm.resilienceScore)
                }
            }
            .frame(height: 6)

            Text("No streak to break. Just showing up.")
                .font(AppTheme.editorialBody(size: 13))
                .foregroundStyle(AppTheme.cream.opacity(0.7))
                .italic()
        }
        .padding(20)
        .background(AppTheme.ink)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Activity grid (last 30 days)
    private var activityGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Last 30 days")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 10), spacing: 4) {
                ForEach(vm.last30Days, id: \.date) { day in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(day.hasEntry ? AppTheme.terracotta : AppTheme.paperWarm)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(
                            day.hasEntry ? nil :
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(AppTheme.inkSoft.opacity(0.1), lineWidth: 0.5)
                        )
                }
            }
            HStack {
                Circle().fill(AppTheme.paperWarm).frame(width: 10, height: 10)
                Text("No entry").font(AppTheme.mono(size: 10)).foregroundStyle(AppTheme.inkSoft)
                Spacer().frame(width: 16)
                Circle().fill(AppTheme.terracotta).frame(width: 10, height: 10)
                Text("Journaled").font(AppTheme.mono(size: 10)).foregroundStyle(AppTheme.inkSoft)
            }
            .padding(.top, 2)
        }
    }

    // MARK: - Mood distribution
    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Mood (last 30)")
            ForEach(vm.moodDistribution, id: \.mood) { item in
                HStack(spacing: 10) {
                    Text(item.mood.faceEmoji)
                        .font(.title3)
                    Text(item.mood.scaleLabel)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(AppTheme.moodColor(item.mood).opacity(0.7))
                            .frame(
                                width: geo.size.width * CGFloat(item.count) / CGFloat(max(vm.moodDistribution.first?.count ?? 1, 1)),
                                height: 8
                            )
                    }
                    .frame(height: 8)
                    Text("\(item.count)")
                        .font(AppTheme.mono(size: 11))
                        .foregroundStyle(AppTheme.inkSoft)
                        .frame(width: 24, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Stats row
    private var statsRow: some View {
        HStack(spacing: 10) {
            statCell(value: "\(vm.totalEntries)", label: "entries")
            Divider().frame(height: 40)
            statCell(value: "\(vm.totalWords)", label: "words")
            Divider().frame(height: 40)
            statCell(value: "\(vm.sessionsThisWeek)", label: "this week")
            Divider().frame(height: 40)
            statCell(value: "\(vm.ninetySecondSessions)", label: "90-sec")
        }
        .padding(16)
        .background(AppTheme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(AppTheme.editorialDisplay(size: 24))
                .foregroundStyle(AppTheme.ink)
            Text(label)
                .font(AppTheme.mono(size: 9))
                .foregroundStyle(AppTheme.inkSoft)
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Word cloud
    private var wordsCloud: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Words you return to")
            FlowLayout(spacing: 8) {
                ForEach(vm.frequentWords, id: \.word) { item in
                    HStack(spacing: 4) {
                        Text(item.word)
                            .font(.system(size: 13, weight: .medium))
                        Text("×\(item.count)")
                            .font(AppTheme.mono(size: 10))
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.cream)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(AppTheme.inkSoft.opacity(0.15), lineWidth: 1))
                    .foregroundStyle(AppTheme.ink)
                }
            }
        }
    }

    // MARK: - Tags section
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Recurring tags")
            ForEach(vm.frequentTags, id: \.tag) { item in
                HStack {
                    Text("#\(item.tag)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.terracotta)
                    Spacer()
                    Text("\(item.count) entries")
                        .font(AppTheme.mono(size: 11))
                        .foregroundStyle(AppTheme.inkSoft)
                }
                .padding(.vertical, 6)
                Divider().overlay(AppTheme.inkSoft.opacity(0.1))
            }
        }
    }

    // MARK: - Section label
    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(AppTheme.mono(size: 10))
            .foregroundStyle(AppTheme.inkSoft)
            .tracking(1.5)
    }
}
