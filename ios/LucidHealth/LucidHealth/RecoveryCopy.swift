import Foundation

/// Recovery-band copy generator. Single source of truth for the short labels
/// and meaning sentences that depend on recovery score. Mode-specific copy
/// (Evening's "Strong day", Dashboard's "Push window") still lives in those
/// views — this only covers the shared band-derived language.
enum RecoveryBand {
    case unknown
    case low
    case mid
    case high

    static func from(_ score: Double) -> RecoveryBand {
        if score <= 0 { return .unknown }
        if score < 33 { return .low }
        if score < 66 { return .mid }
        return .high
    }

    /// Three-word pill label. Used on JustWokeUp's recovery hero.
    var pillLabel: String {
        switch self {
        case .unknown: return "Calibrating"
        case .low:     return "Take it easy"
        case .mid:     return "Hold the line"
        case .high:    return "Go window"
        }
    }

    /// One-sentence interpretation of the recovery band. Shared between
    /// JustWokeUp's hero card and any future "what this means" surface.
    var meaning: String {
        switch self {
        case .unknown: return "System still calibrating. Check back in a minute."
        case .low:     return "Rough night — hydrate, eat, keep cognitive load light."
        case .mid:     return "Moderate output today. Don't stack hard training."
        case .high:    return "Window is open — good 90-min deep work or zone-2."
        }
    }
}
