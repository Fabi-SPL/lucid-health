import Foundation
import UserNotifications

extension Notification.Name {
    /// Posted when a biostate notification's "Open & fix" action (or body tap) is hit.
    /// object = detector rawValue String ("arousal"/"drunk"/"respiration").
    /// InsightsView observes this and opens the dashboard's correction sheet.
    static let lucidOpenBiostate = Notification.Name("lucidOpenBiostate")
}

/// EXPERIMENTAL biostate change-notifier — the training flywheel.
///
/// On a throttled cadence (driven by the BLE HR tick so it runs whenever the strap
/// is live, foreground or background), it reads `biostate_all_now` and, when a
/// detector's discrete STATE changes vs the last-notified snapshot, fires a LOCAL,
/// actionable notification. Fabi confirms ("✓ Right") or corrects ("Sober", "Was
/// calm"…) straight from the lockscreen → `log_state_correction` (more ground-truth
/// labels = the #1 accuracy lever).
///
/// Self-registers as the UNUserNotificationCenter delegate, replicating the app's
/// existing foreground-present behavior — so NO edit to AppDelegate is needed.
/// Everything stays experimental.
final class BiostateNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = BiostateNotifier()
    private override init() { super.init() }

    private let svc = ExperimentalFeaturesService.shared
    private let defaults = UserDefaults.standard

    private var activated = false
    private var checking = false
    private var lastCheck = Date.distantPast
    private let minInterval: TimeInterval = 300   // 5-min throttle (also the max notif rate/detector)

    private static let catArousal = "BIOSTATE_AROUSAL"
    private static let catDrunk   = "BIOSTATE_DRUNK"
    private static let catResp    = "BIOSTATE_RESP"
    private static let openId     = "BIOSTATE_OPEN"

    private func snapKey(_ s: String) -> String { "biostate_notif_\(s)" }

    // MARK: - Activation

    /// Idempotent. Registers categories + claims the notification delegate.
    func activate() {
        guard !activated else { return }
        activated = true
        registerCategories()
        ensureDelegate()
    }

    private func ensureDelegate() {
        let center = UNUserNotificationCenter.current()
        if !(center.delegate is BiostateNotifier) {
            center.delegate = self   // willPresent below replicates prior behavior
        }
    }

    private func registerCategories() {
        let center = UNUserNotificationCenter.current()
        let open = UNNotificationAction(identifier: Self.openId, title: "Open & fix", options: [.foreground])
        func act(_ id: String, _ title: String) -> UNNotificationAction {
            UNNotificationAction(identifier: id, title: title, options: [])
        }
        let arousal = UNNotificationCategory(identifier: Self.catArousal, actions: [
            act("AROUSAL_RIGHT", "✓ Right"), act("AROUSAL_CALM", "Was calm"),
            act("AROUSAL_HIGH", "Was stressed"), open
        ], intentIdentifiers: [], options: [])
        let drunk = UNNotificationCategory(identifier: Self.catDrunk, actions: [
            act("DRUNK_RIGHT", "✓ Right"), act("DRUNK_SOBER", "Sober"),
            act("DRUNK_MORE", "More drunk"), open
        ], intentIdentifiers: [], options: [])
        let resp = UNNotificationCategory(identifier: Self.catResp, actions: [
            act("RESP_RIGHT", "✓ Right"), open
        ], intentIdentifiers: [], options: [])

        // merge — never clobber existing alarm / cognitive categories
        center.getNotificationCategories { existing in
            var set = existing
            set.insert(arousal); set.insert(drunk); set.insert(resp)
            center.setNotificationCategories(set)
        }
    }

    // MARK: - Throttled tick (called from the BLE HR handler)

    func noteTick() {
        if !activated { activate() }
        let now = Date()
        guard !checking, now.timeIntervalSince(lastCheck) >= minInterval else { return }
        lastCheck = now
        checking = true
        Task {
            await checkAndNotify()
            checking = false
        }
    }

    // MARK: - Change detection

    func checkAndNotify() async {
        ensureDelegate()
        guard let s = await svc.fetchBiostateNow() else { return }

        if let a = s.arousal, a.arousal != nil, let band = a.band, band != "unknown" {
            maybeNotify(
                stateKey: "arousal_band", newState: band,
                title: "Arousal", body: "\(a.emoji ?? "") \(human(band)) · \(fmt(a.arousal))",
                category: Self.catArousal,
                userInfo: ["detector": "arousal", "state": band, "value": a.arousal ?? 5.0])
        }

        if let d = s.drunk, d.gated != true, let stage = d.stage, let label = d.label {
            maybeNotify(
                stateKey: "drunk_stage", newState: String(stage),
                title: "Intoxication", body: "\(label.capitalized) · stage \(stage)",
                category: Self.catDrunk,
                userInfo: ["detector": "drunk", "state": label, "value": Double(stage)])
        }

        if let r = s.respiration, let rr = r.resp_rate {
            let band = rr < 12 ? "slow" : (rr > 20 ? "fast" : "normal")
            maybeNotify(
                stateKey: "resp_band", newState: band,
                title: "Breathing", body: "\(band) · \(fmt(rr)) bpm",
                category: Self.catResp,
                userInfo: ["detector": "respiration", "state": band, "value": rr])
        }
    }

    private func maybeNotify(stateKey: String, newState: String, title: String,
                             body: String, category: String, userInfo: [String: Any]) {
        let prev = defaults.string(forKey: snapKey(stateKey))
        guard prev != newState else { return }            // no change
        defaults.set(newState, forKey: snapKey(stateKey))
        if prev == nil { return }                          // first observation = silent baseline
        fire(title: title, body: body, category: category, userInfo: userInfo)
    }

    private func fire(title: String, body: String, category: String, userInfo: [String: Any]) {
        let content = UNMutableNotificationContent()
        content.title = "🧪 \(title) changed"
        content.body = "\(body) — right? tap to confirm or fix"
        content.sound = .default
        content.categoryIdentifier = category
        content.userInfo = userInfo
        content.interruptionLevel = .active
        let req = UNNotificationRequest(
            identifier: "biostate-\(category)-\(Date().timeIntervalSince1970)",
            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])   // preserve app-wide behavior
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        guard let detector = info["detector"] as? String else { completionHandler(); return }
        let action = response.actionIdentifier

        // deep-link to the dashboard for nuanced correction
        if action == Self.openId || action == UNNotificationDefaultActionIdentifier {
            NotificationCenter.default.post(name: .lucidOpenBiostate, object: detector)
            completionHandler(); return
        }
        if action == UNNotificationDismissActionIdentifier { completionHandler(); return }

        let detectedState = info["state"] as? String
        let detectedValue = (info["value"] as? Double) ?? (info["value"] as? NSNumber)?.doubleValue
        let c = Self.correction(action: action, detectedState: detectedState, detectedValue: detectedValue)
        Task {
            await svc.logStateCorrection(detector: detector,
                correctedState: c.state, correctedValue: c.value, note: "lockscreen:\(action)")
            completionHandler()
        }
    }

    private static func correction(action: String, detectedState: String?, detectedValue: Double?) -> (state: String?, value: Double?) {
        switch action {
        case "AROUSAL_RIGHT", "DRUNK_RIGHT", "RESP_RIGHT": return (detectedState, detectedValue)   // confirm
        case "AROUSAL_CALM": return ("relaxed", 3)
        case "AROUSAL_HIGH": return ("high_arousal", 8)
        case "DRUNK_SOBER":  return ("sober", 0)
        case "DRUNK_MORE":   return (nil, min((detectedValue ?? 0) + 1, 4))
        default:             return (detectedState, detectedValue)
        }
    }

    // MARK: - Helpers

    private func human(_ s: String) -> String { s.replacingOccurrences(of: "_", with: " ") }
    private func fmt(_ v: Double?) -> String { v.map { String(format: "%.1f", $0) } ?? "—" }
}
