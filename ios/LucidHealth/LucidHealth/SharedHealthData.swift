import Foundation

/// Shared data model between main app and widget extension via App Groups
/// App Group: group.com.fabi.lucidhealth.shared (NEW — used to be lucidbridge, then lucidhealth, but
/// that's claimed by legacy LucidBridge install on the same Apple ID).
struct SharedHealthData: Codable {
    // Scores
    var recoveryScore: Double = 0
    var sleepScore: Double = 0
    var strainScore: Double = 0
    var bodyBattery: Double = 100
    var trainingLoadRatio: Double = 1.0
    var trainingLoadStatus: String = "Optimal"
    var sleepConsistencyScore: Double = 0

    // Live vitals
    var heartRate: Int = 0
    var currentRMSSD: Double = 0
    var currentHRZone: Int = 0
    var respiratoryRate: Double = 0

    // Connection
    var isConnected: Bool = false
    var strapBattery: Double = 0

    // Sleep
    var sleepDetected: Bool = false
    var sleepStage: String = "awake"
    var sleepDurationHours: Double = 0

    // Readiness
    var readiness: String = "unknown"

    // Cognitive Capacity v2
    var cognitiveCapacity: Double = 0
    var cognitiveLabel: String = "—"
    var sdnn: Double = 0
    var pnn50: Double = 0
    var dfaAlpha1: Double = 0

    // Illness Sentinel
    var illnessAlert: String? = nil
    var illnessRisk: Int = 0

    // Training Load Intelligence
    var trainingMonotony: Double = 0
    var trainingStrain: Double = 0

    // Active activity
    var activeActivityType: String? = nil
    var activeActivityStart: Date? = nil

    // Adaptive app mode — read by widget so the lock-screen face can match
    // the current soul-state (morning/day/evening/windDown/lateNight/justWokeUp).
    // Values are AppMode.rawValue strings.
    var appMode: String = "evening"

    // Recovery overlay — optional override layer (red/yellow/green/alcohol/illness).
    var recoveryOverlay: String = "neutral"

    // Day state — third dimension cutting across AppMode + RecoveryOverlay.
    // Values: normal, hangover, sick, soft, sleepDebt, push, wired.
    // Auto-detected from accumulated signals; widgets layout-transform per state.
    var dayState: String = "normal"

    // Timestamp
    var lastUpdated: Date = Date()

    // MARK: - App Group Storage
    //
    // 2026-05-05 — switched from UserDefaults(suiteName:) to a file in the
    // shared container. Reason: AltStore Classic re-signs IPAs at install
    // time using free Apple Developer cert. UserDefaults app-group access
    // is the most fragile entitlement check on iOS — when the suite is
    // denied, UserDefaults(suiteName:) silently returns a per-process
    // container instead of nil. That's why the host app worked but
    // widget showed zeros: each process was reading its OWN empty store.
    //
    // FileManager.containerURL(forSecurityApplicationGroupIdentifier:) is
    // more permissive AND fails visibly (returns nil) when access is
    // denied — making the failure mode debuggable instead of silent.

    static let groupID = "group.com.fabi.lucidhealth.shared"
    static let fileName = "shared-health.json"

    private static var sharedURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent(fileName)
    }

    static func save(_ data: SharedHealthData) {
        guard let url = sharedURL else {
            LucidLog.log("SharedHealthData", "save FAILED — sharedURL nil (App Group denied)")
            return
        }
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        do {
            try encoded.write(to: url, options: .atomic)
        } catch {
            LucidLog.log("SharedHealthData", "save error: \(error.localizedDescription)")
        }
    }

    static func load() -> SharedHealthData {
        guard let url = sharedURL else {
            LucidLog.log("SharedHealthData", "load FAILED — sharedURL nil (App Group denied)")
            return SharedHealthData()
        }
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(SharedHealthData.self, from: data)
        else {
            return SharedHealthData()
        }
        return decoded
    }
}
