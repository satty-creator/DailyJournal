//
//  AppTheme.swift
//  DailyJournal
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

    // ── Raw palette ────────────────────────────────────────────────────
    static let paper          = Color(hex: "F2EBDE")
    static let paperWarm      = Color(hex: "EAE0CE")
    static let cream          = Color(hex: "FBF7EE")
    static let ink            = Color(hex: "1A1614")
    static let inkSoft        = Color(hex: "3A332D")
    static let terracotta     = Color(hex: "C8472F")
    static let terracottaDeep = Color(hex: "9B3120")
    static let moss           = Color(hex: "5C6F4A")
    static let dusk           = Color(hex: "6B5B8A")
    static let gold           = Color(hex: "C9973A")
    static let slate          = Color(hex: "8B8B7A")

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
        case .terrible: return Color(hex: "7A3B3B")
        }
    }

    // ── Sentiment string → accent color ───────────────────────────────
    static func sentimentColor(_ label: String?) -> Color {
        guard let s = label?.lowercased() else { return slate }
        switch true {
        case s.contains("anxi"), s.contains("stress"),
             s.contains("worry"), s.contains("dread"), s.contains("fear"):
            return terracotta
        case s.contains("excit"), s.contains("happy"),
             s.contains("joy"),   s.contains("elat"),  s.contains("thrill"):
            return gold
        case s.contains("sad"),  s.contains("grief"),
             s.contains("mourn"), s.contains("depress"), s.contains("low"):
            return dusk
        case s.contains("calm"), s.contains("peace"),
             s.contains("content"), s.contains("gratit"), s.contains("serene"):
            return moss
        default:
            return slate
        }
    }

    // ── Typography helpers ─────────────────────────────────────────────
    static func editorialDisplay(size: CGFloat, weight: Font.Weight = .light) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func editorialBody(size: CGFloat = 17) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    static func mono(size: CGFloat = 12) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }
}
