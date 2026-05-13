import Foundation
import UIKit

class GeminiClient {

    static let shared = GeminiClient()

    private let apiKey: String = "local-dev"  // Replaced at CI build time
    private let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"

    // MARK: - Public

    func analyzeFood(image: UIImage, caption: String?) async throws -> GeminiFoodResult {
        let resized = resizeForGemini(image)
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else {
            throw NSError(domain: "Gemini", code: 0, userInfo: [NSLocalizedDescriptionKey: "JPEG encode failed"])
        }
        let b64 = jpeg.base64EncodedString()

        var promptText = systemPrompt
        if let caption, !caption.isEmpty {
            promptText += "\n\nUser note about this meal (use to disambiguate or correct visual identification): \(caption)"
        }

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["inline_data": ["mime_type": "image/jpeg", "data": b64]],
                        ["text": promptText]
                    ]
                ]
            ],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": responseSchema
            ]
        ]

        return try await callGemini(body: body)
    }

    /// Text-only path — user typed a meal description (e.g. "lasagna I made yesterday, ~300g").
    /// No image. Gemini infers items, portions, NOVA, MIND tags purely from prose.
    func analyzeFood(description: String) async throws -> GeminiFoodResult {
        let promptText = textOnlyPrompt + "\n\nUser-described meal:\n\(description)"

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": promptText]
                    ]
                ]
            ],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": responseSchema
            ]
        ]

        return try await callGemini(body: body)
    }

    private func callGemini(body: [String: Any]) async throws -> GeminiFoodResult {
        let url = URL(string: "\(endpoint)?key=\(apiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status < 300 else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "Gemini", code: status, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        return try parseGeminiResponse(data)
    }

    // MARK: - Image Resize

    private func resizeForGemini(_ image: UIImage) -> UIImage {
        let maxDimension: CGFloat = 1024
        let size = image.size
        guard max(size.width, size.height) > maxDimension else { return image }
        let scale = maxDimension / max(size.width, size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }

    // MARK: - Response Parsing

    private func parseGeminiResponse(_ data: Data) throws -> GeminiFoodResult {
        guard let outer = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = outer["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String,
              let jsonData = text.data(using: .utf8) else {
            throw NSError(domain: "Gemini", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unexpected Gemini response shape"])
        }

        guard let raw = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw NSError(domain: "Gemini", code: 0, userInfo: [NSLocalizedDescriptionKey: "Gemini JSON parse failed"])
        }

        return buildResult(from: raw, rawJSON: text)
    }

    private func buildResult(from raw: [String: Any], rawJSON: String) -> GeminiFoodResult {
        let foods = (raw["foods"] as? [[String: Any]]) ?? []
        let items: [DetectedItem] = foods.map { f in
            DetectedItem(
                name: f["name"] as? String ?? "Unknown",
                nameLocal: f["name_local"] as? String,
                grams: f["quantity_grams_estimate"] as? Int ?? 0,
                kcal: f["calories_estimate"] as? Int ?? 0,
                caloriesLow: f["estimated_calories_low"] as? Int,
                caloriesHigh: f["estimated_calories_high"] as? Int,
                proteinG: doubleOf(f["protein_g"]),
                carbsG: doubleOf(f["carbs_g"]),
                fatG: doubleOf(f["fat_g"]),
                fiberG: doubleOf(f["fiber_g"]),
                novaClass: f["nova_group"] as? Int ?? 1,
                novaConfidence: f["nova_confidence"] as? String,
                novaReasoning: f["nova_reasoning"] as? String,
                quantityConfidence: f["quantity_confidence"] as? String,
                quantityDescription: f["quantity_description"] as? String,
                mindTags: f["mind_tags"] as? [String] ?? [],
                isDrink: f["is_drink"] as? Bool,
                isAlcohol: f["is_alcohol"] as? Bool,
                isSupplement: f["is_supplement"] as? Bool
            )
        }

        let totalsRaw = raw["meal_totals"] as? [String: Any] ?? [:]
        let totalKcal = totalsRaw["estimated_calories_midpoint"] as? Int ?? items.reduce(0) { $0 + $1.kcal }
        let novaVals = items.map { Double($0.novaClass) }
        let novaAvg = novaVals.isEmpty ? 1.0 : novaVals.reduce(0, +) / Double(novaVals.count)
        let brainScore = raw["brain_score"] as? [String: Any] ?? [:]
        let mindScore = brainScore["total"] as? Int
        let confidence = (totalsRaw["confidence_level"] as? String) ?? "medium"

        let mealTotals = MealTotals(
            caloriesLow: totalsRaw["estimated_calories_low"] as? Int,
            caloriesMidpoint: totalsRaw["estimated_calories_midpoint"] as? Int,
            caloriesHigh: totalsRaw["estimated_calories_high"] as? Int,
            proteinG: doubleOf(totalsRaw["protein_g_estimate"]),
            carbsG: doubleOf(totalsRaw["carbs_g_estimate"]),
            fatG: doubleOf(totalsRaw["fat_g_estimate"]),
            fiberG: doubleOf(totalsRaw["fiber_g_estimate"]),
            confidenceLevel: confidence
        )

        return GeminiFoodResult(
            items: items,
            totalKcal: totalKcal,
            novaAvg: novaAvg,
            mindScore: mindScore,
            confidence: confidence,
            notes: rawJSON,
            mealTotals: mealTotals,
            ambiguities: raw["ambiguities"] as? [String]
        )
    }

    /// Coerce JSON number (Int or Double) to Double — Gemini returns either depending on value.
    private func doubleOf(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }

    // MARK: - System Prompt

    private let systemPrompt = """
You are a brain-health food analyst. The user has taken a photo of their meal. \
Your task is to identify all foods visible, estimate portions, assign NOVA processing \
group to each item, tag MIND diet categories, estimate macronutrients, and compute \
a brain health score.

IDENTIFICATION RULES:
- Identify every distinct food item visible in the photo.
- For mixed dishes (stews, salads, pasta), break into component ingredients where possible.
- If a dish is a recognized named dish, name it and estimate its standard components.
- For drinks, identify type (water, juice, wine, beer, coffee, soda, etc.).

PORTION ESTIMATION:
- Estimate grams based on visual plate size, food density, and typical serving sizes.
- Use a standard dinner plate as ~26cm reference if no other reference is visible.
- When uncertain about portion, give a range in quantity_description and use \
  quantity_confidence: "low" or "medium".
- Never estimate calories from photos alone with false precision. Always provide \
  estimated_calories_low and estimated_calories_high as a range of at least ±20%.

NOVA CLASSIFICATION (assign to each food item):
- Group 1: Unprocessed or minimally processed foods (whole vegetables, fruits, meat, \
  eggs, plain legumes, plain nuts, plain grains, plain dairy).
- Group 2: Processed culinary ingredients (olive oil, butter, sugar, salt, flour — \
  used in cooking but not eaten alone).
- Group 3: Processed foods (canned vegetables with salt, cheese, cured meat, \
  freshly baked bread, wine, beer). Identifiable ingredients, small additive list.
- Group 4: Ultra-processed foods (packaged snacks, sweet drinks, reconstituted meat \
  products, mass-produced bread with 10+ ingredients, flavored yogurts with additives, \
  fast food items, frozen ready meals). Key marker: substances not found in a home \
  kitchen (emulsifiers, flavor enhancers, stabilizers, hydrogenated fats).

MIND DIET TAGGING (for each food item, list all applicable tags):
Brain-healthy categories (tag presence positively):
- leafy_greens: kale, spinach, romaine, arugula, chard, any dark leafy green
- other_vegetables: tomato, pepper, cucumber, zucchini, broccoli, cauliflower, carrot
- nuts: almonds, walnuts, cashews, pistachios, peanuts, any tree nut
- berries: strawberries, blueberries, raspberries, blackberries, any berry
- legumes: lentils, chickpeas, black beans, kidney beans, edamame, hummus
- whole_grains: oats, quinoa, brown rice, whole wheat bread/pasta, barley
- fish: salmon, tuna, sardines, herring, mackerel, any seafood
- poultry: chicken, turkey, duck
- olive_oil: olive oil specifically (not other oils)
- wine_moderate: wine (1 glass for women, up to 2 for men)

Brain-penalizing categories:
- red_meat: beef, pork, lamb, veal, venison
- processed_meat: sausage, salami, ham, bacon, hot dogs, deli meats
- butter: butter, margarine
- cheese: any cheese
- pastry_sweet: cake, cookies, donuts, candy, ice cream, chocolate (large serving)
- fried_food: any deep-fried item
- fast_food: hamburgers, pizza, fast food restaurant items

BRAIN SCORE COMPUTATION:
1. MIND component: start at 4, +1 per positive category, -1 per penalized category \
   (butter/cheese: -0.5 each), clamp 0–8.
2. NOVA deduction: -2 if majority calories from Group 4, -1 if Group 3 dominant, 0 otherwise.
3. Bonus: +2 if 2+ brain-star categories present (leafy_greens, berries, fish, nuts).
4. Total = MIND_component - nova_deduction + bonus, clamped 0–10.

OUTPUT: Return only the JSON matching the specified schema. No prose. No markdown. Pure JSON only.
"""

    // MARK: - Text-only Prompt (manual log)

    private let textOnlyPrompt = """
You are a brain-health food analyst. The user did NOT take a photo — they typed a description \
of what they ate. Your task is to identify all food items mentioned, infer portions when \
unstated (use typical serving sizes), assign NOVA processing group, tag MIND categories, \
estimate macros, and compute a brain health score.

PORTION INFERENCE (no image, so be conservative):
- If the user gives explicit grams or volume, use it.
- If they say "a portion of X" without quantity, use a standard serving size (~250g for \
  a main course, ~150g for a side, ~30g for nuts/snacks, 250ml for beverages).
- If they say "a small/large bowl" or "a piece", estimate based on typical home portions.
- Mark quantity_confidence as "low" or "medium" — never "high" without explicit grams.
- Always output estimated_calories_low and estimated_calories_high with at least ±25% spread \
  (text-only is less precise than photo).

Apply NOVA classification, MIND diet tagging, and brain score computation per the same rules \
as photo analysis. If the user mentions homemade preparation (e.g. "lasagna I made"), favor \
NOVA group 3 over group 4 — homemade dishes use real ingredients.

OUTPUT: Return only the JSON matching the specified schema. No prose. No markdown. Pure JSON only.
"""

    // MARK: - Response Schema

    private let responseSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "input_mode": ["type": "string"],
            "foods": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string"],
                        "name_local": ["type": "string"],
                        "quantity_description": ["type": "string"],
                        "quantity_grams_estimate": ["type": "integer"],
                        "quantity_confidence": ["type": "string"],
                        "nova_group": ["type": "integer"],
                        "nova_confidence": ["type": "string"],
                        "nova_reasoning": ["type": "string"],
                        "mind_tags": ["type": "array", "items": ["type": "string"]],
                        "calories_estimate": ["type": "integer"],
                        "protein_g": ["type": "number"],
                        "fat_g": ["type": "number"],
                        "carbs_g": ["type": "number"],
                        "is_drink": ["type": "boolean"],
                        "is_alcohol": ["type": "boolean"],
                        "is_supplement": ["type": "boolean"]
                    ]
                ]
            ],
            "meal_totals": [
                "type": "object",
                "properties": [
                    "estimated_calories_low": ["type": "integer"],
                    "estimated_calories_high": ["type": "integer"],
                    "estimated_calories_midpoint": ["type": "integer"],
                    "protein_g_estimate": ["type": "number"],
                    "fat_g_estimate": ["type": "number"],
                    "carbs_g_estimate": ["type": "number"],
                    "fiber_g_estimate": ["type": "number"],
                    "confidence_level": ["type": "string"]
                ]
            ],
            "brain_score": [
                "type": "object",
                "properties": [
                    "total": ["type": "integer"],
                    "mind_component": ["type": "number"],
                    "nova_deduction": ["type": "number"],
                    "bonus_applied": ["type": "boolean"],
                    "mind_positive_categories": ["type": "array", "items": ["type": "string"]],
                    "mind_negative_categories": ["type": "array", "items": ["type": "string"]]
                ]
            ],
            "ambiguities": ["type": "array", "items": ["type": "string"]],
            "confirmation_required": ["type": "boolean"],
            "user_note": ["type": "string"]
        ]
    ]
}
