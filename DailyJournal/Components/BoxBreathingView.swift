//
//  BoxBreathingView.swift
//  DailyJournal
//
//  A skippable 4-4-4-4 box-breathing pause used by the "breathing" template
//  step kind (`TemplateStep.Kind.breathing`, see `JournalTemplate.swift`).
//  Standalone and stateful — it owns its own clock and emits two outcomes to
//  its caller: `onComplete` when every cycle finishes, `onSkip` when the
//  person taps out early. Neither outcome is ever woven into an entry (see
//  `AIService+Template.swift`'s weave prompt, rule 10) — this is a pause, not
//  something to write about.
//
//  Every phase animates: a dot traces one side of a square per phase (top =
//  inhale, right = hold, bottom = exhale, left = hold), a center shape
//  breathes in and out with it, and the label/countdown cross-fade. Driven by
//  a repeating timer measured against an absolute start `Date` (not an
//  accumulating counter), so a dropped tick or a frame hitch never drifts the
//  phase boundaries — each tick recomputes phase purely from elapsed time.
//

import SwiftUI
import UIKit

struct BoxBreathingView: View {
    /// How many times around the inhale/hold/exhale/hold square.
    var cycles: Int = 4
    /// Fires once, when all `cycles` finish on their own.
    var onComplete: () -> Void = {}
    /// Fires once, the moment the person taps "Skip" — whether that happens
    /// before starting, mid lead-in, or mid-cycle.
    var onSkip: () -> Void = {}

    private enum Stage: Equatable {
        case idle
        case leadIn
        case breathing
        case finished
    }

    private static let phaseDuration: TimeInterval = 4
    private static let leadInDuration: TimeInterval = 3
    private static let phaseLabels = ["Breathe in", "Hold", "Breathe out", "Hold"]

    @State private var stage: Stage = .idle
    @State private var stageStart = Date()
    @State private var now = Date()
    /// Set whenever the stage clock should stop advancing (backgrounded) —
    /// resumed by shifting `stageStart` forward by however long it was paused,
    /// so elapsed time inside the current stage is unaffected.
    @State private var pausedAt: Date?
    @State private var cyclesDone = 0
    /// (cycleIndex, phaseIndex) at the last haptic, so a 30fps timer tick
    /// doesn't re-fire the same phase's haptic repeatedly.
    @State private var lastHapticKey: (Int, Int) = (-1, -1)
    @State private var didComplete = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private let timer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                square
                if stage == .breathing {
                    centerShape
                    if !reduceMotion {
                        travelingDot
                    }
                }
                if stage == .leadIn {
                    Text("\(leadInCountdown)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                        .transition(.opacity)
                        .id(leadInCountdown)
                }
                if stage == .finished {
                    Text("Nice.")
                        .font(AppTheme.editorialDisplay(size: 20))
                        .foregroundStyle(AppTheme.ink)
                        .transition(.opacity)
                }
            }
            .frame(width: 180, height: 180)

            statusLine

            cycleDots

            controls
        }
        .padding(.vertical, 8)
        .onReceive(timer) { tick in
            now = tick
            advanceIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            guard stage == .leadIn || stage == .breathing else { return }
            if phase != .active, pausedAt == nil {
                pausedAt = Date()
            } else if phase == .active, let paused = pausedAt {
                let gap = Date().timeIntervalSince(paused)
                stageStart = stageStart.addingTimeInterval(gap)
                pausedAt = nil
            }
        }
    }

    // MARK: - Timing

    /// Elapsed time in the current stage, frozen while backgrounded.
    private var elapsed: TimeInterval {
        let reference = pausedAt ?? now
        return max(0, reference.timeIntervalSince(stageStart))
    }

    private var leadInCountdown: Int {
        max(1, Int(ceil(Self.leadInDuration - elapsed)))
    }

    /// 0 = inhale (top), 1 = hold (right), 2 = exhale (bottom), 3 = hold (left).
    private var phaseIndex: Int {
        let cycleElapsed = elapsed.truncatingRemainder(dividingBy: Self.phaseDuration * 4)
        return min(3, Int(cycleElapsed / Self.phaseDuration))
    }

    private var cycleIndex: Int {
        Int(elapsed / (Self.phaseDuration * 4))
    }

    /// 0...1 progress through the current phase.
    private var phaseFraction: Double {
        let cycleElapsed = elapsed.truncatingRemainder(dividingBy: Self.phaseDuration * 4)
        let intoPhase = cycleElapsed - Double(phaseIndex) * Self.phaseDuration
        return min(1, max(0, intoPhase / Self.phaseDuration))
    }

    /// 0...1 progress around the whole square for this cycle — what both the
    /// trimmed outline and the traveling dot are positioned from.
    private var cycleProgress: Double {
        (Double(phaseIndex) + phaseFraction) / 4
    }

    private func advanceIfNeeded() {
        guard pausedAt == nil else { return }
        switch stage {
        case .idle, .finished:
            return
        case .leadIn:
            if elapsed >= Self.leadInDuration {
                stage = .breathing
                stageStart = now
                cyclesDone = 0
                lastHapticKey = (-1, -1)
            }
        case .breathing:
            if cycleIndex >= cycles {
                stage = .finished
                if !didComplete {
                    didComplete = true
                    onComplete()
                }
                return
            }
            cyclesDone = cycleIndex
            let key = (cycleIndex, phaseIndex)
            if key != lastHapticKey {
                lastHapticKey = key
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    // MARK: - Square outline + fill

    /// A plain square, traced clockwise from the top-left corner — top edge,
    /// right edge, bottom edge, left edge — so `trim(from:to:)` and
    /// `pointOnPerimeter` below walk the same path in the same order the
    /// phases do (inhale = top, hold = right, exhale = bottom, hold = left).
    private struct BoxTrace: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            return p
        }
    }

    private func pointOnPerimeter(_ progress: Double, in size: CGSize) -> CGPoint {
        let p = max(0, min(1, progress))
        let side = min(3, Int(p * 4))
        let local = p * 4 - Double(side)
        switch side {
        case 0: return CGPoint(x: local * size.width, y: 0)
        case 1: return CGPoint(x: size.width, y: local * size.height)
        case 2: return CGPoint(x: size.width - local * size.width, y: size.height)
        default: return CGPoint(x: 0, y: size.height - local * size.height)
        }
    }

    private var square: some View {
        ZStack {
            BoxTrace()
                .stroke(AppTheme.inkSoft.opacity(0.18), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
            if stage == .breathing || stage == .finished {
                BoxTrace()
                    .trim(from: 0, to: stage == .finished ? 1 : cycleProgress)
                    .stroke(accentTint.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
            }
        }
        .frame(width: 180, height: 180)
    }

    /// Falls back to the app's lavender accent — this view has no template
    /// reference, just `AppTheme`, same as every other Component here.
    private var accentTint: Color { AppTheme.lav }

    private var travelingDot: some View {
        GeometryReader { geo in
            let point = pointOnPerimeter(cycleProgress, in: geo.size)
            Circle()
                .fill(accentTint)
                .frame(width: 14, height: 14)
                .shadow(color: accentTint.opacity(0.6), radius: 6)
                .position(point)
        }
        .frame(width: 180, height: 180)
    }

    /// The breathing shape in the center. Under Reduce Motion this stays a
    /// fixed size and only changes opacity — no scaling, no travel.
    private var centerShape: some View {
        let scale: CGFloat = {
            switch phaseIndex {
            case 0: return 0.6 + 0.4 * phaseFraction
            case 1: return 1.0 + 0.03 * sin(phaseFraction * 2 * .pi)
            case 2: return 1.0 - 0.4 * phaseFraction
            default: return 0.6 + 0.03 * sin(phaseFraction * 2 * .pi)
            }
        }()
        let opacity: Double = {
            switch phaseIndex {
            case 0: return 0.55 + 0.35 * phaseFraction
            case 1: return 0.9
            case 2: return 0.9 - 0.35 * phaseFraction
            default: return 0.55
            }
        }()
        return Circle()
            .fill(accentTint.opacity(0.25))
            .frame(width: 92, height: 92)
            .scaleEffect(reduceMotion ? 1 : scale)
            .opacity(reduceMotion ? opacity : 1)
    }

    // MARK: - Status line

    private var statusLine: some View {
        Group {
            switch stage {
            case .idle:
                Text("A minute of box breathing, if you'd like it.")
                    .font(AppTheme.editorialBody(size: 13.5))
                    .foregroundStyle(AppTheme.inkSoft)
                    .multilineTextAlignment(.center)
            case .leadIn:
                Text("Starting\u{2026}")
                    .font(AppTheme.mono(size: 11))
                    .tracking(1.5)
                    .foregroundStyle(AppTheme.inkSoft)
            case .breathing:
                VStack(spacing: 2) {
                    Text(Self.phaseLabels[phaseIndex])
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                        .transition(.opacity)
                        .id(phaseIndex)
                    Text("\(secondsLeftInPhase)")
                        .font(AppTheme.mono(size: 11))
                        .foregroundStyle(AppTheme.inkSoft)
                }
            case .finished:
                Text("That's \(cycles) time\(cycles == 1 ? "" : "s") around.")
                    .font(AppTheme.editorialBody(size: 13))
                    .foregroundStyle(AppTheme.inkSoft)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: stage)
        .frame(height: 36)
    }

    private var secondsLeftInPhase: Int {
        max(1, Int(ceil(Self.phaseDuration * (1 - phaseFraction))))
    }

    // MARK: - Cycle dots

    @ViewBuilder
    private var cycleDots: some View {
        if stage == .breathing || stage == .finished {
            HStack(spacing: 6) {
                ForEach(0..<cycles, id: \.self) { i in
                    Circle()
                        .fill(i < (stage == .finished ? cycles : cyclesDone) ? accentTint : AppTheme.inkSoft.opacity(0.2))
                        .frame(width: 6, height: 6)
                }
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 10) {
            switch stage {
            case .idle:
                Button {
                    stage = .leadIn
                    stageStart = now
                } label: {
                    Text("Start")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.cream)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(accentTint)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                skipButton
            case .leadIn, .breathing:
                skipButton
            case .finished:
                EmptyView()
            }
        }
    }

    private var skipButton: some View {
        Button {
            onSkip()
        } label: {
            Text("Skip")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.inkSoft)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Skip breathing")
    }
}
