import SwiftUI

// ════════════════════════════════════════════════════════════
// Lucid Design System — Single source of truth for all UI
// Based on: Lucid brand system + research spec (02-design-system-spec.html)
//
// Rules:
//   - Never use raw Color literals (.gray, .red) — always DS.Colors.*
//   - Never use raw font sizes — always DS.Font.*
//   - Never use raw padding values — always DS.Spacing.*
//   - Every card uses GlassCard or HeroCard modifier
//   - Background is always MeshGradientBackground, never Color.black
// ════════════════════════════════════════════════════════════

enum DS {
    // MARK: - Spacing (8-point grid)
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Corner Radius
    enum Radius {
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let pill: CGFloat = 100
    }

    // MARK: - Colors (Lucid Brand — adaptive light/dark)
    enum Colors {
        // Backgrounds
        static let bg = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.031, green: 0.027, blue: 0.051, alpha: 1)    // #08070d Aurora
                : UIColor(red: 0.945, green: 0.941, blue: 0.965, alpha: 1)    // #f1f0f6 Aurora
        })
        static let surface = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.04)
                : UIColor(white: 1.0, alpha: 0.65)
        })
        static let surfaceElevated = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.07)
                : UIColor(white: 1.0, alpha: 0.80)
        })
        static let surfaceStrong = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.10)
                : UIColor(white: 1.0, alpha: 0.90)
        })

        // AURORA card surfaces — translucent dark over the glow (lets the violet
        // bleed through subtly) in dark, solid white in light. NO glass, NO blur,
        // NO reflection. Depth = luminance + 1px border.
        static let cardFill = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.086, green: 0.078, blue: 0.133, alpha: 0.55) // ~#161422 @55%
                : UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)        // #ffffff
        })
        static let cardFillElevated = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.106, green: 0.098, blue: 0.157, alpha: 0.72) // ~#1b1928 @72%
                : UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)        // #ffffff
        })
        /// Aurora glow — the ONE soft violet radial behind everything (top-center).
        static let glow = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.545, green: 0.486, blue: 0.965, alpha: 0.30) // violet @30%
                : UIColor(red: 0.486, green: 0.361, blue: 0.749, alpha: 0.16) // violet @16%
        })
        /// Empty ring / bar track (Aurora) — what unfilled chart segments sit on.
        static let track = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.10)
                : UIColor(red: 0.902, green: 0.894, blue: 0.933, alpha: 1) // #e6e4ee
        })

        // Text
        static let textPrimary = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.91, green: 0.89, blue: 0.94, alpha: 1)       // #e8e4ef
                : UIColor(red: 0.10, green: 0.09, blue: 0.15, alpha: 1)       // #1a1625
        })
        static let textSecondary = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.69, green: 0.68, blue: 0.75, alpha: 1)       // #b0adc0
                : UIColor(red: 0.23, green: 0.22, blue: 0.35, alpha: 1)       // #3a3858
        })
        static let textMuted = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.42, green: 0.41, blue: 0.50, alpha: 1)       // #6b6880
                : UIColor(red: 0.42, green: 0.41, blue: 0.53, alpha: 1)       // #6b6888
        })
        static let textFaint = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.29, green: 0.28, blue: 0.38, alpha: 1)       // #4a4760
                : UIColor(red: 0.60, green: 0.60, blue: 0.66, alpha: 1)       // #9a98a8
        })

        // Accent (adaptive violet/teal)
        static let violet = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.545, green: 0.486, blue: 0.965, alpha: 1)    // #8B7CF6
                : UIColor(red: 0.486, green: 0.361, blue: 0.749, alpha: 1)    // #7c5cbf
        })
        static let teal = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.310, green: 0.820, blue: 0.773, alpha: 1)    // #4FD1C5
                : UIColor(red: 0.051, green: 0.580, blue: 0.533, alpha: 1)    // #0d9488
        })

        // Semantic (adaptive)
        static let success = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.063, green: 0.725, blue: 0.506, alpha: 1)    // #10b981
                : UIColor(red: 0.020, green: 0.588, blue: 0.412, alpha: 1)    // #059669
        })
        static let danger = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.937, green: 0.267, blue: 0.267, alpha: 1)    // #ef4444
                : UIColor(red: 0.863, green: 0.149, blue: 0.149, alpha: 1)    // #dc2626
        })
        static let warning = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.984, green: 0.749, blue: 0.141, alpha: 1)    // #fbbf24
                : UIColor(red: 0.851, green: 0.467, blue: 0.024, alpha: 1)    // #d97706
        })

        static let pink = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.925, green: 0.282, blue: 0.600, alpha: 1)    // #EC4899
                : UIColor(red: 0.780, green: 0.157, blue: 0.478, alpha: 1)    // #c7287a
        })
        static let amber = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.965, green: 0.624, blue: 0.044, alpha: 1)    // #F59E0B
                : UIColor(red: 0.851, green: 0.467, blue: 0.024, alpha: 1)    // #d97706
        })

        // Borders (adaptive)
        static let border = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.08)
                : UIColor(white: 0.0, alpha: 0.06)
        })
        static let borderStrong = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.545, green: 0.361, blue: 0.965, alpha: 0.15)
                : UIColor(red: 0.486, green: 0.361, blue: 0.749, alpha: 0.15)
        })
        // Adaptive accent borders (were fixed dark-mode hex — invisible-ish in light)
        static let borderViolet = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.545, green: 0.486, blue: 0.965, alpha: 0.18)
                : UIColor(red: 0.486, green: 0.361, blue: 0.749, alpha: 0.22)
        })
        static let borderTeal = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.310, green: 0.820, blue: 0.773, alpha: 0.15)
                : UIColor(red: 0.051, green: 0.580, blue: 0.533, alpha: 0.20)
        })

        /// Shimmer/specular highlight — white reads on dark glass, but is
        /// invisible white-on-white in light mode. Violet-tinted there instead.
        static let shimmer = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 1.0)
                : UIColor(red: 0.486, green: 0.361, blue: 0.749, alpha: 1.0)
        })

        // Recovery zones
        static func recoveryColor(_ score: Double) -> Color {
            if score >= 67 { return success }
            if score >= 34 { return warning }
            return danger
        }

        static func sleepColor(_ score: Double) -> Color {
            if score >= 70 { return success }
            if score >= 40 { return warning }
            return danger
        }

        static func strainColor(_ score: Double) -> Color {
            if score < 8 { return teal }
            if score < 14 { return warning }
            return danger
        }

        static func bodyBatteryColor(_ level: Double) -> Color {
            if level >= 60 { return success }
            if level >= 30 { return warning }
            return danger
        }

        static func readinessColor(_ readiness: HealthEngine.ReadinessLevel) -> Color {
            switch readiness {
            case .green: return success
            case .yellow: return warning
            case .red: return danger
            case .unknown: return textMuted
            }
        }

        static func zoneColor(_ zone: Int) -> Color {
            switch zone {
            case 0: return textMuted
            case 1: return teal
            case 2: return success
            case 3: return warning
            case 4: return danger
            default: return textMuted
            }
        }

        static func stageColor(_ stage: HealthEngine.SleepStage) -> Color {
            switch stage {
            case .awake: return warning
            case .light: return Color(hex: 0xFDE68A) // soft yellow
            case .deep: return teal
            case .rem: return violet
            }
        }

        static func mindColor(_ score: Double) -> Color {
            if score >= 10 { return success }
            if score >= 6  { return teal }
            if score >= 3  { return warning }
            return danger
        }

        static func novaColor(_ nova: Double) -> Color {
            switch Int(nova.rounded()) {
            case 1: return success
            case 2: return teal
            case 3: return warning
            default: return danger
            }
        }

        // Gradient
        static let brandGradient = LinearGradient(
            colors: [violet, teal],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let heroGradient = LinearGradient(
            colors: [violet.opacity(0.12), teal.opacity(0.06)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        // Status glow halos (used by StatusGlow modifier)
        static let glowViolet  = violet.opacity(0.35)
        static let glowSuccess = success.opacity(0.30)
        static let glowAmber   = warning.opacity(0.30)
        static let glowDanger  = danger.opacity(0.30)

        // Category dots (principle #5)
        static let categoryBody  = violet
        static let categoryMind  = teal
        static let categoryCare  = amber
        static let categorySleep = Color(hex: 0xA78BFA)  // soft lavender
        static let categoryFood  = success
    }

    // MARK: - Typography
    // Sized for iPhone 15 Pro (393pt wide). Uses .rounded design.
    // Switch to Font.custom("Outfit", ...) when font is bundled.
    enum Font {
        static let display = SwiftUI.Font.system(size: 28, weight: .heavy, design: .rounded)
        static let title1 = SwiftUI.Font.system(size: 22, weight: .heavy, design: .rounded)
        static let title2 = SwiftUI.Font.system(size: 18, weight: .bold, design: .rounded)
        static let title3 = SwiftUI.Font.system(size: 15, weight: .semibold, design: .rounded)
        static let body = SwiftUI.Font.system(size: 14, weight: .regular)
        static let bodyMed = SwiftUI.Font.system(size: 14, weight: .medium)
        static let caption = SwiftUI.Font.system(size: 12, weight: .regular)
        static let label = SwiftUI.Font.system(size: 10, weight: .bold)
        static let micro = SwiftUI.Font.system(size: 8, weight: .bold)

        // Numeric — sized for 393pt width
        static let heroNumber = SwiftUI.Font.system(size: 44, weight: .heavy, design: .rounded)
        static let bigNumber = SwiftUI.Font.system(size: 24, weight: .bold, design: .rounded)
        static let scoreNumber = SwiftUI.Font.system(size: 20, weight: .heavy, design: .rounded)
        static let statNumber = SwiftUI.Font.system(size: 16, weight: .bold, design: .rounded)
    }

    // MARK: - Animations
    // Smoothness pass (2026-06-01): higher damping = no overshoot wobble on UI
    // transitions (Emil rule: ease-out, no bounce for functional motion). Every
    // card-appear / stagger / state change across all 14 screens flows through
    // these, so tuning here smooths the whole app at once.
    enum Anim {
        static let standard = Animation.spring(response: 0.34, dampingFraction: 0.86)
        static let bouncy = Animation.spring(response: 0.4, dampingFraction: 0.7)
        /// Snappy ease-out for taps / toggles — instant-feeling feedback.
        static let quick = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)
        /// Smooth ease-out-quint for content swaps (numbers, text, opacity).
        static let smooth = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.5)
        static let ringFill = Animation.spring(response: 0.85, dampingFraction: 0.82)
        static let countUp = Animation.spring(response: 0.9, dampingFraction: 0.85)
        /// Card entrance — smooth settle, no visible bounce.
        static let cardAppear = Animation.spring(response: 0.46, dampingFraction: 0.85)
        /// Gentle 4s breathing loop for live-data anchors (recovery ring steady-state)
        static let breath = Animation.easeInOut(duration: 4.0).repeatForever(autoreverses: true)
        /// Hero ring fill entrance — slower spring, more drama
        static let ringEntrance = Animation.spring(response: 1.2, dampingFraction: 0.8)

        /// Staggered delay for list items. Capped at 8 so long lists don't drag
        /// the last cards in noticeably late (was a jank tell on Settings/Health).
        static func stagger(index: Int) -> Animation {
            cardAppear.delay(Double(min(index, 8)) * 0.05)
        }
    }

    // MARK: - Glow Colors (status halos)
    enum Glow {
        static let violet = DS.Colors.violet.opacity(0.35)
        static let success = DS.Colors.success.opacity(0.30)
        static let amber = DS.Colors.amber.opacity(0.30)
        static let danger = DS.Colors.danger.opacity(0.30)
    }

    // MARK: - Haptics (one vocabulary, app-wide)
    // Four verbs only. Every interactive surface speaks the same touch language:
    //   tap     — navigation, chips, toggles, anything light
    //   commit  — state-changing actions (start/end/save-intent/wake)
    //   success — a save/write confirmed
    //   error   — a save/write failed
    //   select  — tab/segment selection (UISelectionFeedback)
    enum Haptic {
        static func tap()     { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        static func commit()  { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        static func error()   { UINotificationFeedbackGenerator().notificationOccurred(.error) }
        static func select()  { UISelectionFeedbackGenerator().selectionChanged() }
    }

    // MARK: - Category dot colors (principle #5)
    enum Category {
        case body, mind, care, sleep, food

        var color: Color {
            switch self {
            case .body:  return DS.Colors.violet
            case .mind:  return DS.Colors.teal
            case .care:  return DS.Colors.amber
            case .sleep: return Color(hex: 0xA78BFA)  // soft lavender
            case .food:  return DS.Colors.success
            }
        }

        var label: String {
            switch self {
            case .body:  return "BODY"
            case .mind:  return "MIND"
            case .care:  return "CARE"
            case .sleep: return "SLEEP"
            case .food:  return "FOOD"
            }
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}

// MARK: - Aurora Background (the LIVING canvas)
// Solid bg + ONE soft violet glow. When given `recovery`, the glow becomes
// ALIVE: it breathes (period paced by recovery), its intensity tracks how
// recovered the body is (depleted = dim/cool, charged = luminous + teal life),
// and it drifts lower/higher with the circadian phase of the day. nil recovery
// = the calm static glow (sheets, previews). No mesh, no reflections.
struct AuroraBackground: View {
    /// 0–100. nil = static calm glow (transient sheets keep the still canvas).
    var recovery: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let rec = recovery, rec > 0, !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { ctx in
                livingGlow(recovery: rec, date: ctx.date, breathing: true)
            }
        } else if let rec = recovery, rec > 0 {
            livingGlow(recovery: rec, date: Date(), breathing: false)
        } else {
            staticGlow
        }
    }

    private var staticGlow: some View {
        ZStack {
            DS.Colors.bg.ignoresSafeArea()
            RadialGradient(
                gradient: Gradient(colors: [DS.Colors.glow, DS.Colors.glow.opacity(0)]),
                center: UnitPoint(x: 0.5, y: -0.05),
                startRadius: 0,
                endRadius: 520
            )
            .ignoresSafeArea()
        }
    }

    private func livingGlow(recovery: Double, date: Date, breathing: Bool) -> some View {
        let rec = max(0.0, min(1.0, recovery / 100.0))
        let period = 7.0 - rec * 2.5                      // depleted breathes slow (~7s), charged fast (~4.5s)
        let breath = breathing ? sin(date.timeIntervalSinceReferenceDate / period * 2 * .pi) : 0.0
        let opacity = max(0.0, min(1.0, (0.5 + rec * 0.5) + breath * 0.09))
        let radius: CGFloat = 500 + CGFloat(breath) * 30
        let hour = Calendar.current.component(.hour, from: date)
        let dayPhase = 0.5 - 0.5 * cos(Double((hour + 21) % 24) / 24.0 * 2 * .pi)  // 0 at ~3am, 1 at ~3pm
        let yCenter = -0.10 + (1 - dayPhase) * 0.08      // sits lower at night
        let tealMix = rec * (0.4 + dayPhase * 0.35)      // teal life only when charged + daytime
        return ZStack {
            DS.Colors.bg.ignoresSafeArea()
            RadialGradient(
                gradient: Gradient(colors: [DS.Colors.glow.opacity(opacity), DS.Colors.glow.opacity(0)]),
                center: UnitPoint(x: 0.5, y: yCenter),
                startRadius: 0,
                endRadius: radius
            )
            .ignoresSafeArea()
            RadialGradient(
                gradient: Gradient(colors: [DS.Colors.teal.opacity(0.12 * tealMix), .clear]),
                center: UnitPoint(x: 0.5, y: yCenter + 0.02),
                startRadius: 0,
                endRadius: radius * 0.82
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - Mesh Gradient Background (iOS 18+ MeshGradient, animated) — LEGACY, unused
struct MeshGradientBackground: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    // Animate mesh control points for ambient life (20s loop)
    @State private var phase: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 99999 : 1.0 / 12.0)) { context in
            let t = reduceMotion ? 0.0 : context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 20.0) / 20.0
            let drift = Float(sin(t * .pi * 2) * 0.04)
            let drift2 = Float(cos(t * .pi * 2) * 0.05)

            ZStack {
                DS.Colors.bg.ignoresSafeArea()

                if colorScheme == .dark {
                    // PURPLE-ONLY (no teal). Soft violet base anchors + two
                    // drifting violet "clouds" at different scales — gives the
                    // background organic depth that glass surfaces actually
                    // refract against. Uniform black = flat gray cards.
                    //
                    // Anchors are deep purple-black (#0A0612 / #100A1F) instead
                    // of pure black so the dark mode reads as "lucid violet"
                    // not "void". Less harsh on the eyes at night.
                    MeshGradient(
                        width: 3, height: 3,
                        points: [
                            [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                            [0.0, 0.5], [0.32 + drift, 0.22 + drift * 0.5], [1.0, 0.5],
                            [0.0, 1.0], [0.68 - drift, 0.78 - drift * 0.5], [1.0, 1.0]
                        ],
                        colors: [
                            Color(hex: 0x0A0612), Color(hex: 0x0F0A1F), Color(hex: 0x0A0612),
                            Color(hex: 0x0F0A1F), DS.Colors.violet.opacity(0.32), Color(hex: 0x0F0A1F),
                            Color(hex: 0x0A0612), Color(hex: 0x12082A).opacity(0.95), Color(hex: 0x0A0612)
                        ]
                    )
                    .ignoresSafeArea()
                    // Second violet cloud — slower drift, different position,
                    // larger soft bloom. Stacked via .screen blend so it
                    // brightens rather than replaces.
                    MeshGradient(
                        width: 2, height: 2,
                        points: [
                            [0.15 + drift2 * 0.5, 0.30 + drift2 * 0.3],
                            [0.85, 0.20],
                            [0.20, 0.75 - drift2 * 0.3],
                            [0.80 - drift2 * 0.5, 0.85]
                        ],
                        colors: [
                            DS.Colors.violet.opacity(0.20),
                            Color.clear,
                            Color.clear,
                            DS.Colors.violet.opacity(0.16)
                        ]
                    )
                    .ignoresSafeArea()
                    .blendMode(.screen)
                    // Subtle warmth — soft pink-violet bloom in the center,
                    // pulses gently with drift. Adds painterly feel without
                    // introducing teal.
                    MeshGradient(
                        width: 2, height: 2,
                        points: [[0.0, 0.0], [1.0, 0.0], [0.0, 1.0], [1.0, 1.0]],
                        colors: [
                            Color(hex: 0xB57BFF).opacity(0.00),
                            Color(hex: 0xB57BFF).opacity(0.00),
                            Color(hex: 0xB57BFF).opacity(0.00),
                            Color(hex: 0xB57BFF).opacity(0.06 + Double(abs(drift)) * 0.2)
                        ]
                    )
                    .ignoresSafeArea()
                    .blendMode(.screen)
                } else {
                    // Light mode — purple-only. Darker lavender than before
                    // (#D6C5E8 base) so the background actually exists visually
                    // instead of disappearing into white. Two cloud layers
                    // composited via opacity (NOT .multiply — that was causing
                    // Color.clear corners to wipe the base back to white).
                    MeshGradient(
                        width: 3, height: 3,
                        points: [
                            [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                            [0.0, 0.5], [0.25 + drift, 0.25 + drift * 0.5], [1.0, 0.5],
                            [0.0, 1.0], [0.75 - drift, 0.65 - drift * 0.5], [1.0, 1.0]
                        ],
                        colors: [
                            Color(hex: 0xD6C5E8), Color(hex: 0xDBC9EC), Color(hex: 0xD6C5E8),
                            Color(hex: 0xDBC9EC), DS.Colors.violet.opacity(0.42), Color(hex: 0xDBC9EC),
                            Color(hex: 0xD0BEE3), Color(hex: 0xC9B5DD), Color(hex: 0xD0BEE3)
                        ]
                    )
                    .ignoresSafeArea()
                    // Second cloud — uses lavender base instead of Color.clear
                    // for the non-bloom corners so layering doesn't clip
                    // through to the underlying DS.Colors.bg (near-white).
                    // Lower overall opacity instead of blend mode tricks.
                    MeshGradient(
                        width: 2, height: 2,
                        points: [
                            [0.20 + drift2 * 0.4, 0.30 + drift2 * 0.3],
                            [0.85, 0.18],
                            [0.18, 0.78 - drift2 * 0.3],
                            [0.82 - drift2 * 0.4, 0.85]
                        ],
                        colors: [
                            DS.Colors.violet.opacity(0.35),
                            Color(hex: 0xD6C5E8),
                            Color(hex: 0xD6C5E8),
                            DS.Colors.violet.opacity(0.28)
                        ]
                    )
                    .opacity(0.55)
                    .ignoresSafeArea()
                }

                // Dot grid overlay — gives glass cards something to refract
                // (uniform mesh = flat-looking glass). 24pt spacing, 1.5pt dots.
                // Visible but minimalist — Apple Settings background pattern.
                DotGridOverlay()
            }
        }
    }
}

// MARK: - Dot Grid Overlay

/// Static dot grid used by MeshGradientBackground. The whole point: glass
/// surfaces need high-frequency content underneath to refract visibly,
/// otherwise they look like flat gray boxes.
struct DotGridOverlay: View {
    @Environment(\.colorScheme) var colorScheme
    var spacing: CGFloat = 24
    var dotSize: CGFloat = 1.5

    var body: some View {
        Canvas { context, size in
            // Tinted toward violet (not pure white/black) so the grid
            // integrates with the purple-only palette instead of fighting it.
            let color: Color = colorScheme == .dark
                ? Color(hex: 0xC0A8E8).opacity(0.10)
                : Color(hex: 0x4A3870).opacity(0.12)
            let cols = Int(size.width / spacing) + 2
            let rows = Int(size.height / spacing) + 2
            for row in 0..<rows {
                for col in 0..<cols {
                    let x = CGFloat(col) * spacing
                    let y = CGFloat(row) * spacing
                    let rect = CGRect(
                        x: x - dotSize / 2,
                        y: y - dotSize / 2,
                        width: dotSize,
                        height: dotSize
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Liquid Glass — 4 Tier System (iOS 26 .glassEffect API)

/// Tier 1 — Subtle: list rows, nested cells (16px radius)
struct GlassSubtle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(DS.Colors.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Colors.border, lineWidth: 0.5)
            )
    }
}

/// Tier 2 — Default: standard cards (20px radius) with inner shimmer top edge
struct GlassDefault: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(DS.Colors.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(DS.Colors.border, lineWidth: 0.5)
            )
    }
}

/// Tier 3 — Hero: ONE per page, gradient tint + specular shimmer + halo glow (24px radius)
struct GlassHero: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .fill(DS.Colors.cardFillElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .stroke(DS.Colors.border, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 4)
    }
}

/// Tier 4 — Pill: chips, tabs, FABs (100px / capsule)
struct GlassPill: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Capsule().fill(DS.Colors.cardFillElevated))
            .overlay(Capsule().stroke(DS.Colors.border, lineWidth: 0.5))
    }
}

// MARK: - Convenience extension for 4 glass tiers
extension View {
    func glassSubtle()  -> some View { modifier(GlassSubtle()) }
    func glassDefault() -> some View { modifier(GlassDefault()) }
    func glassHero()    -> some View { modifier(GlassHero()) }
    func glassPill()    -> some View { modifier(GlassPill()) }

    /// Subtle scale + opacity falloff as a section leaves the viewport.
    /// Keeps cards feeling alive without the "obvious AI animation" tell.
    /// Use only on top-level scroll sections, not on every nested element.
    func scrollSectionTransition() -> some View {
        scrollTransition { content, phase in
            content
                .scaleEffect(phase.isIdentity ? 1.0 : 0.96)
                .opacity(phase.isIdentity ? 1.0 : 0.65)
        }
    }
}

// MARK: - Status Glow Modifier

struct StatusGlowModifier: ViewModifier {
    let color: Color
    var intensity: Double

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.35 * intensity), radius: 20, x: 0, y: 0)
            .shadow(color: color.opacity(0.20 * intensity), radius: 40, x: 0, y: 0)
    }
}

extension View {
    func statusGlow(_ color: Color, intensity: Double = 1.0) -> some View {
        modifier(StatusGlowModifier(color: color, intensity: intensity))
    }
}

// MARK: - Glass Card (Liquid Glass on iOS 26, material fallback on 17-18)

struct GlassCard: ViewModifier {
    var padding: CGFloat = DS.Spacing.md
    var radius: CGFloat = DS.Radius.lg
    var tint: Color = DS.Colors.violet
    var tintOpacity: Double = 0.08

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(DS.Colors.cardFill)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(DS.Colors.border, lineWidth: 0.5)
            )
    }
}

/// Accent glass card — a standard glass card tinted by a status color. For cards
/// that carry meaning through color (wake-coach verdict, smart-alarm enabled,
/// last-night signal). Same glass DNA as every other card so accent surfaces stop
/// reading as a bolted-on different app. Caller keeps its own content padding.
struct AccentGlassCard: ViewModifier {
    var tint: Color
    var active: Bool = true
    var radius: CGFloat = DS.Radius.lg

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(DS.Colors.cardFill)
            )
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tint.opacity(active ? 0.07 : 0.0))
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(tint.opacity(active ? 0.32 : 0.12), lineWidth: active ? 1.0 : 0.5)
            )
    }
}

struct HeroCard: ViewModifier {
    var color: Color = DS.Colors.violet

    func body(content: Content) -> some View {
        content
            .padding(DS.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .fill(DS.Colors.cardFillElevated)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .stroke(DS.Colors.border, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 4)
    }
}

/// Specular shimmer overlay — diagonal light sweep across the hero card every
/// 6 seconds. Per Lucid Design Bundle Tier 3 hero spec. Respects reduce-motion.
struct SpecularShimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let phase = (context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 6.0)) / 6.0
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: DS.Colors.shimmer.opacity(0.08), location: 0.48),
                            .init(color: DS.Colors.shimmer.opacity(0.16), location: 0.50),
                            .init(color: DS.Colors.shimmer.opacity(0.08), location: 0.52),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: geo.size.width * 0.45)
                    .offset(x: -geo.size.width + (geo.size.width * 2.45 * CGFloat(phase)))
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
                .opacity(0.55)
            }
        }
    }
}

extension View {
    func glassCard(
        padding: CGFloat = DS.Spacing.md,
        elevated: Bool = false,
        tint: Color? = nil
    ) -> some View {
        modifier(GlassCard(
            padding: padding,
            tint: tint ?? DS.Colors.violet,
            tintOpacity: tint != nil ? 0.08 : 0.04
        ))
    }

    func heroCard(color: Color = DS.Colors.violet) -> some View {
        modifier(HeroCard(color: color))
    }

    /// Status-tinted glass card (wake coach, smart alarm, last-night). Caller
    /// supplies its own content padding before this modifier.
    func accentGlassCard(tint: Color, active: Bool = true) -> some View {
        modifier(AccentGlassCard(tint: tint, active: active))
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    var icon: String = ""
    let title: String
    var iconColor: Color = DS.Colors.violet
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            if !icon.isEmpty {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(iconColor)
            }
            Text(title)
                .font(DS.Font.label)
                .foregroundStyle(DS.Colors.textMuted)
                .tracking(0.8)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(iconColor)
            }
        }
    }
}

// MARK: - Stat Pill

struct StatPill: View {
    let icon: String
    let value: String
    var unit: String = ""
    var color: Color = DS.Colors.textSecondary

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color.opacity(0.7))
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 9))
                    .foregroundStyle(color.opacity(0.6))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.08))
        .overlay(
            Capsule().stroke(color.opacity(0.15), lineWidth: 0.5)
        )
        .clipShape(Capsule())
    }
}

// MARK: - Score Ring (Recovery / Sleep / Strain hero display)

struct ScoreRing: View {
    let score: Double
    var maxScore: Double = 100
    var size: CGFloat = 56
    var lineWidth: CGFloat = 4
    var color: Color = DS.Colors.success
    var label: String? = nil

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(color.opacity(0.12), lineWidth: lineWidth)

            // Progress
            Circle()
                .trim(from: 0, to: min(score / maxScore, 1.0))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(DS.Anim.ringFill, value: score)

            // Center text
            VStack(spacing: 0) {
                Text("\(Int(score))")
                    .font(.system(size: size * 0.32, weight: .heavy, design: .rounded))
                    .foregroundStyle(color)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let label {
                    Text(label)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(DS.Colors.textMuted)
                        .textCase(.uppercase)
                        .tracking(0.5)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Info Row (icon + label + value)

struct InfoRow: View {
    let icon: String
    let label: String
    let value: String
    var color: Color = DS.Colors.textSecondary

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color.opacity(0.7))
                .frame(width: 24)
            Text(label)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Colors.textMuted)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.textPrimary)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
    }
}

// MARK: - Alert Banner

struct AlertBanner: View {
    let icon: String
    let message: String
    var color: Color = DS.Colors.warning

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
            Text(message)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Colors.textPrimary)
                .lineLimit(3)
            Spacer()
        }
        .glassCard(padding: 12, tint: color)
        .padding(.horizontal)
    }
}

// MARK: - Glass Status Pill

struct GlassStatusPill: View {
    let icon: String
    let text: String
    var color: Color = DS.Colors.violet

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.10))
        .overlay(
            Capsule()
                .stroke(color.opacity(0.18), lineWidth: 0.5)
        )
        .clipShape(Capsule())
    }
}

// MARK: - Metric Tile

struct MetricTile: View {
    let label: String
    let value: String
    var unit: String = ""
    var color: Color = DS.Colors.violet

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(DS.Font.micro)
                .foregroundStyle(DS.Colors.textMuted)
                .tracking(0.7)

            Text(value)
                .font(DS.Font.title2)
                .foregroundStyle(color)
                .monospacedDigit()

            if !unit.isEmpty {
                Text(unit)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .lineLimit(2)
            }
        }
        // .leading = horizontal-leading + vertical-CENTER. With minHeight 108 the
        // tiles stay row-consistent, but short content (e.g. SDNN/42/ms) no longer
        // pins to the top with a 48pt dead zone below — vertically centered now.
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
        .padding(DS.Spacing.md)
        .glassCard(padding: 0, tint: color)
    }
}

// MARK: - Empty Glass State

struct EmptyGlassState: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(DS.Colors.textFaint)
            Text(title)
                .font(DS.Font.bodyMed)
                .foregroundStyle(DS.Colors.textPrimary)
            Text(detail)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Colors.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xl)
        .glassCard(padding: DS.Spacing.md)
    }
}

// MARK: - Two-Tone Headline

/// Two-tone typographic headline per Lucid Design Bundle principle 1.
/// Bold primary half locks the eye in 0.3s, muted secondary half adds context
/// without competing. Same font, same size, different weight + color.
struct TwoToneHeadline: View {
    let primary: String
    let secondary: String
    var font: SwiftUI.Font = DS.Font.display

    var body: some View {
        (
            Text(primary)
                .fontWeight(.heavy)
                .foregroundStyle(DS.Colors.textPrimary)
            + Text(secondary.hasPrefix(" ") ? "" : " ")
                .foregroundStyle(DS.Colors.textPrimary)
            + Text(secondary)
                .fontWeight(.regular)
                .foregroundStyle(DS.Colors.textMuted)
        )
        .font(font)
        .kerning(-0.5)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Glass Action Button Style

struct GlassActionButtonStyle: ButtonStyle {
    var tint: Color = DS.Colors.violet
    var filled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(filled ? Color.white : tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Group {
                    if filled {
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(tint.opacity(configuration.isPressed ? 0.52 : 0.70))
                    } else {
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(tint.opacity(configuration.isPressed ? 0.18 : 0.10))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(tint.opacity(0.18), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

// MARK: - Pressable Card Style

/// Press feedback for whole-card buttons (tiles, list rows) that currently use
/// `.buttonStyle(.plain)` and feel dead on tap. Subtle scale + opacity dip —
/// makes every tappable surface feel physically responsive (Emil rule).
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

extension View {
    /// Apply tactile press feedback to a card-shaped Button.
    func pressableCard() -> some View { buttonStyle(PressableCardStyle()) }

    /// Canonical card entrance — rise + fade, staggered by index. One source of
    /// truth for the offset(20)/opacity/stagger pattern that was hand-copied
    /// across every screen (often with duplicated indices). Drive it from a
    /// single `appeared` flag set in the view's .task/.onAppear.
    func entrance(_ appeared: Bool, index: Int) -> some View {
        self
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .animation(DS.Anim.stagger(index: index), value: appeared)
    }
}
