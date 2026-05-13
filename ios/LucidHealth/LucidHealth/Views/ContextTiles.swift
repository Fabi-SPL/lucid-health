import SwiftUI

// MARK: - Context Tiles
// Two read-only tiles that surface external context onto the health canvas:
//   • WeatherContextTile — daily snapshot from open-meteo (Vercel cron)
//   • PCActivityTile     — today's foreground apps (lucid-pc-bridge → Supabase)
//
// Both are quiet by default. They only animate in when data exists.
// No hand-rolled tokens — uses DS.* + .glassDefault().

// ════════════════════════════════════════════════════════════════
// MARK: - WeatherContextTile (Today / Insights)
// ════════════════════════════════════════════════════════════════

struct WeatherContextTile: View {
    @State private var weather: ExperimentalFeaturesService.WeatherDay?
    @State private var isLoaded = false

    var body: some View {
        Group {
            if let w = weather {
                content(w)
            } else if isLoaded {
                EmptyView()
            } else {
                EmptyView()
            }
        }
        .task { await load() }
    }

    private func load() async {
        weather = await ExperimentalFeaturesService.shared.fetchTodayWeather()
        isLoaded = true
    }

    @ViewBuilder
    private func content(_ w: ExperimentalFeaturesService.WeatherDay) -> some View {
        HStack(spacing: DS.Spacing.md) {
            // Glyph
            Image(systemName: iconForCode(w.conditions_code))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(DS.Colors.teal)
                .frame(width: 36, height: 36)
                .symbolRenderingMode(.hierarchical)

            // Primary line — temp + label
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let avg = w.temp_avg_c {
                        Text(String(format: "%.0f°", avg))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.Colors.textPrimary)
                            .monospacedDigit()
                    }
                    if let label = w.conditions_label {
                        Text(label.capitalized)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(DS.Colors.textSecondary)
                    }
                }
                // Secondary — only the metric most likely to predict bad recovery
                if let pressure = w.pressure_hpa {
                    let drop = w.pressure_change_hpa ?? 0
                    let dropText = drop <= -3 ? String(format: " · %.0f hPa drop", drop) : ""
                    Text(String(format: "%.0f hPa", pressure) + dropText)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(drop <= -3 ? DS.Colors.amber : DS.Colors.textMuted)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: DS.Spacing.sm)

            // Tertiary — daylight + UV (compact stack)
            VStack(alignment: .trailing, spacing: 2) {
                if let daylight = w.daylight_min {
                    let h = daylight / 60
                    let m = daylight % 60
                    Text(String(format: "%dh %02dm", h, m))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.textSecondary)
                        .monospacedDigit()
                } else {
                    Text("—")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(DS.Colors.textFaint)
                }
                Text("daylight")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(DS.Colors.textFaint)
                    .tracking(0.6)
            }
        }
        .padding(DS.Spacing.md)
        .glassDefault()
    }

    private func iconForCode(_ code: Int?) -> String {
        guard let c = code else { return "thermometer.medium" }
        if c == 0 { return "sun.max" }
        if c <= 2 { return "cloud.sun" }
        if c == 3 { return "cloud" }
        if c <= 48 { return "cloud.fog" }
        if c <= 67 { return "cloud.rain" }
        if c <= 77 { return "cloud.snow" }
        if c <= 82 { return "cloud.heavyrain" }
        if c <= 86 { return "cloud.snow" }
        return "cloud.bolt.rain"
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - PCActivityTile (Insights, optional Today)
// ════════════════════════════════════════════════════════════════

struct PCActivityTile: View {
    @State private var rollup: [ExperimentalFeaturesService.PCAppRollup] = []
    @State private var nowApp: ExperimentalFeaturesService.PCNowSnapshot?
    @State private var isLoaded = false

    private var totalMinutes: Int { rollup.reduce(0) { $0 + $1.minutes } }
    private var top: [ExperimentalFeaturesService.PCAppRollup] { Array(rollup.prefix(4)) }

    var body: some View {
        Group {
            if isLoaded && rollup.isEmpty && nowApp == nil {
                // Bridge not running — silently hide
                EmptyView()
            } else if isLoaded {
                content
            } else {
                EmptyView()
            }
        }
        .task { await load() }
    }

    private func load() async {
        async let r = ExperimentalFeaturesService.shared.fetchPCDailySummary()
        async let n = ExperimentalFeaturesService.shared.fetchPCNow()
        rollup = await r
        nowApp = await n
        isLoaded = true
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            // Header line
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Colors.violet)
                Text("ON PC TODAY")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DS.Colors.textFaint)
                    .tracking(0.8)
                Spacer()
                Text("\(totalMinutes / 60)h \(totalMinutes % 60)m")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.textSecondary)
                    .monospacedDigit()
            }

            // Now line — only if a session is open
            if let n = nowApp {
                HStack(spacing: 6) {
                    Circle()
                        .fill(DS.Colors.success)
                        .frame(width: 6, height: 6)
                    Text("now: \(n.app ?? prettyExe(n.exe))")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(DS.Colors.textSecondary)
                        .lineLimit(1)
                }
            }

            // Stacked horizontal bar — categories
            if totalMinutes > 0 {
                CategoryBar(rows: top, total: max(totalMinutes, 1))
                    .frame(height: 8)
            }

            // Top-4 rows
            VStack(spacing: 6) {
                ForEach(top) { row in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(colorForCategory(row.category))
                            .frame(width: 6, height: 6)
                        Text(row.app)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.Colors.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let hr = row.avg_hr, hr > 0 {
                            Text(String(format: "%.0f bpm", hr))
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(DS.Colors.textMuted)
                                .monospacedDigit()
                        }
                        Text("\(row.minutes)m")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.Colors.textSecondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(DS.Spacing.md)
        .glassDefault()
    }

    private func prettyExe(_ exe: String) -> String {
        exe.replacingOccurrences(of: ".exe", with: "")
    }

    fileprivate static func colorForCategory(_ c: String) -> Color {
        switch c {
        case "code":     return DS.Colors.teal
        case "creative": return DS.Colors.violet
        case "game":     return DS.Colors.amber
        case "browser":  return DS.Colors.textSecondary
        case "comm":     return DS.Colors.pink
        case "media":    return DS.Colors.violet.opacity(0.6)
        case "work":     return DS.Colors.teal.opacity(0.7)
        default:         return DS.Colors.textFaint
        }
    }

    private func colorForCategory(_ c: String) -> Color { Self.colorForCategory(c) }
}

// MARK: - Category Bar (stacked horizontal)

private struct CategoryBar: View {
    let rows: [ExperimentalFeaturesService.PCAppRollup]
    let total: Int

    private var grouped: [(String, Int)] {
        var bins: [String: Int] = [:]
        for r in rows { bins[r.category, default: 0] += r.minutes }
        return bins.sorted { $0.value > $1.value }
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(grouped, id: \.0) { (cat, mins) in
                    let frac = CGFloat(mins) / CGFloat(total)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(PCActivityTile.colorForCategory(cat))
                        .frame(width: max(geo.size.width * frac - 2, 0))
                }
            }
        }
    }
}
