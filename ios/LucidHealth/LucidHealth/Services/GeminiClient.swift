import Foundation
import UIKit

/// Food analysis client. Calls the server-side proxy RPCs (`analyze_food_photo`,
/// `analyze_food_text`) instead of Google directly — the Gemini key lives in
/// Supabase Vault, never in this binary. The RPC returns the raw Gemini response,
/// so parseGeminiResponse stays unchanged.
class GeminiClient {

    static let shared = GeminiClient()

    // MARK: - Public

    func analyzeFood(image: UIImage, caption: String?) async throws -> GeminiFoodResult {
        let resized = resizeForGemini(image)
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else {
            throw NSError(domain: "Gemini", code: 0, userInfo: [NSLocalizedDescriptionKey: "JPEG encode failed"])
        }
        let b64 = jpeg.base64EncodedString()
        var args: [String: Any] = ["p_image_base64": b64, "p_mime": "image/jpeg"]
        if let caption, !caption.isEmpty { args["p_caption"] = caption }
        return try await callProxy(rpc: "analyze_food_photo", args: args)
    }

    /// Text-only path — user typed a meal description. Server infers items, portions,
    /// NOVA, MIND tags, macros, brain score purely from prose.
    func analyzeFood(description: String) async throws -> GeminiFoodResult {
        return try await callProxy(rpc: "analyze_food_text", args: ["p_description": description])
    }

    // MARK: - Server proxy transport

    private func callProxy(rpc: String, args: [String: Any]) async throws -> GeminiFoodResult {
        let sb = SupabaseClient.shared
        try await sb.ensureAuth()
        guard let token = sb.accessToken else {
            throw NSError(domain: "Gemini", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in — can't analyze food"])
        }
        let url = URL(string: "\(sb.baseURL)/rest/v1/rpc/\(rpc)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(sb.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: args)
        req.timeoutInterval = 60

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status < 300 else {
                let msg = String(data: data, encoding: .utf8) ?? ""
                sb.logClientError(area: "gemini.\(rpc).http_\(status)", message: msg, context: argsSummary(args))
                throw NSError(domain: "Gemini", code: status, userInfo: [NSLocalizedDescriptionKey: msg])
            }
            return try parseGeminiResponse(data)
        } catch let err where !(err is CancellationError) {
            // transport error (timeout, offline) or parse failure — record it, then rethrow
            if (err as NSError).domain != "Gemini" {
                sb.logClientError(area: "gemini.\(rpc).transport", message: err.localizedDescription, context: argsSummary(args))
            }
            throw err
        }
    }

    /// Compact, PII-light summary of the call args for the error log (no base64 blobs).
    private func argsSummary(_ args: [String: Any]) -> String {
        if let d = args["p_description"] as? String { return "text: \(d.prefix(200))" }
        if let c = args["p_caption"] as? String { return "photo+caption: \(c.prefix(120))" }
        if args["p_image_base64"] != nil { return "photo (no caption)" }
        return ""
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
}
