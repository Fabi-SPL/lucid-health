import SwiftUI
import UIKit

// ─── Recovery color recipe (v105) ───────────────────────────────────────────
//
// Continuous HSB curve — every integer score maps to a UNIQUE color so 60
// reads visibly different from 61, 95 reads visibly different from 90, etc.
// No anchor stops, no discrete bucketing.
//
// Hue path (piecewise linear, biased to put yellow-green at 60):
//   score   hue°    color name
//   0       0       deep red
//   30      30      red-orange
//   60      80      yellow-green ⭐ (Fabi's sweet spot)
//   100     140     rich green
//
// Saturation peaks near the warm zone (yellows need high chroma to pop),
// dips slightly at red+green ends to avoid neon-toy feel. Brightness peaks
// around the amber/yellow band where the eye expects max luminance, eases
// down at red (deeper) and green (richer) endpoints.
//
// Per-unit perceptual delta: ~1.3-1.7° hue shift per recovery point, plus
// micro brightness/saturation drift — enough that any two adjacent scores
// read as distinct colors.

fileprivate func recoveryColor(at score: Double) -> Color {
    let s = max(0, min(100, score))

    // Piecewise hue curve in degrees (0-360)
    let hueDeg: Double
    if s <= 30 {
        // 0→30°: red → red-orange (1° per recovery point)
        hueDeg = s * 1.0
    } else if s <= 60 {
        // 30→80°: red-orange → yellow-green (~1.67° per recovery point)
        hueDeg = 30 + (s - 30) * (50.0 / 30.0)
    } else {
        // 80→140°: yellow-green → rich green (1.5° per recovery point)
        hueDeg = 80 + (s - 60) * (60.0 / 40.0)
    }

    // Saturation curve — peak at warm zone, slight ease at endpoints
    // Gaussian bell centered at score=50, width ~30
    let satPeak = 0.92
    let satFloor = 0.78
    let satGauss = exp(-pow((s - 50.0) / 30.0, 2))
    let saturation = satFloor + (satPeak - satFloor) * satGauss

    // Brightness curve — peak in amber zone, deeper at green end for richness
    // Asymmetric: red gets 0.92, yellow zone 0.97, deep green eases to 0.78
    let brightness: Double
    if s < 30 {
        brightness = 0.88 + (s / 30.0) * 0.07              // 0.88 → 0.95
    } else if s < 65 {
        brightness = 0.95 + sin((s - 30) / 35.0 * .pi) * 0.03  // 0.95 → 0.98 → 0.95
    } else {
        brightness = 0.95 - (s - 65) / 35.0 * 0.17         // 0.95 → 0.78
    }

    return Color(hue: hueDeg / 360.0, saturation: saturation, brightness: brightness)
}

/// Tier label for a given score. 5-tier (more granular than red/yellow/green).
fileprivate func recoveryLabel(for score: Double) -> String {
    if score >= 80 { return "PRIME" }
    if score >= 67 { return "STRONG" }
    if score >= 50 { return "OKAY" }
    if score >= 34 { return "LOW" }
    return "DEPLETED"
}

// MARK: - HeroRecoveryRing (classic — no smoke)
//
// Hero recovery ring — 180pt diameter on Today.
// v103 — uses the new 8-stop gradient with yellow-green at 60. Same ring
// structure as v102 (continuous gradient, breathing, numericText transition,
// spring entrance via DS.Anim.ringEntrance).

struct HeroRecoveryRing: View {
    let score: Double      // 0–100
    var size: CGFloat = 180
    var lineWidth: CGFloat = 18

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var breathing = false
    @State private var displayedScore: Double = 0

    private var trimEnd: CGFloat { appeared ? CGFloat(max(0, min(100, score)) / 100.0) : 0 }
    private var scoreColor: Color { recoveryColor(at: score) }
    private var scoreLabel: String { recoveryLabel(for: score) }

    var body: some View {
        ZStack {
            // Track ring (faint hint of current zone)
            Circle()
                .stroke(scoreColor.opacity(0.10), lineWidth: lineWidth)
                .frame(width: size, height: size)

            // Progress arc — SOLID color matched to score (v104 — no rainbow)
            Circle()
                .trim(from: 0, to: trimEnd)
                .stroke(
                    scoreColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .animation(DS.Anim.ringEntrance.delay(0.15), value: appeared)
                .animation(.easeInOut(duration: 0.6), value: scoreColor)
                .statusGlow(scoreColor, intensity: appeared ? 1.0 : 0)

            // Center content
            VStack(spacing: 3) {
                Text("\(Int(displayedScore))")
                    .font(.system(size: size * 0.30, weight: .heavy, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .scaleEffect(breathing ? 1.012 : 1.0)
                    .animation(
                        reduceMotion ? .default : DS.Anim.breath,
                        value: breathing
                    )

                Text(scoreLabel)
                    .font(.system(size: size * 0.075, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor)
                    .tracking(1.8)
                    .textCase(.uppercase)
            }
            .scaleEffect(appeared ? 1.0 : 0.85)
            .opacity(appeared ? 1 : 0)
            .animation(
                reduceMotion ? .default : .spring(response: 0.55, dampingFraction: 0.65).delay(0.15),
                value: appeared
            )
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(DS.Anim.ringEntrance.delay(0.1)) { appeared = true }
            if reduceMotion {
                displayedScore = score
            } else {
                withAnimation(.spring(response: 1.4, dampingFraction: 0.78).delay(0.25)) {
                    displayedScore = score
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    breathing = true
                }
            }
        }
        .onChange(of: score) { _, new in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                displayedScore = new
            }
        }
    }
}

// MARK: - SmokeRecoveryRing (v103 — smoke wisps off the arc tip)
//
// Mode A from the 2026-05-10 concept exploration. Smoke particles use the
// Vortex Smoke recipe ported to pure SwiftUI (TimelineView + Canvas, iOS 17+,
// no SPM dep): start at base size, grow to 2× while opacity fades to zero,
// drift in a 10° upward-tangent cone off the trim tip. Tinted to scoreColor.
// Reduce-motion respected — smoke layer disabled, falls back to classic ring.

private struct SmokeParticle: Identifiable {
    let id = UUID()
    let birth: Date
    let x0: CGFloat
    let y0: CGFloat
    let vx: CGFloat        // px/sec
    let vy: CGFloat
    let size0: CGFloat
    let size1: CGFloat     // size at end-of-life (Vortex sizeMultiplierAtDeath = 2×)
}

struct SmokeRecoveryRing: View {
    let score: Double
    var size: CGFloat = 180
    var lineWidth: CGFloat = 18

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var breathing = false
    @State private var displayedScore: Double = 0
    @State private var particles: [SmokeParticle] = []
    @State private var lastTick: Date = Date()
    @State private var spawnAccumulator: Double = 0

    // Vortex Smoke parameters (matched 1:1 to the concept HTML)
    private let spawnRate: Double = 22       // particles per second
    private let lifespan: TimeInterval = 3.0
    private let baseSize: CGFloat = 14
    private let driftSpeed: CGFloat = 14     // px/sec
    private let coneRadians: Double = .pi / 18  // 10° cone

    // Render the smoke in an over-sized canvas so particles can drift beyond
    // the ring's bounds without clipping. Layout still uses `size`.
    private let canvasInflation: CGFloat = 1.55

    private var trimEnd: CGFloat { appeared ? CGFloat(max(0, min(100, score)) / 100.0) : 0 }
    private var ringRadius: CGFloat { (size / 2) - (lineWidth / 2) }
    private var scoreColor: Color { recoveryColor(at: score) }
    private var scoreLabel: String { recoveryLabel(for: score) }

    var body: some View {
        ZStack {
            // ── Smoke layer (iOS 17+ TimelineView + Canvas, 30 Hz) ────────
            if !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tlContext in
                    Canvas { ctx, _ in
                        let now = tlContext.date
                        for p in particles {
                            let age = now.timeIntervalSince(p.birth)
                            guard age >= 0, age <= lifespan else { continue }
                            let t = CGFloat(age / lifespan)
                            let x = p.x0 + p.vx * CGFloat(age)
                            // small upward buoyancy (smoke rises)
                            let y = p.y0 + p.vy * CGFloat(age) - 6 * CGFloat(age)
                            let radius = p.size0 + (p.size1 - p.size0) * t
                            let alpha = (1.0 - Double(t)) * 0.42

                            let shading = GraphicsContext.Shading.radialGradient(
                                Gradient(stops: [
                                    .init(color: scoreColor.opacity(alpha), location: 0),
                                    .init(color: scoreColor.opacity(alpha * 0.5), location: 0.4),
                                    .init(color: scoreColor.opacity(0), location: 1.0)
                                ]),
                                center: CGPoint(x: x, y: y),
                                startRadius: 0,
                                endRadius: max(1, radius)
                            )
                            ctx.fill(
                                Path(ellipseIn: CGRect(
                                    x: x - radius,
                                    y: y - radius,
                                    width: radius * 2,
                                    height: radius * 2
                                )),
                                with: shading
                            )
                        }
                    }
                    .frame(width: size * canvasInflation, height: size * canvasInflation)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
                }
            }

            // ── Track ring ────────────────────────────────────────────────
            Circle()
                .stroke(scoreColor.opacity(0.10), lineWidth: lineWidth)
                .frame(width: size, height: size)

            // ── Progress arc — SOLID color (v104, smoke variant) ──────────
            Circle()
                .trim(from: 0, to: trimEnd)
                .stroke(
                    scoreColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .animation(DS.Anim.ringEntrance.delay(0.15), value: appeared)
                .animation(.easeInOut(duration: 0.6), value: scoreColor)
                .statusGlow(scoreColor, intensity: appeared ? 1.0 : 0)

            // ── Center content ────────────────────────────────────────────
            VStack(spacing: 3) {
                Text("\(Int(displayedScore))")
                    .font(.system(size: size * 0.30, weight: .heavy, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .scaleEffect(breathing ? 1.012 : 1.0)
                    .animation(
                        reduceMotion ? .default : DS.Anim.breath,
                        value: breathing
                    )

                Text(scoreLabel)
                    .font(.system(size: size * 0.075, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor)
                    .tracking(1.8)
                    .textCase(.uppercase)
            }
            .scaleEffect(appeared ? 1.0 : 0.85)
            .opacity(appeared ? 1 : 0)
            .animation(
                reduceMotion ? .default : .spring(response: 0.55, dampingFraction: 0.65).delay(0.15),
                value: appeared
            )
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(DS.Anim.ringEntrance.delay(0.1)) { appeared = true }
            if reduceMotion {
                displayedScore = score
            } else {
                withAnimation(.spring(response: 1.4, dampingFraction: 0.78).delay(0.25)) {
                    displayedScore = score
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    breathing = true
                }
                lastTick = Date()
            }
        }
        .onChange(of: score) { _, new in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                displayedScore = new
            }
        }
        // Smoke simulation tick — separate from TimelineView's redraw cycle so
        // particle state mutation doesn't ride on view re-instantiation.
        .task {
            guard !reduceMotion else { return }
            lastTick = Date()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 33_000_000)  // ~30 Hz
                advanceSmoke(now: Date())
            }
        }
    }

    // ─── Particle simulation ────────────────────────────────────────────────

    private func advanceSmoke(now: Date) {
        let dt = now.timeIntervalSince(lastTick)
        // Guard against background-resume jumps (clamp dt to a single frame)
        guard dt > 0, dt < 0.5 else {
            lastTick = now
            return
        }
        lastTick = now

        spawnAccumulator += dt * spawnRate
        while spawnAccumulator >= 1 {
            particles.append(spawnParticle(now: now))
            spawnAccumulator -= 1
        }

        particles.removeAll { now.timeIntervalSince($0.birth) >= lifespan }

        // Hard cap to defend against any pathological spawn loop
        if particles.count > 80 {
            particles.removeFirst(particles.count - 80)
        }
    }

    private func spawnParticle(now: Date) -> SmokeParticle {
        // Tip angle on the ring: 12 o'clock = -90°, sweep clockwise by score%
        let tipAngle = -.pi / 2 + Double(trimEnd) * 2 * .pi
        // Drift direction: tangent at the tip + variance within upward cone
        let driftAngle = tipAngle + .pi / 2 + Double.random(in: -1...1) * coneRadians
        let speed = driftSpeed * CGFloat.random(in: 0.7...1.3)
        let sizeJitter = CGFloat.random(in: 0.5...1.0)

        // Canvas is over-sized — center it ourselves
        let canvasCenter = (size * canvasInflation) / 2
        let x0 = canvasCenter + cos(tipAngle) * Double(ringRadius)
        let y0 = canvasCenter + sin(tipAngle) * Double(ringRadius)

        return SmokeParticle(
            birth: now,
            x0: CGFloat(x0),
            y0: CGFloat(y0),
            vx: CGFloat(cos(driftAngle)) * speed,
            vy: CGFloat(sin(driftAngle)) * speed,
            size0: baseSize * sizeJitter,
            size1: baseSize * sizeJitter * 2
        )
    }
}

// MARK: - RGB color interpolation helper

fileprivate extension Color {
    /// Linearly interpolate between two SwiftUI Colors in RGB space.
    static func lerpRGB(from a: Color, to b: Color, t: Double) -> Color {
        let clamped = max(0, min(1, t))
        let ua = UIColor(a)
        let ub = UIColor(b)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aA: CGFloat = 1
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, bA: CGFloat = 1
        ua.getRed(&ar, green: &ag, blue: &ab, alpha: &aA)
        ub.getRed(&br, green: &bg, blue: &bb, alpha: &bA)
        let f = CGFloat(clamped)
        return Color(
            red:   Double(ar + (br - ar) * f),
            green: Double(ag + (bg - ag) * f),
            blue:  Double(ab + (bb - ab) * f),
            opacity: Double(aA + (bA - aA) * f)
        )
    }
}

// MARK: - AppStorage-bound ring style
//
// Saved to UserDefaults under "recoveryRingStyle". Settings page exposes the
// picker; TodayView reads via @AppStorage and switches between renderers.

enum RecoveryRingStyle: String, CaseIterable, Identifiable {
    case classic = "classic"
    case smoke   = "smoke"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic: return "Classic"
        case .smoke:   return "Smoke"
        }
    }

    var detail: String {
        switch self {
        case .classic: return "Continuous gradient, no particles"
        case .smoke:   return "Recovery-tinted smoke wisps off the arc tip"
        }
    }
}

#Preview("Classic vs Smoke") {
    ZStack {
        MeshGradientBackground()
        VStack(spacing: 36) {
            HStack(spacing: 28) {
                HeroRecoveryRing(score: 95, size: 140, lineWidth: 14)
                SmokeRecoveryRing(score: 95, size: 140, lineWidth: 14)
            }
            HStack(spacing: 28) {
                HeroRecoveryRing(score: 60, size: 140, lineWidth: 14)
                SmokeRecoveryRing(score: 60, size: 140, lineWidth: 14)
            }
            HStack(spacing: 28) {
                HeroRecoveryRing(score: 22, size: 140, lineWidth: 14)
                SmokeRecoveryRing(score: 22, size: 140, lineWidth: 14)
            }
        }
    }
}

// MARK: - RecoveryTrendStrip
// Lives in this already-compiled file (this project registers every
// Swift file in project.pbxproj by hand; a standalone file wasn't in the
// build target and broke the build). Semantically it belongs with the
// ring anyway — it renders directly beneath it.

/// Compact 14-day recovery trend shown directly under HeroRecoveryRing.
/// The ring shows a single context-free number, so real day-to-day
/// movement (recovery genuinely swings 9-100) was invisible and a
/// correct-but-varying score read as "stuck". This makes it visible.
struct RecoveryTrendStrip: View {
    /// Recovery scores, oldest → newest (server `recovery_score`, NULLs dropped).
    let scores: [Double]

    private var avg: Double {
        guard !scores.isEmpty else { return 0 }
        return scores.reduce(0, +) / Double(scores.count)
    }
    private var today: Double { scores.last ?? 0 }
    private var delta: Int { Int((today - avg).rounded()) }

    var body: some View {
        if scores.count >= 3 {
            VStack(spacing: DS.Spacing.xs) {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(scores.enumerated()), id: \.offset) { idx, s in
                        let isToday = idx == scores.count - 1
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(DS.Colors.recoveryColor(s))
                            .opacity(isToday ? 1.0 : 0.45)
                            .frame(height: barHeight(s))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 34)
                .animation(DS.Anim.cardAppear, value: scores)

                HStack(spacing: 4) {
                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("\(delta >= 0 ? "+" : "")\(delta) vs \(scores.count)-day avg")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(delta >= 0 ? DS.Colors.teal : DS.Colors.danger)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Recovery \(Int(today)), \(delta >= 0 ? "up" : "down") \(abs(delta)) versus your \(scores.count) day average")
        }
    }

    /// Map score 0-100 to a 6-34pt bar so even a low day stays visible.
    private func barHeight(_ s: Double) -> CGFloat {
        let clamped = max(0, min(100, s))
        return 6 + CGFloat(clamped / 100) * 28
    }
}

// MARK: - AlcoholNightChip (v106)
//
// Subtle chip under the recovery ring on alcohol nights. Frames a low score
// as honest signal ("your body is hungover, not the app is broken") rather
// than alarm. Single-line, muted color, low-emphasis treatment per the
// lucid-design "no alarming red" principle.
struct AlcoholNightChip: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("🍺")
                .font(.system(size: 14))
            Text("Alcohol night detected")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.textSecondary)
            Spacer()
            Text("Score is honest")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(DS.Colors.textMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Colors.surfaceElevated.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(DS.Colors.textFaint.opacity(0.18), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Alcohol night detected. Score is honest.")
    }
}
