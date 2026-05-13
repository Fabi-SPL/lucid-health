import ActivityKit
import SwiftUI

/// Live Activity attributes for active health tracking (Spotify-style bar)
/// + always-on bridge face when activityType == "bridge".
struct LucidActivityAttributes: ActivityAttributes {
    /// State that ticks per BLE reading. Default values exist so older
    /// builds that don't write a field still decode safely.
    public struct ContentState: Codable, Hashable {
        var heartRate: Int = 0
        var duration: TimeInterval = 0  // seconds since activity started
        var strainAccumulated: Double = 0
        var currentHRZone: Int = 0
        var bodyBattery: Double = 0
        var emoji: String = "🎯"  // activity emoji for display
        /// 2026-04-27 — RMSSD (HRV) added for the bridge face. Workout face
        /// ignores it; bridge face uses it as the secondary metric.
        var currentRMSSD: Double = 0
    }

    // Fixed context
    var activityType: String  // "skiing", "sauna", "exercise", "bridge", etc.
    var startTime: Date
}
