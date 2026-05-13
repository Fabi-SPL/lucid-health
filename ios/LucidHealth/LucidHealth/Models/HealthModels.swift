import Foundation

struct PersonalModelEntry {
    let modelType: String
    let modelKey: String
    let modelData: [String: Any]
    let confidence: Double
    let dataPoints: Int
}

struct ActivityEvent: Identifiable, Hashable {
    let id: String
    let activityType: String
    let source: String
    let startedAt: Date
    let endedAt: Date?
    let hrAvg: Int?
    let hrvAvg: Double?
    let notes: String?
    let eventCategory: String
}

/// A single physiology reading pulled from realtime_health. Powers the timeline
/// backtrack scrubber in ActivityEditSheet so Fabi can snap activity boundaries
/// to HR / HRV spikes when he only remembers the rough time.
struct PhysioSample: Identifiable {
    var id: Double { time.timeIntervalSince1970 }
    let time: Date
    let hr: Int
    let hrv: Double
}
