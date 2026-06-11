//
//  AppTheme.swift
//  DailyJournal
//
//  Pastel "cute, but meaningful" design system.
//
//  All the original property names + typography function signatures are kept
//  so existing screens keep compiling. Only the values changed (editorial
//  terracotta → soft pastel) and a River colour vocabulary was added.
//

import SwiftUI

// MARK: - Color Hex Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red:     Double(r) / 255,
            green:   Double(g) / 255,
            blue:    Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - App Theme
struct AppTheme {

    // ── Pastel palette ─────────────────────────────────────────────────
    // Soft, screenshot-friendly tones. Backgrounds are warm-white; "ink" is a
    // deep aubergine rather than near-black so dark surfaces still feel gentle.
    static let paper          = Color(hex: "FFF8F2")   // warm app background
    static let paperWarm      = Color(hex: "FBEFE9")   // slightly deeper surface
    static let cream          = Color(hex: "FFFDFB")   // card / on-dark text
    static let ink            = Color(hex: "2B2440")   // deep aubergine (headlines / dark cards)
    static let inkSoft        = Color(hex: "766F84")   // muted lavender-grey (secondary text)

    // Accents — "terracotta" name kept for back-compat but now a soft rose.
    static let terracotta     = Color(hex: "F58BA6")   // primary rose
    static let terracottaDeep = Color(hex: "E0567C")   // deeper rose (timer urgency etc.)

    // Pastel companions
    static let rose           = Color(hex: "FFB8C6")
    static let rose2          = Color(hex: "FFE1E8")
    static let peach          = Color(hex: "FFD7AD")
    static let mint           = Color(hex: "A9F1D3")
    static let blue           = Color(hex: "BDE7FF")
    static let lav            = Color(hex: "D8CCFF")
    static let sun            = Color(hex: "FFE77A")

    // Legacy semantic names mapped onto the pastel set.
    static let moss           = Color(hex: "8FD9B6")   // calm / content
    static let dusk           = Color(hex: "B7A6E8")   // sad / heavy (soft lavender)
    static let gold           = Color(hex: "FFCF6B")   // joy / excitement
    static let slate          = Color(hex: "A9A2B8")   // neutral

    // ── Semantic aliases ───────────────────────────────────────────────
    static let primary      = terracotta
    static let background   = paper
    static let surface      = cream
    static let textPrimary  = ink
    static let textSecond   = inkSoft

    // ── Mood → accent color ────────────────────────────────────────────
    static func moodColor(_ mood: Mood?) -> Color {
        guard let mood else { return paperWarm }
        switch mood {
        case .amazing:  return gold
        case .good:     return moss
        case .neutral:  return slate
        case .bad:      return dusk
        case .terrible: return Color(hex: "9C86C9")
        }
    }

    // ── Sentiment string → accent color ───────────────────────────────
    static func sentimentColor(_ label: String?) -> Color {
        guard let s = label?.lowercased() else { return slate }
        switch true {
        case s.contains("anxi"), s.contains("stress"),
             s.contains("worry"), s.contains("dread"), s.contains("fear"):
            return rose
        case s.contains("excit"), s.contains("happy"),
             s.contains("joy"),   s.contains("elat"),  s.contains("thrill"):
            return gold
        case s.contains("sad"),  s.contains("grief"),
             s.contains("mourn"), s.contains("depress"), s.contains("low"):
            return dusk
        case s.contains("calm"), s.contains("peace"),
             s.contains("content"), s.contains("gratit"), s.contains("serene"):
            return mint
        default:
            return slate
        }
    }

    // ── River visual vocabulary ─────────────────────────────────────────
    //
    // The river renderer maps derived signals (valence/activation/clarity) onto
    // colour so a user can learn to "read" their own week. Deterministic — the
    // model proposes a visual_spec, but the actual colours come from here so
    // every river is recognisably ninety.

    /// Valence -3…+3 → a hue from cool/heavy to warm/bright.
    static func valenceColor(_ valence: Int) -> Color {
        switch valence {
        case ...(-2): return Color(hex: "9C86C9")   // cold lavender
        case -1:      return dusk
        case 0:       return blue
        case 1:       return mint
        case 2:       return peach
        default:      return sun                     // +3 bright
        }
    }

    /// A river-marker glyph + tint for the cute-but-semantic vocabulary.
    enum RiverMarker: String {
        case water    // a normal entry day
        case mist     // a quiet / no-entry day
        case bridge   // return after a gap
        case glimmer  // softer self-talk / relief
        case stone    // recurring theme
        case rapid    // pressure / intensity
        case pool     // emotionally heavy / dense entry
        case fork     // ambivalence

        var glyph: String {
            switch self {
            case .water:   return "💧"
            case .mist:    return "🌫️"
            case .bridge:  return "🌉"
            case .glimmer: return "✨"
            case .stone:   return "🪨"
            case .rapid:   return "🌊"
            case .pool:    return "🌀"
            case .fork:    return "🜊"
            }
        }

        var tint: Color {
            switch self {
            case .water:   return AppTheme.blue
            case .mist:    return AppTheme.paperWarm
            case .bridge:  return AppTheme.lav
            case .glimmer: return AppTheme.sun
            case .stone:   return AppTheme.slate
            case .rapid:   return AppTheme.rose
            case .pool:    return AppTheme.dusk
            case .fork:    return AppTheme.peach
            }
        }
    }

    // ── Typography helpers ─────────────────────────────────────────────
    // Display switched from serif → rounded to match the soft, cute direction.
    // Signatures are unchanged so every existing call site keeps working.
    static func editorialDisplay(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func editorialBody(size: CGFloat = 17) -> Font {
        .system(size: size, weight: .regular, design: .rounded)
    }

    static func mono(size: CGFloat = 12) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }

    // ── Soft shadow helper ──────────────────────────────────────────────
    static let cardShadow = Color(hex: "392A4C").opacity(0.10)
}

// MARK: - Soft card modifier
extension View {
    /// A reusable pastel card surface: translucent white, rounded, soft shadow.
    func softCard(cornerRadius: CGFloat = 24, padding: CGFloat = 20) -> some View {
        self
            .padding(padding)
            .background(AppTheme.cream.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: AppTheme.cardShadow, radius: 18, x: 0, y: 12)
    }
}
