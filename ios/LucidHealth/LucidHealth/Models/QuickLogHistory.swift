import Foundation

/// Frequency tracker for quick-tag inputs (chips + freeform).
/// UserDefaults-backed, no new DB table needed.
///
/// Records each (canonical name) submission and exposes top-N most-used
/// items for the QuickTagSheet to pin at the top. After 5 espresso logs,
/// "espresso" floats to the top — Fabi's exact ask.
///
/// Canonicalization is local-only here: lowercased + trimmed. The backend
/// AI canonicalization (planned via Gemini batch) will normalize spelling
/// variants later. For now, "espresso" / "Espresso" / "espresso " all map.
struct QuickLogRecent: Codable, Identifiable, Equatable {
    var id: String { name }
    let name: String
    var displayName: String      // original capitalization the user typed
    var emoji: String
    var category: String         // intake / mood / physical / marker
    var type: String             // canonical type (caffeine / supplement / etc)
    var count: Int
    var lastUsed: Date
}

@MainActor
final class QuickLogHistory: ObservableObject {
    static let shared = QuickLogHistory()
    private let key = "lucidhealth_quicklog_history_v1"

    @Published private(set) var entries: [QuickLogRecent] = []

    init() { load() }

    /// Top N items by composite score (frequency × recency decay).
    /// Items used today get a 1.5× boost; items >7d old halve in weight.
    func topItems(limit: Int = 6) -> [QuickLogRecent] {
        let now = Date()
        return entries
            .map { entry -> (QuickLogRecent, Double) in
                let ageDays = now.timeIntervalSince(entry.lastUsed) / 86_400
                let recencyMultiplier: Double = {
                    if ageDays < 1 { return 1.5 }
                    if ageDays < 7 { return 1.0 }
                    if ageDays < 30 { return 0.5 }
                    return 0.2
                }()
                return (entry, Double(entry.count) * recencyMultiplier)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }

    /// Record a usage. Called from BLEManager on every chip / freeform submit.
    func record(name: String, displayName: String, emoji: String, category: String, type: String) {
        let canonical = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !canonical.isEmpty else { return }

        if let idx = entries.firstIndex(where: { $0.name == canonical }) {
            entries[idx].count += 1
            entries[idx].lastUsed = Date()
            // Update emoji/category if a more confident value comes in
            if entries[idx].emoji.isEmpty { entries[idx].emoji = emoji }
        } else {
            entries.append(QuickLogRecent(
                name: canonical,
                displayName: displayName,
                emoji: emoji,
                category: category,
                type: type,
                count: 1,
                lastUsed: Date()
            ))
        }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([QuickLogRecent].self, from: data) else {
            entries = []
            return
        }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Clear all history — for the Settings dev card.
    func reset() {
        entries = []
        UserDefaults.standard.removeObject(forKey: key)
    }
}
