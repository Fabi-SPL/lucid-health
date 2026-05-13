import Foundation

/// Shared activity-type → display-string helpers. Used across MorningHomeView,
/// DayHomeView, ActivityView, HealthIntelligenceView, BLEManager, and
/// ActivityDetector. Single source of truth so adding a new activity type
/// only happens here.

func activityEmoji(_ type: String) -> String {
    let map: [String: String] = [
        "sauna": "🧖",
        "cold_plunge": "🥶",
        "exercise": "🏋️",
        "workout": "🏋️",
        "deep_work": "🧠",
        "social": "👥",
        "social_small": "🍷",
        "social_large": "🎉",
        "alcohol": "🍺",
        "coffee": "☕",
        "motorcycle": "🏍️",
        "anxiety": "😰",
        "nap": "😴",
        "wake_up": "☀️",
        "sleep": "🌙",
        "meal": "🍽️",
        "frustration": "😤",
        "spiral": "🌀",
        "good_vibes": "😊",
        "hyperfocus": "🎯"
    ]
    return map[type] ?? "⚡"
}

func activityName(_ type: String) -> String {
    type.replacingOccurrences(of: "_", with: " ").capitalized
}
