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

    enum CodingKeys: String, CodingKey {
        case id, name, emoji, items
        case totalKcal = "total_kcal"
        case novaAvg = "nova_avg"
        case mindScore = "mind_score"
        case servingNote = "serving_note"
        case source, confidence
        case sortOrder = "sort_order"
    }
}
