//
//  MoodBlobView.swift
//  DailyJournal
//
//  A compact, journal-free daily mood logger for the Home screen. Translated
//  from the interactive "mood blob" mockup: drag the slider to shift the band,
//  colour, prompt and motion of a living blob, then tap to log the day's mood.
//
//  The 7-band mockup is mapped onto the app's 5-point Mood scale so it flows
//  straight into the existing Patterns mood analytics.
//

import SwiftUI

// MARK: - RGB helper (0–255 channels, interpolation, SwiftUI Color)
private struct RGB {
    let r, g, b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }

    func lerp(to o: RGB, _ t: Double) -> RGB {
        RGB(r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t)
    }
    func color(opacity: Double = 1) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: opacity)
    }
}

private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

// MARK: - Mood band (visual + copy for each of the 5 moods)
private struct MoodBand {
    let mood: Mood
    let base: RGB    // blob fill
    let glow: RGB    // orb highlight
    let tint: RGB    // card background
    let prompt: String
    let label: String
}

// Ordered unpleasant → pleasant to match the slider (left = low, right = high).
private let moodBands: [MoodBand] = [
    MoodBand(mood: .terrible, base: RGB(122, 59, 59),  glow: RGB(188, 116, 116), tint: RGB(52, 28, 28),
             prompt: "Just dump it — no fixing.",       label: "very unpleasant"),
    MoodBand(mood: .bad,      base: RGB(107, 91, 138), glow: RGB(152, 136, 188), tint: RGB(44, 38, 58),
             prompt: "What's sitting on your chest?",    label: "unpleasant"),
    MoodBand(mood: .neutral,  base: RGB(139, 139, 122), glow: RGB(194, 194, 172), tint: RGB(54, 54, 46),
             prompt: "How are you, actually?",           label: "neutral"),
    MoodBand(mood: .good,     base: RGB(92, 111, 74),  glow: RGB(154, 174, 122), tint: RGB(38, 46, 30),
             prompt: "One small thing that went right?", label: "pleasant"),
    MoodBand(mood: .amazing,  base: RGB(201, 151, 58), glow: RGB(250, 205, 110), tint: RGB(72, 52, 18),
             prompt: "You're flying. Capture this.",     label: "very pleasant"),
]

// Deterministic orb seeds (no per-frame randomness, no heavy literal math —
// precomputed so the type-checker stays fast).
private struct Orb { let angle: Double; let radius: Double; let speed: Double; let size: Double; let light: Double }
private let orbs: [Orb] = [
    Orb(angle: 0.00, radius: 18, speed: 0.35, size: 30, light: 0.0),
    Orb(angle: 1.27, radius: 31, speed: 0.55, size: 47, light: 0.3),
    Orb(angle: 2.54, radius: 44, speed: 0.75, size: 40, light: 0.6),
    Orb(angle: 3.81, radius: 57, speed: 0.45, size: 33, light: 0.9),
    Orb(angle: 5.08, radius: 30, speed: 0.65, size: 50, light: 0.2),
]

struct MoodBlobView: View {
    /// Pre-existing log for today (so we can reflect "already logged" state).
    let existingMood: Mood?
    /// Called when the user commits a mood.
    let onLog: (Mood) -> Void

    @State private var value: Double = 0.5      // 0 (heavy) … 1 (light)
    @State private var interacted = false
    @State private var startDate = Date()
    /// Once today's mood is logged we collapse to a compact summary row. Tapping
    /// "Change" expands the full slider again.
    @State private var expanded = false
    /// A short affirmation shown briefly right after logging.
    @State private var celebration: String?
    @State private var celebrate = false   // drives the little bounce

    private struct Blend { let band: MoodBand; let base: RGB; let glow: RGB; let tint: RGB; let flow: Double }

    private var blend: Blend {
        let p = value * Double(moodBands.count - 1)
        let i = min(moodBands.count - 2, max(0, Int(p)))
        let t = p - Double(i)
        let a = moodBands[i], b = moodBands[i + 1]
        return Blend(band: t < 0.5 ? a : b,
                     base: a.base.lerp(to: b.base, t),
                     glow: a.glow.lerp(to: b.glow, t),
                     tint: a.tint.lerp(to: b.tint, t),
                     flow: lerp(0.25, 1.4, value))
    }

    private var selectedMood: Mood {
        let idx = Int((value * Double(moodBands.count - 1)).rounded())
        return moodBands[min(moodBands.count - 1, max(0, idx))].mood
    }

    var body: some View {
        // Already logged today and not actively changing → compact summary.
        if let logged = existingMood, !expanded {
            compactLoggedView(logged)
        } else {
            fullControl
        }
    }

    // MARK: - Compact "already logged" summary
    private func compactLoggedView(_ mood: Mood) -> some View {
        HStack(spacing: 12) {
            Text(mood.faceEmoji)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Logged for today")
                    .font(AppTheme.mono(size: 10))
                    .tracking(1)
                    .foregroundStyle(AppTheme.inkSoft)
                Text(mood.scaleLabel)
                    .font(AppTheme.editorialBody(size: 16))
                    .foregroundStyle(AppTheme.ink)
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { expanded = true }
            } label: {
                Text("Change")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.terracotta)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .overlay(Capsule().stroke(AppTheme.terracotta.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(AppTheme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Full interactive control
    private var fullControl: some View {
        let b = blend

        return VStack(spacing: 10) {
            Text(b.band.label.uppercased())
                .font(AppTheme.mono(size: 10))
                .tracking(1.5)
                .foregroundStyle(b.glow.color())

            Text(b.band.prompt)
                .font(AppTheme.editorialBody(size: 16))
                .foregroundStyle(RGB(245, 242, 232).color())
                .multilineTextAlignment(.center)
                .frame(minHeight: 44)
                .animation(.easeInOut(duration: 0.3), value: b.band.prompt)

            blob(base: b.base, glow: b.glow, flow: b.flow)
                .frame(width: 150, height: 150)
                .scaleEffect(celebrate ? 1.08 : 1.0)
                .overlay {
                    if celebrate, let celebration {
                        Text(celebration)
                            .font(AppTheme.editorialDisplay(size: 17))
                            .foregroundStyle(RGB(245, 242, 232).color())
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10)
                            .shadow(radius: 6)
                            .transition(.opacity.combined(with: .scale))
                    }
                }

            Slider(value: $value, in: 0...1) { editing in
                if editing { interacted = true }
            }
            .tint(b.glow.color())

            HStack {
                Text("unpleasant")
                Spacer()
                Text("neutral")
                Spacer()
                Text("pleasant")
            }
            .font(AppTheme.mono(size: 9))
            .foregroundStyle(RGB(180, 178, 169).color())

            Button {
                onLog(selectedMood)
                interacted = false
                // A little moment of delight: haptic + bounce + affirmation.
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                celebration = affirmation(for: selectedMood)
                withAnimation(.spring(response: 0.32, dampingFraction: 0.5)) { celebrate = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        celebrate = false
                        expanded = false   // collapse to the compact summary
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: existingMood == nil ? "checkmark.circle" : "arrow.triangle.2.circlepath")
                        .font(.system(size: 13, weight: .medium))
                    Text(buttonTitle)
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(b.tint.color())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppTheme.cream)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .opacity(interacted || existingMood != nil ? 1 : 0.55)
            .padding(.top, 4)
        }
        .padding(16)
        .background(b.tint.color())
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .animation(.easeOut(duration: 0.5), value: value)
        .onAppear {
            startDate = Date()
            // Pre-position the slider at an already-logged mood, if any.
            if let existingMood,
               let idx = moodBands.firstIndex(where: { $0.mood == existingMood }) {
                value = Double(idx) / Double(moodBands.count - 1)
            }
        }
    }

    private var buttonTitle: String {
        existingMood == nil ? "Log today's mood" : "Update today's mood"
    }

    /// A gentle, non-judgemental one-liner shown right after logging. Never
    /// cheerful at someone having a hard day — meets the mood where it is.
    private func affirmation(for mood: Mood) -> String {
        switch mood {
        case .amazing:  return "Soak it in."
        case .good:     return "Noted. Nice one."
        case .neutral:  return "Logged. That counts."
        case .bad:      return "Thanks for being honest."
        case .terrible: return "You showed up. That's enough."
        }
    }

    // MARK: - Animated blob
    private func blob(base: RGB, glow: RGB, flow: Double) -> some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = startDate.distance(to: timeline.date)
                let cx = size.width / 2, cy = size.height / 2
                let breath = 1 + 0.045 * sin(t * .pi * 2 / 4)
                let R = min(size.width, size.height) * 0.34 * breath

                // Wobbling blob outline
                var path = Path()
                let pts = 48
                for i in 0...pts {
                    let a = Double(i) / Double(pts) * .pi * 2
                    let wob = 1 + 0.05 * sin(a * 3 + t * 0.8) + 0.04 * sin(a * 5 - t * 0.6)
                    let x = cx + cos(a) * R * wob
                    let y = cy + sin(a) * R * wob
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                path.closeSubpath()

                ctx.clip(to: path)

                // Base fill
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base.color()))

                // Orbiting glow orbs
                for orb in orbs {
                    let ang = orb.angle + t * 0.4 * orb.speed * (0.4 + flow)
                    let ox = cx + cos(ang) * orb.radius
                    let oy = cy + sin(ang * 1.3) * orb.radius
                    let oc = base.lerp(to: glow, 0.4 + 0.6 * orb.light)
                    let rect = CGRect(x: ox - orb.size, y: oy - orb.size,
                                      width: orb.size * 2, height: orb.size * 2)
                    ctx.fill(
                        Path(ellipseIn: rect),
                        with: .radialGradient(
                            Gradient(colors: [oc.color(opacity: 0.9), oc.color(opacity: 0)]),
                            center: CGPoint(x: ox, y: oy),
                            startRadius: 0,
                            endRadius: orb.size
                        )
                    )
                }

                // Sheen
                let sheenCenter = CGPoint(x: cx - 14, y: cy - 18)
                ctx.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .radialGradient(
                        Gradient(colors: [glow.color(opacity: 0.35), glow.color(opacity: 0)]),
                        center: sheenCenter,
                        startRadius: 3,
                        endRadius: min(size.width, size.height) * 0.55
                    )
                )
            }
        }
    }
}
