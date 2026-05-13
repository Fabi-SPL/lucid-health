import SwiftUI
import UIKit

// ─── Shared color recipe (v104) ─────────────────────────────────────────────
//
// Single-color ring — score maps to ONE solid color, no rainbow gradient.
// Premium 6-stop red→green palette tuned by Fabi 2026-05-13:
//   0  → deep saturated red
//   20 → red-orange
//   40 → warm amber
//   60 → yellow-green ⭐ (Fabi's sweet spot)
//   80 → vivid green
//   100 → deep emerald
// Each stop chosen for high chroma — avoids muddy mid-tones that plague raw
// HSL/RGB interpolation. lerpRGB picks the bracketing pair and lerps in
// linear-RGB so the 2-stop hop is short enough to stay clean.

fileprivate let recoveryStops: [(pos: Double, color: Color)] = [
    (0,   Color(red: 0.949, green: 0.231, blue: 0.235)),  // #F23B3C deep saturated red
    (20,  Color(red: 1.000, green: 0.435, blue: 0.235)),  // #FF6F3C red-orange
    (40,  Color(red: 1.000, green: 0.733, blue: 0.224)),  // #FFBB39 warm amber
    (60,  Color(red: 0.706, green: 0.863, blue: 0.275)),  // #B4DC46 yellow-green ⭐
    (80,  Color(red: 0.298, green: 0.804, blue: 0.392)),  // #4CCD64 vivid green
    (100, Color(red: 0.094, green: 0.682, blue: 0.388))   // #18AE63 deep emerald
]

/// Continuously-interpolated recovery color at a given score (0–100).
/// Used by both rings + glow + label color so that 50, 60, and 61 read as
/// distinct colors instead of the discrete-bucket bug Fabi flagged.
fileprivate func recoveryColor(at score: Double) -> Color {
    let s = max(0, min(100, score))
    var lo = recoveryStops[0]
    var hi = recoveryStops[recoveryStops.count - 1]
    for i in 0..<(recoveryStops.count - 1) {
        if s >= recoveryStops[i].pos && s <= recoveryStops[i + 1].pos {
            lo = recoveryStops[i]
            hi = recoveryStops[i + 1]
            break
        }
    }
    let span = hi.pos - lo.pos
    let t = span == 0 ? 0 : (s - lo.pos) / span
    return Color.lerpRGB(from: lo.color, to: hi.color, t: t)
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
