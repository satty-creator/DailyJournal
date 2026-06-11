//
//  NoticedView.swift  →  EchoesView
//  DailyJournal
//
//  The "Echoes" tab — a Google-Photos-Memories-style retrospective surface that
//  always has something to say about you. It replaces the old Noticed shelf:
//  where River is the picture (the shape of a window) and Patterns is the
//  dashboard, Echoes is the *memory* — resurfaced moments, recurring themes,
//  "on this day", patterns, and last week as a river.
//
//  It's built from everything ninety already has: Echoes (AI callbacks), Pattern
//  Callbacks, the MemoryProfile digest, on-this-day entries, and the River. Those
//  used to flash once on the Home screen and vanish; here they have a home.
//

import SwiftUI

@MainActor
final class EchoesViewModel: ObservableObject {
    @Published var entries: [JournalEntry] = []
    @Published var echoes: [Echo] = []
    @Published var callbacks: [PatternCallback] = []
    @Published var river: River?
    @Published var profile: MemoryProfile?
    @Published var isLoading = true

    private let journal       = JournalService()
    private let riverService  = RiverService()
    private let echoService   = EchoService()
    private let callbackSvc   = PatternCallbackService()
    let userId: String

    init(userId: String) { self.userId = userId }

    func load() async {
        isLoading = true

        if let e = try? await journal.fetchAllEntries(for: userId) {
            entries = e
            await riverService.backfillLocalMarks(from: e, userId: userId)
        }

        river     = await riverService.buildRiver(window: .week, for: userId)
        echoes    = (try? await echoService.fetchAll(for: userId)) ?? []
        callbacks = (try? await callbackSvc.fetchAll(for: userId)) ?? []
        // Compose + cache the durable profile (also refreshes the AI prompt context).
        profile   = await MemoryProfileService.shared.build(for: userId)

        isLoading = false
    }

    /// True if there is literally nothing to show yet.
    var isEmpty: Bool {
        entries.isEmpty && echoes.isEmpty && callbacks.isEmpty
    }

    // MARK: - Derived memories

    /// An "on this day" moment: a past entry sharing today's calendar day, or the
    /// nearest entry to ~one month ago. Returns the entry + a human label.
    var onThisDay: (entry: JournalEntry, label: String)? {
        let cal = Calendar.current
        let today = cal.dateComponents([.month, .day], from: Date())
        let twentyAgo = cal.date(byAdding: .day, value: -20, to: Date())!

        let sameDay = entries.filter {
            let c = cal.dateComponents([.month, .day], from: $0.createdAt)
            return c.month == today.month && c.day == today.day && $0.createdAt < twentyAgo
        }.max { $0.createdAt < $1.createdAt }
        if let e = sameDay { return (e, Self.agoLabel(e.createdAt)) }

        let monthAgo = cal.date(byAdding: .day, value: -30, to: Date())!
        let lo = cal.date(byAdding: .day, value: -34, to: Date())!
        let hi = cal.date(byAdding: .day, value: -26, to: Date())!
        if let e = entries.filter({ $0.createdAt >= lo && $0.createdAt <= hi })
            .min(by: { abs($0.createdAt.timeIntervalSince(monthAgo)) < abs($1.createdAt.timeIntervalSince(monthAgo)) }) {
            return (e, Self.agoLabel(e.createdAt))
        }
        return nil
    }

    static func agoLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                      to: cal.startOfDay(for: Date())).day ?? 0
        switch days {
        case ..<1:      return "today"
        case 1:         return "yesterday"
        case 2..<7:     return "\(days) days ago"
        case 7..<14:    return "last week"
        case 14..<45:   return "\(days / 7) weeks ago"
        case 45..<350:  return "\(max(1, days / 30)) months ago"
        default:        let y = max(1, days / 365); return "\(y) year\(y > 1 ? "s" : "") ago"
        }
    }
}

struct EchoesView: View {
    @StateObject private var vm: EchoesViewModel
    @State private var activeMemory: MemoryPopover?
    @State private var popoverProgress: CGFloat = 1

    init(userId: String) {
        _vm = StateObject(wrappedValue: EchoesViewModel(userId: userId))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        if !vm.isLoading { bubbleRow }

                        if vm.isLoading && vm.river == nil {
                            ProgressView().tint(AppTheme.terracotta)
                                .frame(maxWidth: .infinity).padding(.top, 60)
                        } else if vm.isEmpty {
                            emptyState
                        } else {
                            feed
                        }
                        Spacer(minLength: 110)
                    }
                    .padding(.top, 12)
                }
                .scrollIndicators(.hidden)
                .refreshable { await vm.load() }

                if let m = activeMemory {
                    memoryPopover(m)
                        .id(m.id)
                        .task(id: m.id) {
                            // Auto-close after 5s — cancelled automatically if the
                            // user closes it or opens a different memory (id changes).
                            try? await Task.sleep(nanoseconds: 5_000_000_000)
                            guard !Task.isCancelled else { return }
                            close()
                        }
                }
            }
            .navigationBarHidden(true)
            .task { if vm.river == nil { await vm.load() } }
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [AppTheme.paper, AppTheme.lav.opacity(0.3), AppTheme.rose2.opacity(0.35)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    // MARK: - Header
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("THINGS NINETY NOTICED")
                .font(AppTheme.mono(size: 11)).tracking(2).foregroundStyle(AppTheme.inkSoft)
            Text("Echoes")
                .font(AppTheme.editorialDisplay(size: 34)).foregroundStyle(AppTheme.ink)
            Text("Always something here about you. Tap a memory to sit with it.")
                .font(AppTheme.editorialBody(size: 14)).foregroundStyle(AppTheme.inkSoft)
        }
        .padding(.top, 44)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Memory bubbles (Google-Photos style)
    private var bubbleRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(bubbles, id: \.label) { b in
                    Button { open(b.popover) } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(AngularGradient(colors: b.ring, center: .center))
                                    .frame(width: 74, height: 74)
                                Circle()
                                    .fill(AppTheme.cream)
                                    .frame(width: 64, height: 64)
                                Text(b.popover.glyph).font(.system(size: 26))
                            }
                            Text(b.label)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.ink)
                                .lineLimit(1)
                        }
                        .frame(width: 78)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
    }

    private struct Bubble { let label: String; let ring: [Color]; let popover: MemoryPopover }

    private var bubbles: [Bubble] {
        var out: [Bubble] = []

        // ── Last week ──────────────────────────────────────────────────────
        if let r = vm.river, r.entryCount > 0 {
            var body = r.oneLineTruth
            let interpretation = r.privateInterpretation
            if !interpretation.isEmpty, interpretation != r.oneLineTruth {
                body += "\n\n" + interpretation
            }
            body += "\n\n" + r.countLabel + ". Not perfect attendance — return. That's the part that counts."
            out.append(.init(
                label: "Last week",
                ring: [AppTheme.rose, AppTheme.lav, AppTheme.blue, AppTheme.rose],
                popover: MemoryPopover(glyph: "🗓️", title: "Last week, as a current", body: body, tint: AppTheme.blue)))
        }

        // ── This year so far ───────────────────────────────────────────────
        let year = Calendar.current.component(.year, from: Date())
        out.append(.init(
            label: "\(year) so far",
            ring: [AppTheme.sun, AppTheme.peach, AppTheme.rose],
            popover: MemoryPopover(glyph: "✦", title: "\(year) so far", body: yearBody(), tint: AppTheme.peach)))

        // ── A recurring theme ──────────────────────────────────────────────
        if let theme = vm.profile?.recurringThemes.first {
            out.append(.init(
                label: "On: \(theme.word)",
                ring: [AppTheme.blue, AppTheme.mint, AppTheme.lav],
                popover: MemoryPopover(glyph: "🌙", title: "On “\(theme.word)”", body: themeBody(theme), tint: AppTheme.lav)))
        }

        // ── Returns ────────────────────────────────────────────────────────
        if let rm = vm.river?.returnMark {
            let body = rm + "\n\nThe river keeps the gap without turning it into a broken streak. "
                + "Coming back after a quiet stretch isn't catching up — it's the whole habit."
            out.append(.init(
                label: "Returns",
                ring: [AppTheme.lav, AppTheme.rose2, AppTheme.peach],
                popover: MemoryPopover(glyph: "🌉", title: "On coming back", body: body, tint: AppTheme.rose2)))
        }

        // ── A recurring name / place ───────────────────────────────────────
        if let entity = vm.profile?.recurringEntities.first {
            let body = "\(entity) keeps surfacing across your entries. ninety isn't reading anything into it — "
                + "just noticing it's there more than once. If it's quietly carrying weight, it might be worth a full ninety seconds the next time it comes up."
            out.append(.init(
                label: "On: \(entity)",
                ring: [AppTheme.mint, AppTheme.blue, AppTheme.lav],
                popover: MemoryPopover(glyph: "💬", title: "On \(entity)", body: body, tint: AppTheme.mint)))
        }
        return out
    }

    // Thoughtful body for the "year so far" memory, grounded in the profile.
    private func yearBody() -> String {
        let p = vm.profile
        let total = p?.totalEntries ?? vm.entries.count
        var lines = ["\(total) \(total == 1 ? "entry" : "entries")" + ((p?.sinceLabel).map { ", \($0)" } ?? "") + "."]

        if let week = p?.activeDaysThisWeek, let month = p?.activeDaysLast30 {
            lines.append("You've shown up \(week) of the last 7 days, and \(month) of the last 30.")
        }
        if let themes = p?.recurringThemes, !themes.isEmpty {
            let words = themes.prefix(3).map { $0.word }.joined(separator: ", ")
            lines.append("What's surfaced most: \(words).")
        }
        if let mood = p?.topMood {
            lines.append("The year has leaned \(mood.scaleLabel.lowercased()) — but moods move, and so have you.")
        }
        lines.append("Not every day needed words. You kept finding your way back anyway.")
        return lines.joined(separator: "\n\n")
    }

    // Thoughtful body for a recurring theme.
    private func themeBody(_ theme: MemoryProfile.Theme) -> String {
        var body = "“\(theme.word)” has surfaced \(theme.count) times in your writing."
        let others = (vm.profile?.recurringThemes ?? [])
            .dropFirst().prefix(3).map { $0.word }
        if !others.isEmpty {
            body += " It tends to travel alongside \(others.joined(separator: ", "))."
        }
        body += "\n\nWhen a word keeps coming back like this, it's usually standing in for something underneath it. Worth following the next time it shows up — not to solve it, just to name it."
        return body
    }

    // MARK: - Feed
    private var feed: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(vm.echoes.prefix(3))) { echo in echoCard(echo) }
            if let theme = vm.profile?.recurringThemes.first, theme.count >= 3 { themeCard(theme) }
            ForEach(Array(vm.callbacks.filter { $0.isSurfaceable }.prefix(2))) { cb in callbackCard(cb) }
            if let memory = vm.onThisDay { onThisDayCard(memory.entry, label: memory.label) }
            if let r = vm.river, r.entryCount > 0 { weekRiverCard(r) }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Cards

    private func echoCard(_ echo: Echo) -> some View {
        memoryCard(tag: "\(echo.type.displayLabel) · \(EchoesViewModel.agoLabel(echo.sourceEntryCreatedAt))",
                   tagBG: AppTheme.rose.opacity(0.2), tagFG: AppTheme.terracottaDeep, tint: AppTheme.rose2) {
            VStack(alignment: .leading, spacing: 8) {
                Text(echo.line ?? "You said something worth keeping.")
                    .font(AppTheme.editorialDisplay(size: 20)).foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("“\(echo.quote)”")
                    .font(AppTheme.editorialBody(size: 16)).italic()
                    .foregroundStyle(AppTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func themeCard(_ theme: MemoryProfile.Theme) -> some View {
        memoryCard(tag: "about you · recurring", tagBG: AppTheme.lav.opacity(0.35),
                   tagFG: AppTheme.ink, tint: AppTheme.lav) {
            VStack(alignment: .leading, spacing: 10) {
                Text("“\(theme.word.capitalized)” keeps returning.")
                    .font(AppTheme.editorialDisplay(size: 20)).foregroundStyle(AppTheme.ink)
                FlowLayout(spacing: 8) {
                    ForEach((vm.profile?.recurringThemes ?? []).prefix(5).map { $0 }) { t in
                        Text("\(t.word) ×\(t.count)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(AppTheme.cream.opacity(0.8))
                            .foregroundStyle(AppTheme.ink)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private func callbackCard(_ cb: PatternCallback) -> some View {
        memoryCard(tag: "pattern · \(cb.archetype.displayLabel)", tagBG: AppTheme.mint.opacity(0.45),
                   tagFG: AppTheme.ink, tint: AppTheme.mint) {
            VStack(alignment: .leading, spacing: 6) {
                Text(cb.callbackLine)
                    .font(AppTheme.editorialDisplay(size: 19)).foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Not a diagnosis. Just a shape your words keep making.")
                    .font(AppTheme.mono(size: 10)).foregroundStyle(AppTheme.inkSoft)
            }
        }
    }

    private func onThisDayCard(_ entry: JournalEntry, label: String) -> some View {
        memoryCard(tag: "on this day · \(label)", tagBG: AppTheme.blue.opacity(0.35),
                   tagFG: AppTheme.ink, tint: AppTheme.blue) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(label.capitalized), today.")
                    .font(AppTheme.editorialDisplay(size: 20)).foregroundStyle(AppTheme.ink)
                Text("“\(String(entry.content.prefix(140)))\(entry.content.count > 140 ? "…" : "")”")
                    .font(AppTheme.editorialBody(size: 15)).italic()
                    .foregroundStyle(AppTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func weekRiverCard(_ river: River) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LAST WEEK · AS A RIVER")
                .font(AppTheme.mono(size: 9)).tracking(1.5).foregroundStyle(AppTheme.cream.opacity(0.7))
            Text(river.oneLineTruth)
                .font(AppTheme.editorialDisplay(size: 20)).foregroundStyle(AppTheme.cream)
                .fixedSize(horizontal: false, vertical: true)
            Text(river.countLabel)
                .font(AppTheme.editorialBody(size: 13)).foregroundStyle(AppTheme.cream.opacity(0.85))
            RiverShape(segments: river.segments)
                .frame(height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.ink)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    // MARK: - Building blocks

    private func memoryCard<Content: View>(
        tag: String, tagBG: Color, tagFG: Color, tint: Color,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tag.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(1.2)
                .foregroundStyle(tagFG)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(tagBG).clipShape(Capsule())
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            LinearGradient(colors: [AppTheme.cream, tint.opacity(0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: AppTheme.cardShadow, radius: 14, x: 0, y: 8)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("✦").font(.system(size: 40)).foregroundStyle(AppTheme.terracotta)
            Text("No echoes yet.")
                .font(AppTheme.editorialDisplay(size: 20)).foregroundStyle(AppTheme.ink)
            Text("Write a few entries and ninety will start surfacing what keeps returning — quietly, here.")
                .font(AppTheme.editorialBody(size: 14)).multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.inkSoft)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60).padding(.horizontal, 28)
    }

    // MARK: - Memory popover

    /// A tapped memory bubble opens into this: a thoughtful, self-dismissing card.
    struct MemoryPopover: Identifiable {
        let id = UUID()
        let glyph: String
        let title: String
        let body: String
        let tint: Color
    }

    private func open(_ memory: MemoryPopover) {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { activeMemory = memory }
    }

    private func close() {
        withAnimation(.easeInOut(duration: 0.22)) { activeMemory = nil }
    }

    private func memoryPopover(_ m: MemoryPopover) -> some View {
        ZStack {
            // Dimmed, tappable scrim — tap anywhere outside to dismiss.
            AppTheme.ink.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { close() }
                .transition(.opacity)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Text(m.glyph).font(.system(size: 34))
                    Spacer()
                    Button { close() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppTheme.inkSoft)
                            .frame(width: 30, height: 30)
                            .background(AppTheme.paperWarm)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }

                Text(m.title)
                    .font(AppTheme.editorialDisplay(size: 24))
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(m.body)
                    .font(AppTheme.editorialBody(size: 15))
                    .foregroundStyle(AppTheme.inkSoft)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                // Slim auto-dismiss progress (depletes over 5s).
                GeometryReader { geo in
                    Capsule()
                        .fill(AppTheme.inkSoft.opacity(0.15))
                        .frame(height: 3)
                        .overlay(alignment: .leading) {
                            Capsule().fill(m.tint)
                                .frame(width: geo.size.width * popoverProgress, height: 3)
                        }
                }
                .frame(height: 3)
                .padding(.top, 6)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [AppTheme.cream, m.tint.opacity(0.5)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: AppTheme.cardShadow, radius: 28, x: 0, y: 16)
            .padding(.horizontal, 28)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
            .onAppear {
                popoverProgress = 1
                withAnimation(.linear(duration: 5)) { popoverProgress = 0 }
            }
        }
    }
}
