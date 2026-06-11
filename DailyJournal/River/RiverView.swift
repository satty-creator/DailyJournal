//
//  RiverView.swift
//  DailyJournal
//
//  The River tab. A flowing, colour-coded artifact built from the user's own
//  words — "here is the shape your words made." Cute on the surface, semantic
//  underneath: every glyph (mist / bridge / glimmer / stone / rapid) means
//  something specific.
//

import SwiftUI

@MainActor
final class RiverViewModel: ObservableObject {
    @Published var river: River?
    @Published var window: RiverWindow = .week
    @Published var isLoading = true

    private let service = RiverService()
    private let journal = JournalService()
    let userId: String

    init(userId: String) { self.userId = userId }

    func load() async {
        isLoading = true
        // Backfill local marks for any past entries first (cheap, offline-safe),
        // so existing users see a river immediately rather than an empty one.
        if let entries = try? await journal.fetchAllEntries(for: userId) {
            await service.backfillLocalMarks(from: entries, userId: userId)
        }
        river = await service.buildRiver(window: window, for: userId)
        isLoading = false
    }

    func switchWindow(_ w: RiverWindow) async {
        window = w
        isLoading = true
        river = await service.buildRiver(window: w, for: userId)
        isLoading = false
    }
}

// MARK: - River View
struct RiverView: View {
    @StateObject private var vm: RiverViewModel
    @State private var activeTip: String?
    @State private var showShare = false

    init(userId: String) {
        _vm = StateObject(wrappedValue: RiverViewModel(userId: userId))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                pastelBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        windowPicker

                        if vm.isLoading && vm.river == nil {
                            ProgressView().tint(AppTheme.terracotta)
                                .frame(maxWidth: .infinity).padding(.top, 60)
                        } else if let river = vm.river {
                            if river.entryCount == 0 {
                                emptyState
                            } else {
                                // River is the PICTURE — just the shape, one
                                // private read, and the share action. The words
                                // (recurring themes, returns, patterns) live in Echoes.
                                riverCanvas(river)
                                if river.isSparse { sparseNote(river) }
                                interpretationCard(river)
                                shareButton
                                openNoticedLink
                            }
                        }
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
                .refreshable { await vm.load() }

                if let tip = activeTip { tooltipOverlay(tip) }
            }
            .navigationBarHidden(true)
            .task { if vm.river == nil { await vm.load() } }
            .sheet(isPresented: $showShare) {
                if let river = vm.river { ShareRiverView(river: river) }
            }
        }
    }

    // MARK: - Background
    private var pastelBackground: some View {
        LinearGradient(
            colors: [AppTheme.paper, AppTheme.rose2.opacity(0.4), AppTheme.blue.opacity(0.3)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    // MARK: - Header
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("YOUR RIVER")
                .font(AppTheme.mono(size: 11)).tracking(2)
                .foregroundStyle(AppTheme.inkSoft)
            Text(vm.river?.privateTitle ?? vm.window.label)
                .font(AppTheme.editorialDisplay(size: 30))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let river = vm.river, river.entryCount > 0 {
                Text(river.countLabel)
                    .font(AppTheme.editorialBody(size: 14))
                    .foregroundStyle(AppTheme.inkSoft)
            }
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Window picker
    private var windowPicker: some View {
        HStack(spacing: 8) {
            ForEach(RiverWindow.allCases) { w in
                Button {
                    Task { await vm.switchWindow(w) }
                } label: {
                    Text(w.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(vm.window == w ? AppTheme.cream : AppTheme.inkSoft)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(vm.window == w ? AppTheme.ink : AppTheme.cream.opacity(0.7))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - The river canvas
    private func riverCanvas(_ river: River) -> some View {
        VStack(spacing: 14) {
            RiverShape(segments: river.segments)
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(colors: [AppTheme.cream, AppTheme.blue.opacity(0.18)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            // Day pills with tappable markers.
            HStack(spacing: 5) {
                ForEach(river.segments) { seg in
                    Button {
                        withAnimation(.spring(response: 0.3)) { activeTip = seg.tooltip }
                    } label: {
                        VStack(spacing: 3) {
                            Text(seg.marker.glyph).font(.system(size: 13))
                            Text(seg.date.formatted(.dateTime.weekday(.narrow)))
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.inkSoft)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(seg.marker.tint.opacity(seg.hasEntry ? 0.55 : 0.25))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .softCard(cornerRadius: 32, padding: 16)
    }

    // MARK: - Cards
    private func sparseNote(_ river: River) -> some View {
        labeledCard("just getting started") {
            Text("Write \(river.window.unlockThreshold)+ times in this window for a fuller river. For now, here's the first shape.")
                .font(AppTheme.editorialBody(size: 14)).foregroundStyle(AppTheme.inkSoft)
        }
    }

    // A soft pointer to the words-surface, keeping River purely visual.
    private var openNoticedLink: some View {
        HStack(spacing: 8) {
            Text("✦").font(.system(size: 14)).foregroundStyle(AppTheme.terracotta)
            Text("Want the words? Open **Echoes** to see what kept returning.")
                .font(AppTheme.editorialBody(size: 13)).foregroundStyle(AppTheme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(cornerRadius: 18, padding: 14)
    }

    private func interpretationCard(_ river: River) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(river.oneLineTruth)
                .font(AppTheme.editorialDisplay(size: 20)).foregroundStyle(AppTheme.cream)
            Text(river.privateInterpretation)
                .font(AppTheme.editorialBody(size: 14)).foregroundStyle(AppTheme.cream.opacity(0.85))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.ink)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var shareButton: some View {
        Button { showShare = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                Text("Make a share card").font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .foregroundStyle(AppTheme.ink)
            .frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(AppTheme.sun.opacity(0.85))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("💧").font(.system(size: 44))
            Text("Your river starts with one honest minute.")
                .font(AppTheme.editorialDisplay(size: 20)).multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.ink)
            Text("Write a few entries and watch your words become a current.")
                .font(AppTheme.editorialBody(size: 14)).multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.inkSoft)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60).padding(.horizontal, 20)
        .softCard(cornerRadius: 28)
    }

    // MARK: - Building blocks
    private func labeledCard<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label.uppercased())
                .font(AppTheme.mono(size: 9)).tracking(1.5).foregroundStyle(AppTheme.inkSoft)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(cornerRadius: 22)
    }

    private func tooltipOverlay(_ tip: String) -> some View {
        VStack {
            Spacer()
            Text(tip)
                .font(AppTheme.editorialBody(size: 14)).foregroundStyle(AppTheme.cream)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.ink)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 20).padding(.bottom, 24)
                .onTapGesture { withAnimation { activeTip = nil } }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - River shape (deterministic renderer)
//
// A flowing band whose vertical position follows valence and whose width
// follows intensity. Markers ride on top. Drawn with Canvas for crispness.
struct RiverShape: View {
    let segments: [RiverDaySegment]

    var body: some View {
        Canvas { ctx, size in
            guard segments.count > 1 else { return }
            let stepX = size.width / CGFloat(segments.count - 1)
            let midY = size.height / 2

            func y(for seg: RiverDaySegment) -> CGFloat {
                // valence +3 → high (up), -3 → low (down); mist days sit at mid.
                let v = CGFloat(seg.valence ?? 0)
                return midY - (v / 3.0) * (size.height * 0.30)
            }

            // Build a smooth path through the day points.
            var points: [CGPoint] = []
            for (i, seg) in segments.enumerated() {
                points.append(CGPoint(x: CGFloat(i) * stepX, y: y(for: seg)))
            }

            // Wide soft under-band.
            var band = Path()
            band.move(to: points[0])
            for i in 1..<points.count {
                let prev = points[i - 1], cur = points[i]
                let midX = (prev.x + cur.x) / 2
                band.addQuadCurve(to: cur, control: CGPoint(x: midX, y: prev.y))
            }
            ctx.stroke(band, with: .color(AppTheme.lav.opacity(0.55)),
                       style: StrokeStyle(lineWidth: 46, lineCap: .round, lineJoin: .round))
            ctx.stroke(band, with: .color(AppTheme.blue.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 26, lineCap: .round, lineJoin: .round))

            // Per-day coloured droplets sized by intensity.
            for (i, seg) in segments.enumerated() {
                let p = points[i]
                let r = seg.hasEntry ? (8 + CGFloat(seg.intensity) * 2.2) : 5
                let color: Color = seg.hasEntry
                    ? AppTheme.valenceColor(seg.valence ?? 0)
                    : AppTheme.paperWarm
                let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(color.opacity(seg.hasEntry ? 0.9 : 0.6)))
                if seg.hasEntry {
                    ctx.stroke(Path(ellipseIn: rect), with: .color(AppTheme.cream.opacity(0.9)),
                               style: StrokeStyle(lineWidth: 2))
                }
            }
        }
    }
}

// MARK: - Share card
//
// Privacy-safe by default: NO raw entry text, no sensitive theme labels. Sells
// "make your first current," not "I use a journaling app."
struct ShareRiverView: View {
    let river: River
    @Environment(\.dismiss) private var dismiss
    @State private var style: ShareStyle = .poetic

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.paper.ignoresSafeArea()
                VStack(spacing: 20) {
                    // Style toggle.
                    HStack(spacing: 8) {
                        ForEach(ShareStyle.allCases) { s in
                            Button { style = s } label: {
                                Text(s.label)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(style == s ? AppTheme.cream : AppTheme.inkSoft)
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .background(style == s ? AppTheme.ink : AppTheme.cream)
                                    .clipShape(Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 12)

                    shareCard
                        .padding(.horizontal, 20)

                    Text("Raw text is hidden by default. Sensitive themes stay private.")
                        .font(AppTheme.mono(size: 10)).foregroundStyle(AppTheme.inkSoft)
                        .multilineTextAlignment(.center).padding(.horizontal, 30)

                    if #available(iOS 16.0, *) {
                        ShareLink(item: river.share(style)) {
                            Text("Open share sheet")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.cream)
                                .frame(maxWidth: .infinity).padding(.vertical, 15)
                                .background(AppTheme.terracotta).clipShape(Capsule())
                        }
                        .padding(.horizontal, 20)
                    }
                    Spacer()
                }
            }
            .navigationTitle("Share your current")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(AppTheme.terracotta)
                }
            }
        }
    }

    private var shareCard: some View {
        ZStack {
            LinearGradient(colors: [AppTheme.rose2, AppTheme.blue.opacity(0.6), AppTheme.lav.opacity(0.5)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // Abstract river — no data labels.
            RiverShape(segments: river.segments)
                .opacity(0.9).padding(.top, 70)

            VStack(alignment: .leading, spacing: 10) {
                Text("my \(river.window == .month ? "month" : "current")")
                    .font(AppTheme.mono(size: 11)).tracking(2).foregroundStyle(AppTheme.ink.opacity(0.6))
                Text(river.share(style))
                    .font(AppTheme.editorialDisplay(size: 26)).foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                HStack(spacing: 6) {
                    Text("💧").font(.system(size: 14))
                    Text("made with ninety")
                        .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(AppTheme.ink)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 380)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: AppTheme.cardShadow, radius: 24, x: 0, y: 16)
    }
}
