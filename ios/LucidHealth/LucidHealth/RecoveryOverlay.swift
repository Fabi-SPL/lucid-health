import Foundation
import SwiftUI

/// RecoveryOverlay — the "voice layer" that sits on top of AppMode.
/// Mode picks the layout, RecoveryOverlay picks the tone.
///
/// Resolver order (first match wins):
///   1. illness   — resp rate + HR up + HRV dropping → sentinel mode
///   2. alcohol   — overnight alcohol impact flagged
///   3. red       — recovery < 33%
///   4. yellow    — recovery 33–66%
///   5. green     — recovery > 66%
///   6. neutral   — no recovery data yet
enum RecoveryOverlay: String, CaseIterable {
    case illness
    case alcohol
    case red
    case yellow
    case green
    case neutral

    var title: String {
        switch self {
        case .illness:  return "You may be getting sick"
        case .alcohol:  return "Post-alcohol recovery"
        case .red:      return "Soft day"
        case .yellow:   return "Conservative today"
        case .green:    return "Full send window"
        case .neutral:  return ""
        }
    }

    var subtitle: String {
        switch self {
        case .illness:  return "Training gate engaged · hydrate · rest"
        case .alcohol:  return "Today is for rebuilding — no guilt, just water + food + walking"
        case .red:      return "Rough night — let's keep today light"
        case .yellow:   return "Medium output today · don't stack"
        case .green:    return "Window is open — 90m focus or zone-2, both good"
        case .neutral:  return ""
        }
    }

    var icon: String {
        switch self {
        case .illness:  return "cross.circle.fill"
        case .alcohol:  return "drop.triangle.fill"
        case .red:      return "cloud.rain.fill"
        case .yellow:   return "cloud.fill"
        case .green:    return "sun.max.fill"
        case .neutral:  return "circle.dashed"
        }
    }

    var accent: Color {
        switch self {
        case .illness:  return DS.Colors.danger
        case .alcohol:  return DS.Colors.violet
        case .red:      return DS.Colors.danger
        case .yellow:   return DS.Colors.warning
        case .green:    return DS.Colors.success
        case .neutral:  return DS.Colors.textMuted
        }
    }

    /// Whether to render the overlay banner at all.
    var shouldShow: Bool { self != .neutral }
}

/// Resolver for the current RecoveryOverlay given live health state.
/// Reads HealthEngine @Published fields.
struct RecoveryOverlayResolver {
    static func resolve(engine: HealthEngine) -> RecoveryOverlay {
        // Illness takes priority — even if recovery score is "ok", the sentinel
        // pattern (resp up + HR up + HRV drop) means training is off the table.
        if engine.illnessRisk >= 2 || engine.illnessAlert != nil {
            return .illness
        }
        // Alcohol overlay — overnight alcohol detection flagged a non-zero impact.
        // lastAlcoholImpact is % RMSSD depression vs baseline.
        if engine.lastAlcoholImpact >= 10 {
            return .alcohol
        }
        // Recovery-score bands.
        let r = engine.recoveryScore
        if r <= 0 { return .neutral }           // no data yet
        if r < 33 { return .red }
        if r < 66 { return .yellow }
        return .green
    }
}
