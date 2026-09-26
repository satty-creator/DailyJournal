//
//  AppTheme.swift
//  DailyJournal
//
//  "Cute, but meaningful" design system — now themeable.
//
//  Originally this was a single fixed pastel palette. It is now backed by a
//  swappable `ThemePalette` (see ThemeManager) so the whole app can switch
//  between vibes (Bloom / Moon / Forest / Graphite / Sunset) à la the Spilr
//  prototype.
//
//  IMPORTANT — backwards compatibility:
//  Every original property name and typography signature is preserved. The only
//  change is that the colour properties are now computed `static var`s that read
//  from `AppTheme.active` (the currently selected palette) instead of being
//  fixed `let`s. The default palette (`.bloom`) reproduces the previous values
//  EXACTLY, so existing screens render identically until the user picks another
//  theme. No call-site changes are required anywhere.
//
//  See themesprd.md for the full feature spec.
//

import SwiftUI
import UIKit

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

    /// Linearly interpolates this color toward `other` by `amount` (0 = self, 1 = other).
    /// Manual replacement for `Color.mix(with:by:)`, which requires iOS 18.
    func blended(with other: Color, amount: Double) -> Color {
        let t = min(max(amount, 0), 1)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(other).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(
            .sRGB,
            red: r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue: b1 + (b2 - b1) * t,
            opacity: a1 + (a2 - a1) * t
        )
    }
}

// MARK: - Theme identity
//
// The set of user-selectable vibes. `rawValue` is the persistence key.
enum ThemeID: String, CaseIterable, Identifiable {
    case bloom      // soft + cute (default — the original Spilr palette)
    case moon       // night + calm (dark)
    case forest     // grounded
    case graphite   // data-first
    case sunset     // warm

    var id: String { rawValue }

    /// Short display name shown in the picker tile.
    var title: String {
        switch self {
        case .bloom:    return "Bloom"
        case .moon:     return "Moon"
        case .forest:   return "Forest"
        case .graphite: return "Graphite"
        case .sunset:   return "Sunset"
        }
    }

    /// One-line subtitle shown under the name.
    var subtitle: String {
        switch self {
        case .bloom:    return "soft + cute"
        case .moon:     return "night + calm"
        case .forest:   return "grounded"
        case .graphite: return "data-first"
        case .sunset:   return "warm"
        }
    }

    /// Whether this palette is a dark UI (drives `preferredColorScheme`).
    var colorScheme: ColorScheme {
        self == .moon ? .dark : .light
    }

    /// The three swatch colours used on the picker tile (bg, primary, accent).
    var swatch: [Color] {
        let p = palette
        return [p.paper, p.terracotta, p.sun]
    }

    /// The concrete palette for this theme.
    var palette: ThemePalette { ThemePalette.palette(for: self) }
}

// MARK: - Theme palette
//
// A full set of design tokens. Colours are stored as concrete `Color` values
// (parsed once at construction) so look-ups are cheap.
struct ThemePalette {
    // Surfaces & text
    let paper: Color        // app background
    let paperWarm: Color    // slightly deeper surface
    let cream: Color        // card surface / inverse (on-dark) text
    let ink: Color          // headlines, dark cards, primary text
    let inkSoft: Color      // secondary text

    // Primary accent
    let terracotta: Color
    let terracottaDeep: Color

    // Pastel companions
    let rose: Color
    let rose2: Color
    let peach: Color
    let mint: Color
    let blue: Color
    let lav: Color
    let sun: Color

    // Legacy semantic names (mood vocabulary)
    let moss: Color
    let dusk: Color
    let gold: Color
    let slate: Color

    // Cold/extreme lavender used at the bottom of the valence scale.
    let valenceCold: Color

    // Soft shadow tint
    let cardShadow: Color

    // ── Spilr Redesign additions (3a/3b/3c) ─────────────────────────────
    // A deeper, more saturated lavender than `lav` — used for small eyebrow
    // labels and marks that need to read against a light surface (`lav` itself
    // is too pale to hold as text). `lavWash` is the pale tinted-fill counterpart
    // (a wash, not a text colour). `inkRaised` is the lighter stop in the dark
    // hero card's ink→inkRaised gradient.
    let lavDeep: Color
    let lavWash: Color
    let inkRaised: Color

    // MARK: Palette factory
    static func palette(for id: ThemeID) -> ThemePalette {
        switch id {
        case .bloom:    return bloom
        case .moon:     return moon
        case .forest:   return forest
        case .graphite: return graphite
        case .sunset:   return sunset
        }
    }

    // ── Bloom (default) — reproduces the original Spilr palette EXACTLY ──
    static let bloom = ThemePalette(
        paper:          Color(hex: "FFF8F2"),
        paperWarm:      Color(hex: "FBEFE9"),
        cream:          Color(hex: "FFFDFB"),
        ink:            Color(hex: "2B2440"),
        inkSoft:        Color(hex: "766F84"),
        terracotta:     Color(hex: "F58BA6"),
        terracottaDeep: Color(hex: "E0567C"),
        rose:           Color(hex: "FFB8C6"),
        rose2:          Color(hex: "FFE1E8"),
        peach:          Color(hex: "FFD7AD"),
        mint:           Color(hex: "A9F1D3"),
        blue:           Color(hex: "BDE7FF"),
        lav:            Color(hex: "D8CCFF"),
        sun:            Color(hex: "FFE77A"),
        moss:           Color(hex: "8FD9B6"),
        dusk:           Color(hex: "B7A6E8"),
        gold:           Color(hex: "FFCF6B"),
        slate:          Color(hex: "A9A2B8"),
        valenceCold:    Color(hex: "9C86C9"),
        cardShadow:     Color(hex: "392A4C").opacity(0.10),
        lavDeep:        Color(hex: "8E79C9"),
        lavWash:        Color(hex: "EDE6FF"),
        inkRaised:      Color(hex: "4A3A63")
    )

    // ── Moon — night + calm (dark). The one dark palette. ────────────────
    // cream is a dark card surface here; ink flips to near-white text.
    static let moon = ThemePalette(
        paper:          Color(hex: "12132B"),
        paperWarm:      Color(hex: "211638"),
        cream:          Color(hex: "1E2240"),
        ink:            Color(hex: "F7F4FF"),
        inkSoft:        Color(hex: "B9ADC8"),
        terracotta:     Color(hex: "A78BFA"),
        terracottaDeep: Color(hex: "8B5CF6"),
        rose:           Color(hex: "E58AB0"),
        rose2:          Color(hex: "3A2A4A"),
        peach:          Color(hex: "E5A45A"),
        mint:           Color(hex: "5EEAD4"),
        blue:           Color(hex: "38BDF8"),
        lav:            Color(hex: "A78BFA"),
        sun:            Color(hex: "F8D66D"),
        moss:           Color(hex: "5FD0A0"),
        dusk:           Color(hex: "8B7FB8"),
        gold:           Color(hex: "F8D66D"),
        slate:          Color(hex: "8780A0"),
        valenceCold:    Color(hex: "6E5AA6"),
        cardShadow:     Color.black.opacity(0.40),
        // `lav` is already pinned to the same violet as `terracotta` here, so
        // `lavDeep` is a lighter, more pastel violet — distinct from both and
        // still legible as a label/mark against the dark `cream` card surface.
        lavDeep:        Color(hex: "C4B5FD"),
        // A dark theme's "wash" is a tinted panel, not a pale tint — a violet
        // step above `paper`, matching how `paperWarm`/`cream` work here.
        lavWash:        Color(hex: "2A2150"),
        // `ink` is already near-white text in Moon, so the hero card's gradient
        // becomes a soft bright card popping off the dark page — the same
        // "loudest card on screen" role `ink→inkRaised` plays in the light
        // palettes, just inverted the way every dark-theme hero naturally is.
        inkRaised:      Color(hex: "E8E0FF")
    )

    // ── Forest — grounded greens + warm sand ─────────────────────────────
    static let forest = ThemePalette(
        paper:          Color(hex: "EDF8F1"),
        paperWarm:      Color(hex: "F4F0DC"),
        cream:          Color(hex: "FCFEF6"),
        ink:            Color(hex: "163326"),
        inkSoft:        Color(hex: "5E6F66"),
        terracotta:     Color(hex: "2FBF71"),
        terracottaDeep: Color(hex: "0E7490"),
        rose:           Color(hex: "E59A8E"),
        rose2:          Color(hex: "DDEFE3"),
        peach:          Color(hex: "F0C879"),
        mint:           Color(hex: "9DE8C0"),
        blue:           Color(hex: "7FCBD3"),
        lav:            Color(hex: "A7C8C0"),
        sun:            Color(hex: "F6C453"),
        moss:           Color(hex: "5FBF8C"),
        dusk:           Color(hex: "7FA89A"),
        gold:           Color(hex: "E8B84B"),
        slate:          Color(hex: "9DB0A6"),
        valenceCold:    Color(hex: "6FA39A"),
        cardShadow:     Color(hex: "0F3D2A").opacity(0.12),
        lavDeep:        Color(hex: "4F7A70"),
        lavWash:        Color(hex: "E3F0E9"),
        inkRaised:      Color(hex: "2E5943")
    )

    // ── Graphite — cool, data-first ──────────────────────────────────────
    static let graphite = ThemePalette(
        paper:          Color(hex: "EEF1F5"),
        paperWarm:      Color(hex: "DEE5EC"),
        cream:          Color(hex: "FFFFFF"),
        ink:            Color(hex: "151B25"),
        inkSoft:        Color(hex: "5E6878"),
        terracotta:     Color(hex: "2563EB"),
        terracottaDeep: Color(hex: "0F172A"),
        rose:           Color(hex: "F08A8A"),
        rose2:          Color(hex: "E3E9F1"),
        peach:          Color(hex: "F6A86A"),
        mint:           Color(hex: "5BD68C"),
        blue:           Color(hex: "60A5FA"),
        lav:            Color(hex: "8C93F0"),
        sun:            Color(hex: "F5C518"),
        moss:           Color(hex: "22C55E"),
        dusk:           Color(hex: "7E8AA0"),
        gold:           Color(hex: "EAB308"),
        slate:          Color(hex: "94A3B8"),
        valenceCold:    Color(hex: "7480A8"),
        cardShadow:     Color(hex: "16203A").opacity(0.14),
        lavDeep:        Color(hex: "5A63C4"),
        lavWash:        Color(hex: "E3E6FA"),
        inkRaised:      Color(hex: "2B3648")
    )

    // ── Sunset — warm dusk ───────────────────────────────────────────────
    static let sunset = ThemePalette(
        paper:          Color(hex: "FFF0DF"),
        paperWarm:      Color(hex: "FFE3E0"),
        cream:          Color(hex: "FFFBF6"),
        ink:            Color(hex: "2D1A12"),
        inkSoft:        Color(hex: "8A6657"),
        terracotta:     Color(hex: "FF6B35"),
        terracottaDeep: Color(hex: "B45309"),
        rose:           Color(hex: "FF8FA3"),
        rose2:          Color(hex: "FFE0D5"),
        peach:          Color(hex: "FFB088"),
        mint:           Color(hex: "EFC98A"),
        blue:           Color(hex: "EAB07A"),
        lav:            Color(hex: "E2A6C5"),
        sun:            Color(hex: "FACC15"),
        moss:           Color(hex: "E0954F"),
        dusk:           Color(hex: "C08A6A"),
        gold:           Color(hex: "F5B829"),
        slate:          Color(hex: "B5998C"),
        valenceCold:    Color(hex: "C28A8A"),
        cardShadow:     Color(hex: "703018").opacity(0.16),
        lavDeep:        Color(hex: "B06B8F"),
        lavWash:        Color(hex: "F7E0EC"),
        inkRaised:      Color(hex: "4A2E1E")
    )
}

// MARK: - App Theme
//
// The public design-system surface. Colour properties proxy to `active` so a
// theme change is reflected everywhere these tokens are read. `active` is set
// by ThemeManager; default is `.bloom`.
struct AppTheme {

    /// The currently selected palette. Mutated by ThemeManager.
    static var active: ThemePalette = .bloom

    // ── Pastel palette (now theme-driven) ──────────────────────────────
    static var paper: Color          { active.paper }
    static var paperWarm: Color      { active.paperWarm }
    static var cream: Color          { active.cream }
    static var ink: Color            { active.ink }
    static var inkSoft: Color        { active.inkSoft }

    static var terracotta: Color     { active.terracotta }
    static var terracottaDeep: Color { active.terracottaDeep }

    static var rose: Color           { active.rose }
    static var rose2: Color          { active.rose2 }
    static var peach: Color          { active.peach }
    static var mint: Color           { active.mint }
    static var blue: Color           { active.blue }
    static var lav: Color            { active.lav }
    static var sun: Color            { active.sun }

    static var moss: Color           { active.moss }
    static var dusk: Color           { active.dusk }
    static var gold: Color           { active.gold }
    static var slate: Color          { active.slate }

    static var lavDeep: Color        { active.lavDeep }
    static var lavWash: Color        { active.lavWash }
    static var inkRaised: Color      { active.inkRaised }

    // ── Semantic aliases ───────────────────────────────────────────────
    static var primary: Color      { active.terracotta }
    static var background: Color   { active.paper }
    static var surface: Color      { active.cream }
    static var textPrimary: Color  { active.ink }
    static var textSecond: Color   { active.inkSoft }

    // ── Mood → accent color ────────────────────────────────────────────
    static func moodColor(_ mood: Mood?) -> Color {
        guard let mood else { return paperWarm }
        switch mood {
        case .amazing:  return gold
        case .good:     return moss
        case .neutral:  return slate
        case .bad:      return dusk
        case .terrible: return active.valenceCold
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
    // every river is recognisably Spilr.

    /// Valence -3…+3 → a hue from cool/heavy to warm/bright.
    static func valenceColor(_ valence: Int) -> Color {
        switch valence {
        case ...(-2): return active.valenceCold   // cold lavender
        case -1:      return dusk
        case 0:       return blue
        case 1:       return mint
        case 2:       return peach
        default:      return sun                   // +3 bright
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
    static var cardShadow: Color { active.cardShadow }
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
