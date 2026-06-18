import Foundation

/// Detected food item — everything Gemini gives us, structured.
/// Schema is JSONB on the backend so Optional fields are forward/backward compatible.
struct DetectedItem: Codable, Identifiable {
    var id = UUID()
    var name: String
    var nameLocal: String?            // Gemini's locale-aware variant (de_DE)
    var grams: Int
    var kcal: Int
    var caloriesLow: Int?             // estimated_calories_low
    var caloriesHigh: Int?            // estimated_calories_high
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?
    var fiberG: Double?
    var novaClass: Int
    var novaConfidence: String?       // low / medium / high
    var novaReasoning: String?        // why Gemini picked this NOVA class
    var quantityConfidence: String?   // low / medium / high
    var quantityDescription: String?  // human description: "300 grams", "one fist"
    var mindTags: [String]
    var isDrink: Bool?
    var isAlcohol: Bool?
    var isSupplement: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case nameLocal = "name_local"
        case grams, kcal
        case caloriesLow = "calories_low"
        case caloriesHigh = "calories_high"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case novaClass = "nova_class"
        case novaConfidence = "nova_confidence"
        case novaReasoning = "nova_reasoning"
        case quantityConfidence = "quantity_confidence"
        case quantityDescription = "quantity_description"
        case mindTags = "mind_tags"
        case isDrink = "is_drink"
        case isAlcohol = "is_alcohol"
        case isSupplement = "is_supplement"
    }
}

/// Whole-meal totals from Gemini's `meal_totals` block.
struct MealTotals: Codable {
    var caloriesLow: Int?
    var caloriesMidpoint: Int?
    var caloriesHigh: Int?
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?
    var fiberG: Double?
    var confidenceLevel: String?  // low / medium / high

    enum CodingKeys: String, CodingKey {
        case caloriesLow = "calories_low"
        case caloriesMidpoint = "calories_midpoint"
        case caloriesHigh = "calories_high"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case confidenceLevel = "confidence_level"
    }
}

struct GeminiFoodResult: Codable {
    let items: [DetectedItem]
    let totalKcal: Int
    let novaAvg: Double
    let mindScore: Int?
    let confidence: String
    let notes: String?
    let mealTotals: MealTotals?
    let ambiguities: [String]?

    enum CodingKeys: String, CodingKey {
        case items
        case totalKcal = "total_kcal"
        case novaAvg = "nova_avg"
        case mindScore = "mind_score"
        case confidence, notes
        case mealTotals = "meal_totals"
        case ambiguities
    }
}

struct FoodEntry: Codable, Identifiable {
    var id: UUID?
    var userId: String
    var capturedAt: Date
    var photoUrl: String?
    var geminiRawJson: String?
    var items: [DetectedItem]
    var caption: String?
    var totalKcal: Int?
    var novaAvg: Double?
    var mindScore: Int?
    var confidence: String?
    var source: String
    var createdAt: Date?
    var logQuality: Int? = nil       // 1-10: how reliably this was logged (see computeLogQuality)
    var portionSize: String? = nil   // subjective relative size: tiny|small|normal|big|huge
    var portionFactor: Double? = nil // multiplier vs baseline (tiny .5 / normal 1 / huge 2)

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case capturedAt = "captured_at"
        case photoUrl = "photo_url"
        case geminiRawJson = "gemini_raw_json"
        case items
        case caption
        case totalKcal = "total_kcal"
        case novaAvg = "nova_avg"
        case mindScore = "mind_score"
        case confidence
        case source
        case createdAt = "created_at"
        case logQuality = "log_quality"
        case portionSize = "portion_size"
        case portionFactor = "portion_factor"
    }

    /// Log-quality score 1-10 — how trustworthy the data behind this entry is,
    /// based on HOW it was logged (method) + the analyzer's own confidence.
    /// Barcode (label data) > combined > photo > AI-text > keyword-fallback.
    static func computeLogQuality(source: String, confidence: String?, items: [DetectedItem]) -> Int {
        let conf = (confidence ?? "").lowercased()
        let hasGrams = items.contains { $0.grams > 0 }
        switch source {
        case "barcode":            return hasGrams ? 10 : 9
        case "combined":           return hasGrams ? 8 : 7
        case "photo":
            if conf == "high"   { return 8 }
            if conf == "low"    { return 6 }
            return 7
        case "manual", "text":
            // keyword fallback (offline / Gemini down) is explicitly flagged
            if conf == "rough_text" || conf == "estimate" || conf == "none" { return 3 }
            if conf == "high"   { return 7 }
            if conf == "medium" { return 6 }
            if conf == "low"    { return 5 }
            return 5
        case "quick_tag", "quick_log": return 7
        case "favorite":
            // re-logging a curated saved meal — reliable; confidence only nudges it
            if conf == "high" { return 8 }
            if conf == "low"  { return 6 }
            return 7
        default:                       return 4
        }
    }
}
