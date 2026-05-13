import SwiftUI

/// Sheet to manually adjust last night's sleep window.
/// Calls HealthEngine.saveSleepTiming(bedtime:waketime:) which updates
/// sleepStartTime/sleepEndTime and triggers a recovery recompute.
struct SleepAdjustSheet: View {
    let engine: HealthEngine
    let ble: BLEManager
    let onClose: () -> Void

    @State private var bedtime: Date
    @State private var waketime: Date
    @State private var isSaving = false
    @State private var saved = false

    init(engine: HealthEngine, ble: BLEManager, onClose: @escaping () -> Void) {
        self.engine = engine
        self.ble = ble
        self.onClose = onClose
        let cal = Calendar.current

        // Sensible defaults: yesterday 23:00 → today 07:00 (8h).
        let yesterday23 = cal.date(bySettingHour: 23, minute: 0, second: 0, of: Date().addingTimeInterval(-86_400))
            ?? Date().addingTimeInterval(-9 * 3600)
        let today7 = cal.date(bySettingHour: 7, minute: 0, second: 0, of: Date())
            ?? Date()

        // Only use engine's stored times if BOTH are set AND the gap is in a
        // reasonable range (3-14 hours). Otherwise: use defaults.
        // (Bug from before: stored sleepStartTime could be days old → showed
        // 101h duration.)
        var bed = yesterday23
        var wake = today7
        if let storedBed = engine.sleepStartTime,
           let storedWake = engine.sleepEndTime {
            let gap = storedWake.timeIntervalSince(storedBed)
            if gap >= 3 * 3600 && gap <= 14 * 3600 {
                bed = storedBed
                wake = storedWake
            }
        }

        _bedtime = State(initialValue: bed)
        _waketime = State(initialValue: wake)
    }

    private var durationLabel: String {
        let secs = waketime.timeIntervalSince(bedtime)
        guard secs > 0 else { return "—" }
        let h = Int(secs / 3600)
        let m = Int((secs.truncatingRemainder(dividingBy: 3600)) / 60)
        return "\(h)h \(m)m"
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.lg) {
                    Color.clear.frame(height: DS.Spacing.xs)

                    // Hero — duration as the big number
                    VStack(spacing: 6) {
                        Text("DURATION")
                            .font(DS.Font.label)
                            .foregroundStyle(DS.Colors.textFaint)
                            .tracking(0.8)
                        Text(durationLabel)
                            .font(.system(size: 48, weight: .heavy, design: .rounded))
                            .foregroundStyle(DS.Colors.violet)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.lg)
                    .glassDefault()
                    .padding(.horizontal, DS.Spacing.md)

                    // Bedtime picker
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        SectionHeader(icon: "bed.double.fill", title: "BEDTIME", iconColor: DS.Colors.violet)
                        DatePicker(
                            "Bedtime",
                            selection: $bedtime,
                            in: ...waketime,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .tint(DS.Colors.violet)
                    }
                    .padding(DS.Spacing.md)
                    .glassDefault()
                    .padding(.horizontal, DS.Spacing.md)

                    // Wake picker
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        SectionHeader(icon: "sun.max.fill", title: "WAKE TIME", iconColor: DS.Colors.amber)
                        DatePicker(
                            "Wake time",
                            selection: $waketime,
                            in: bedtime...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .tint(DS.Colors.amber)
                    }
                    .padding(DS.Spacing.md)
                    .glassDefault()
                    .padding(.horizontal, DS.Spacing.md)

                    // Save button
                    Button {
                        save()
                    } label: {
                        HStack(spacing: 8) {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            } else if saved {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Saved")
                            } else {
                                Image(systemName: "checkmark")
                                Text("Save sleep window")
                            }
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.md)
                        .background(
                            Capsule().fill(saved ? DS.Colors.success : DS.Colors.violet)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving || saved)
                    .padding(.horizontal, DS.Spacing.md)

                    Text("Replaces auto-detected sleep for tonight. Recovery score recomputes immediately.")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Colors.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DS.Spacing.lg)

                    Color.clear.frame(height: DS.Spacing.lg)
                }
            }
            .background(MeshGradientBackground().ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    TwoToneHeadline(
                        primary: "Adjust sleep",
                        secondary: " · last night",
                        font: .system(size: 17, weight: .heavy, design: .rounded)
                    )
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { onClose() }
                        .foregroundStyle(DS.Colors.textSecondary)
                }
            }
        }
    }

    private func save() {
        let h = UIImpactFeedbackGenerator(style: .medium)
        h.impactOccurred()
        isSaving = true
        engine.saveSleepTiming(bedtime: bedtime, waketime: waketime)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isSaving = false
            saved = true
            let s = UINotificationFeedbackGenerator()
            s.notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                onClose()
            }
        }
    }
}
