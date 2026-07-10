import SwiftUI

/// Wind-Down takeover — a calm full-screen page that comes up once per night
/// when wind-down mode opens (22:00). A soft breathing glow sets the pace (4s in,
/// 4s out, time-driven); tonight's plan (including alcohol-recovery note) sits
/// below in a glass card. Dismissed with the single button. Smart Alarm Module 7.
struct WindDownView: View {
    @ObservedObject var bleManager: BLEManager
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var isAlcohol: Bool { bleManager.tonightPlanMode == "alcohol" }
    private var accent: Color { isAlcohol ? DS.Colors.amber : DS.Colors.violet }
    private var planNote: String {
        bleManager.tonightPlanNote.isEmpty
            ? "Lights low, screens away. Let your heart rate settle."
            : bleManager.tonightPlanNote
    }
    private func fmt(_ mins: Int) -> String {
        "\(String(format: "%02d", mins / 60)):\(String(format: "%02d", mins % 60))"
    }

    var body: some View {
        ZStack {
            AuroraBackground().ignoresSafeArea()
            // Vignette — dims the edges so the breathing glow + content hold the
            // centre. Depth, instead of competing violet-on-violet.
            RadialGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.30)],
                center: .center, startRadius: 180, endRadius: 560
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 22) {
                Spacer(minLength: 8)
                breathingSection
                planCard.padding(.horizontal, DS.Spacing.lg)
                SmartWakeControl(bleManager: bleManager)
                    .padding(.horizontal, DS.Spacing.lg)
                Spacer(minLength: 8)
                dismissButton
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xl)
            }
            .opacity(appeared ? 1 : 0)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.6)) { appeared = true } }
    }

    // Time-driven breath: an 8s cycle (4s in, 4s out). The glow is a radial
    // gradient that fades fully to clear — no hard disc edge (that was the
    // "broken gradient"). Glow + hairline ring + moon scale together; the
    // instruction text follows the same clock.
    private var breathingSection: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 86400 : 1.0 / 30.0)) { context in
            let t = reduceMotion ? 0.0 : context.date.timeIntervalSinceReferenceDate
            let cycle = (sin(t * .pi / 4) + 1) / 2          // 0…1 over 8s
            let inhaling = cos(t * .pi / 4) >= 0

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [accent.opacity(0.42), accent.opacity(0.0)],
                                center: .center, startRadius: 2, endRadius: 150
                            )
                        )
                        .frame(width: 300, height: 300)
                        .blur(radius: 8)
                        .scaleEffect(0.70 + 0.30 * cycle)
                    Circle()
                        .stroke(accent.opacity(0.28), lineWidth: 1)
                        .frame(width: 188, height: 188)
                        .scaleEffect(0.80 + 0.20 * cycle)
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(accent)
                        .symbolRenderingMode(.hierarchical)
                        .scaleEffect(0.92 + 0.08 * cycle)
                }
                .frame(height: 300)

                VStack(spacing: 6) {
                    Text(isAlcohol ? "Wind down · recovery night" : "Wind down")
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                        .tracking(-0.4)
                        .foregroundStyle(DS.Colors.textPrimary)
                    Text(reduceMotion ? "Slow your breathing" : (inhaling ? "Breathe in" : "Breathe out"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DS.Colors.textSecondary)
                        .contentTransition(.opacity)
                }
            }
        }
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isAlcohol {
                HStack(spacing: 6) {
                    Text("\u{1F377}").font(.system(size: 13))
                    Text("ALCOHOL MODE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(DS.Colors.amber)
                }
            }
            Text(planNote)
                .font(.system(size: 13))
                .foregroundStyle(DS.Colors.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if bleManager.tonightWindowStart > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "alarm")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Colors.textMuted)
                    Text(isAlcohol
                         ? "No early alarm. Watching from \(fmt(bleManager.tonightWindowStart)), backstop \(fmt(bleManager.tonightWindowEnd))."
                         : "Wake window \(fmt(bleManager.tonightWindowStart)) to \(fmt(bleManager.tonightWindowEnd)).")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.Colors.textMuted)
                }
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)             // real glass — the mesh refracts through
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(accent.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
        )
    }

    private var dismissButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onDismiss()
        } label: {
            Text(isAlcohol ? "Got it, goodnight" : "I'm winding down")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Capsule().fill(DS.Colors.violet))
        }
        .buttonStyle(WindDownPressStyle())
    }
}

/// Tactile press — every interactive element should respond to touch.
private struct WindDownPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

// MARK: - Smart Wake Control (v154)

/// "Wake me at the perfect time" — arms the server-side v154 smart-wake engine.
/// Idle: a primary button + an optional "up by" hard deadline. Armed: the plan
/// (target, floor, projected window / earliest-wake-in, calm note) + Cancel.
/// The server picks the exact moment (onset-anchored need, hard floor, never in
/// deep) and buzzes the strap on fire; this is just the arm + status surface.
struct SmartWakeControl: View {
    @ObservedObject var bleManager: BLEManager

    @State private var useDeadline = false
    @State private var deadline: Date =
        Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: Date()) ?? Date()
    @State private var busy = false

    private let accent = DS.Colors.violet

    private var armed: Bool { bleManager.smartWakeArmed }
    private var status: SmartWakeStatus? { bleManager.smartWakeStatus }
    private var plan: SmartWakePlan? { bleManager.smartWakePlan }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if armed { armedView } else { idleView }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accentGlassCard(tint: accent, active: armed)
        .task { await bleManager.refreshSmartWakeStatus() }
    }

    // MARK: Idle — arm affordance

    private var idleView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                arm()
            } label: {
                HStack(spacing: 8) {
                    if busy {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    } else {
                        Image(systemName: "sunrise.fill").font(.system(size: 14, weight: .semibold))
                    }
                    Text("Wake me at the perfect time")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Capsule().fill(accent))
            }
            .buttonStyle(WindDownPressStyle())
            .disabled(busy)

            Button {
                withAnimation(DS.Anim.quick) { useDeadline.toggle() }
                DS.Haptic.select()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: useDeadline ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                        .foregroundStyle(useDeadline ? accent : DS.Colors.textMuted)
                    Text("Set a hard \u{201C}up by\u{201D} time")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DS.Colors.textSecondary)
                }
            }
            .buttonStyle(.plain)

            if useDeadline {
                DatePicker("", selection: $deadline, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("I'll aim to wake you before this. If it's sooner than your sleep floor, I'll tell you to set a normal alarm too.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(DS.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Armed — plan + cancel

    private var armedView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sunrise.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                Text("SMART WAKE ARMED")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(accent)
                Spacer()
                if let st = status, st.strapStreaming {
                    Text("live")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DS.Colors.success)
                }
            }

            // Numbers row — target + floor (tabular).
            HStack(spacing: 18) {
                if let t = targetH {
                    metric(label: "TARGET", value: String(format: "%.1f", t), unit: "h")
                }
                if let f = plan?.safetyFloorH {
                    metric(label: "FLOOR", value: String(format: "%.1f", f), unit: "h")
                }
                if let win = status?.projectedWindow {
                    metric(label: "WINDOW", value: win, unit: "")
                } else if let inMin = status?.earliestInMin, inMin > 0 {
                    metric(label: "EARLIEST IN", value: "\(inMin)", unit: "m")
                }
            }

            if let note = armedNote, !note.isEmpty {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Colors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if plan?.deadlineBelowFloor == true {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Colors.warning)
                    Text("Your \u{201C}up by\u{201D} time is earlier than your sleep floor. Set a normal alarm too, just in case.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.Colors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                // Always nudge to keep a backup — the wrist buzz needs the app
                // alive overnight; a normal alarm is the belt-and-suspenders net.
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "alarm")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Colors.textMuted)
                    Text("Keep a normal alarm as a backup — I wake you from your wrist, not the phone speaker.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.Colors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                cancel()
            } label: {
                HStack(spacing: 6) {
                    if busy { ProgressView().scaleEffect(0.7) }
                    Text("Cancel smart wake")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(DS.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    Capsule().stroke(DS.Colors.border, lineWidth: 1)
                )
            }
            .buttonStyle(WindDownPressStyle())
            .disabled(busy)
            .padding(.top, 2)
        }
    }

    private func metric(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(DS.Colors.textMuted)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(DS.Colors.textPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Colors.textMuted)
                }
            }
        }
    }

    private var targetH: Double? { plan?.targetH ?? status?.targetH }

    /// Prefer the live status note (updates as he sleeps); fall back to the arm
    /// note (the calm "here's tonight's plan" explainer).
    private var armedNote: String? {
        if let s = status?.note, !s.isEmpty, status?.armed == true { return s }
        return plan?.note
    }

    // MARK: Actions

    private func arm() {
        guard !busy else { return }
        busy = true
        DS.Haptic.commit()
        // The picker only carries an hour:minute; resolve it to the NEXT future
        // occurrence so an evening arm means tomorrow morning, not today's past.
        let target = useDeadline ? nextOccurrence(of: deadline) : nil
        Task {
            _ = await bleManager.armSmartWake(latestWake: target)
            await MainActor.run { busy = false }
        }
    }

    private func nextOccurrence(of picked: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: picked)
        return cal.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime) ?? picked
    }

    private func cancel() {
        guard !busy else { return }
        busy = true
        DS.Haptic.tap()
        Task {
            await bleManager.cancelSmartWake()
            await MainActor.run { busy = false }
        }
    }
}
