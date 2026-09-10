//
//  DailyReadModels.swift
//  DailyJournal
//
//  Shared tone/sharpness/safety vocabulary. Originally built for "Today's Read"
//  (removed — see git history), these enums are reused by `MirrorCard`.
//

import Foundation

// MARK: - Tone

/// The flavour the *generated* read text actually lands in. This is a property of
/// the read, chosen by the engine, not a user setting.
enum ReadTone: String, Codable, CaseIterable {
    case soft
    case direct
    case funny
    case spicy

    /// Tiny mono-uppercase tag shown on the card.
    var displayLabel: String { rawValue }
}

// MARK: - Sharpness preference

/// The user-facing "how hard should it hit?" dial. Distinct from `ReadTone`:
/// `funny` is a *flavour* the engine can reach for, but the sharpness LADDER the
/// "too sharp" loop walks down is strictly soft ↔ direct ↔ spicy (per spec:
/// "spicy → direct, or direct → soft"). The local engine maps this preference
/// onto a tone, optionally choosing `funny` only at `.direct`/`.spicy`.
enum ReadSharpness: String, Codable, CaseIterable {
    case soft
    case direct
    case spicy

    /// Ordered gentle → sharp. Used by the "too sharp" step-down.
    static let ladder: [ReadSharpness] = [.soft, .direct, .spicy]

    var gradient: Int { Self.ladder.firstIndex(of: self) ?? 1 }

    /// One gradient gentler. `.soft` is the floor — it never goes lower.
    var softer: ReadSharpness {
        let i = gradient
        return i > 0 ? Self.ladder[i - 1] : .soft
    }
}

// MARK: - Rejection codes

/// The "not me" micro-menu classification codes. Appended to training history so
/// the next payload assembly steers clear of the same failure mode.
enum ReadRejectionCode: String, Codable, CaseIterable {
    case tooDramatic   = "too_dramatic"
    case wrongTopic    = "wrong_topic"
    case tooVague      = "too_vague"
    case closeNotQuite = "close_but_not_quite"

    var label: String {
        switch self {
        case .tooDramatic:   return "too dramatic"
        case .wrongTopic:    return "wrong topic"
        case .tooVague:      return "too vague"
        case .closeNotQuite: return "close, but not quite"
        }
    }
}

// MARK: - Safety level

/// Self-reported distress level from the generator, mirrored from the server.
/// `none` is the only level allowed to surface a read; anything else is held
/// back client-side as a belt-and-suspenders gate on top of the server guard.
enum ReadSafetyLevel: String, Codable {
    case none
    case mildDistress = "mild_distress"
    case highDistress = "high_distress"

    var isSurfaceable: Bool { self == .none }
}
