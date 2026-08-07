import Foundation

/// A user-saved meal or drink that can be re-logged with one tap from the Food tab.
/// Backed by the `food_favorites` table (multi-item, full macros, optional batch recipe).
/// `items` reuses DetectedItem so logging a favorite produces a normal food_entries row.
struct FoodFavorite: Codable, Identifiable {
    var id: UUID?
    var name: String
    var emoji: String?
    var items: [DetectedItem]
    var totalKcal: Int?
    var novaAvg: Double?
    var mindScore: Int?
    var servingNote: String?
    var source: String?
    var confidence: String?
    var sortOrder: Int?
    /// Used to pick the survivor when two saved meals are the same dish under
    /// slightly different names — the one he actually taps wins.
    var timesLogged: Int?

    /// Portion multipliers offered at log time. Saving the same dish at a second
    /// size is what produced two "Fusilli" favorites 884 kcal apart.
    static let scales: [(String, Double)] = [("½", 0.5), ("¾", 0.75), ("1×", 1.0), ("1½", 1.5), ("2×", 2.0)]

    static func scaleLabel(_ f: Double) -> String {
        scales.first { abs($0.1 - f) < 0.001 }?.0 ?? String(format: "%.2g×", f)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, emoji, items
        case totalKcal = "total_kcal"
        case novaAvg = "nova_avg"
        case mindScore = "mind_score"
        case servingNote = "serving_note"
        case source, confidence
        case sortOrder = "sort_order"
        case timesLogged = "times_logged"
    }
}
