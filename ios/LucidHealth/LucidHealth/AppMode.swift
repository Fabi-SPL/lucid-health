import Foundation
import SwiftUI

/// AppMode — the current soul-state of LucidBridge.
/// Read time + Whoop + sleep + recovery state, pick a mode, home screen adapts.
/// User never switches manually.
///
/// Design doc: `C:/Users/ilgfa/Desktop/New Concepts/LucidBridge Adaptive Redesign.html`
enum AppMode: String, CaseIterable {
    case justWokeUp
    case morning
    case day
    case evening
    case windDown
    case lateNight

    var title: String {
        switch self {
        case .justWokeUp: return "Just woke up"
        case .morning:    return "Morning"
        case .day:        return "Day"
        case .evening:    return "Evening"
        case .windDown:   return "Wind-Down"
        case .lateNight:  return "Late-Night Protection"
        }
    }

    var subtitle: String {
        switch self {
        case .justWokeUp: return "Here's the story of last night."
        case .morning:    return "Tap when you're up."
        case .day:        return "One number, one suggestion."
        case .evening:    return "You had a real day."
        case .windDown:   return "Slow the body down."
        case .lateNight:  return "No recommendations at this hour."
        }
    }

    var icon: String {
        switch self {
        case .justWokeUp: return "sparkles"
        case .morning:    return "sun.max.fill"
        case .day:        return "sun.and.horizon.fill"
        case .evening:    return "sunset.fill"
        case .windDown:   return "moon.stars.fill"
        case .lateNight:  return "moon.fill"
        }
    }

    /// Accent color per mode — subtle tint, same deep base.
    var color: Color {
        switch self {
        case .justWokeUp: return DS.Colors.warning
        case .morning:    return DS.Colors.warning
        case .day:        return DS.Colors.teal
        case .evening:    return DS.Colors.violet
        case .windDown:   return DS.Colors.violet
        case .lateNight:  return DS.Colors.violet
        }
    }

    /// True when the mode should actively gate recommendations.
    /// Late-Night NEVER shows work suggestions, regardless of HRV/focus score.
    var blocksRecommendations: Bool {
        self == .lateNight
    }
}

/// AppModeStore — observable wrapper that recomputes the current AppMode every
/// minute + on relevant state changes. Bind this to ContentView so the whole UI
/// reacts when the mode flips.
@MainActor
final class AppModeStore: ObservableObject {
    @Published private(set) var current: AppMode = .evening
    /// Last time the user tapped "I'm awake" — used for the Just-Woke-Up window.
    @Published var manualWakeTapAt: Date?

    private var ticker: Timer?
    private weak var engine: HealthEngine?

    func start(engine: HealthEngine) {
        self.engine = engine
        recompute()
        ticker?.invalidate()
        // Tick every 60s — mode rarely changes faster than that.
        ticker = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recompute() }
        }
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
    }

    /// Call this when the user taps the "I'm awake" button — forces Just-Woke-Up
    /// mode for the next 20 minutes.
    func tapImAwake() {
        manualWakeTapAt = Date()
        recompute()
    }

    func recompute() {
        let mode = ModeResolver.resolve(
            now: Date(),
            sleepEnded: engine?.sleepEndTime,
            sleepDetected: engine?.sleepDetected ?? false,
            manualWakeTapAt: manualWakeTapAt
        )
        if mode != current { current = mode }
    }
}

/// ModeResolver — picks the right AppMode given current clock + health state.
/// Rules resolve top to bottom. First match wins.
///
/// Order:
///   1. Just Woke Up — fires on wake tap or auto-detected wake within last 20m
///   2. Late-Night — hard gate 00:00-05:00, overrides everything
///   3. Wind-Down   — 22:00-00:00
///   4. Morning     — 06:00-10:00 AND sleep not ended yet
///   5. Day         — 10:00-17:00
///   6. Evening     — 17:00-22:00 (default fallback)
struct ModeResolver {
    /// Compute the current AppMode given inputs.
    ///
    /// - Parameters:
    ///   - now: current time
    ///   - sleepEnded: when sleep ended (from HealthEngine.sleepEndTime) — if within
    ///     last 20 minutes, fires Just-Woke-Up mode
    ///   - sleepDetected: currently in a detected sleep stage
    ///   - manualWakeTapAt: when user tapped "I'm awake" — if within last 20m,
    ///     forces Just-Woke-Up mode
    static func resolve(
        now: Date = Date(),
        sleepEnded: Date? = nil,
        sleepDetected: Bool = false,
        manualWakeTapAt: Date? = nil
    ) -> AppMode {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)

        // Rule 1 — Just Woke Up (wake tap OR auto-wake within 20m)
        let recentWake: Bool = {
            if let tap = manualWakeTapAt, now.timeIntervalSince(tap) < 20 * 60 { return true }
            if let end = sleepEnded, now.timeIntervalSince(end) < 20 * 60 { return true }
            return false
        }()
        if recentWake { return .justWokeUp }

        // Rule 2 — Late-Night Protection (hard gate, 00:00 — 05:00)
        if hour >= 0 && hour < 5 { return .lateNight }

        // Rule 3 — Wind-Down (22:00 — 00:00)
        if hour >= 22 { return .windDown }

        // Rule 4 — Morning (06:00 — 10:00) AND sleep not ended yet
        if hour >= 5 && hour < 10 && !sleepHasEndedToday(sleepEnded: sleepEnded, now: now) {
            return .morning
        }

        // Rule 5 — Day (10:00 — 17:00)
        if hour >= 10 && hour < 17 { return .day }

        // Rule 6 — Evening default (17:00 — 22:00)
        return .evening
    }

    /// True if the sleep-end timestamp is from today — meaning the user has
    /// already confirmed wake for this sleep cycle.
    private static func sleepHasEndedToday(sleepEnded: Date?, now: Date) -> Bool {
        guard let end = sleepEnded else { return false }
        return Calendar.current.isDate(end, inSameDayAs: now)
    }
}
