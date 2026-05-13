import SwiftUI
import Charts

// MARK: - HealthView (biometric explorer)
// Principle #11 format diversity: ring → bar → chart → stacked bar + tiles → zoned bar + number → timeline → gauge
// Each section uses a different visual format — ADHD attention anchored.

struct HealthView: View {
    @EnvironmentObject private var bleManager: BLEManager
    @State private var appeared = false
    @State private var showTimeline = false
    @State private var showSleepAdjust = false

    private var engine: HealthEngine { bleManager.healthEngine }

    var body: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: DS.Spacing.lg) {
                    Color.clear.frame(height: DS.Spacing.sm)

                    // FORMAT: PILLS — quick actions (Timeline + Sleep adjust)
                    quickActionsRow
                        .padding(.horizontal, DS.Spacing.md)

                    // FORMAT: ROW — live now (biometrics larger)
                    liveNowSection
                        .staggerIn(appeared: appeared, index: 0)

                    // FORMAT: BAR — recovery breakdown
                    recoveryBreakdownSection
                        .staggerIn(appeared: appeared, index: 1)

                    // FORMAT: CHART — HRV trend sparkline (RMSSD headline only)
                    hrvTrendSection
                        .staggerIn(appeared: appeared, index: 2)

                    // FORMAT: COMPACT TILES — research metrics (SDNN / pNN50 / DFA α1)
                    researchMetricsSection
                        .staggerIn(appeared: appeared, index: 3)

                    // FORMAT: STACKED BAR + TILES — sleep
                    sleepSection
                        .staggerIn(appeared: appeared, index: 4)

                    // FORMAT: ZONED BAR + NUMBER — strain & activity
                    strainSection
                        .staggerIn(appeared: appeared, index: 5)

                    // FORMAT: TWIN TILES — body battery + cognitive
                    bodyBatterySection
                        .staggerIn(appeared: appeared, index: 6)

                    // FORMAT: GAUGE (conditional) — illness signals
                    if engine.illnessRisk > 0 || engine.lastAlcoholImpact > 10 {
                        illnessSection
                            .staggerIn(appeared: appeared, index: 7)
                    }

                    // FORMAT: ROWS — device diagnostics
                    deviceSection
                        .staggerIn(appeared: appeared, index: 8)

                    Color.clear.frame(height: 100)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                TwoToneHeadline(
                    primary: "Health",
                    secondary: " · Biometrics",
                    font: .system(size: 17, weight: .heavy, design: .rounded)
                )
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                SettingsGearButton()
            }
        }
        .onAppear { withAnimation { appeared = true } }
        .sheet(isPresented: $showTimeline) {
            NavigationStack {
                ActivityView(ble: bleManager)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            TwoToneHeadline(
                                primary: "Timeline",
                                secondary: " · Today",
                                font: .system(size: 17, weight: .heavy, design: .rounded)
                            )
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showTimeline = false }
                                .foregroundStyle(DS.Colors.violet)
                        }
                    }
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showSleepAdjust) {
            SleepAdjustSheet(engine: engine, ble: bleManager) {
                showSleepAdjust = false
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Quick Actions Row (Timeline + Sleep adjust + I'm awake)

    /// v98 — Show "I'm awake" only while a sleep session is unfinished.
    /// Once sleep score has been computed (sleepEndTime set) the button hides.
    private var canManualWake: Bool {
        engine.sleepDetected || (engine.sleepStartTime != nil && engine.sleepEndTime == nil)
    }

    @ViewBuilder
    private var quickActionsRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            Button {
                let h = UIImpactFeedbackGenerator(style: .light)
                h.impactOccurred()
                showTimeline = true
            } label: {
                Label("Timeline", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.teal)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.sm)
                    .frame(maxWidth: .infinity)
                    .background(
                        Capsule()
                            .fill(DS.Colors.teal.opacity(0.10))
                            .overlay(Capsule().stroke(DS.Colors.teal.opacity(0.25), lineWidth: 0.5))
                    )
            }
            .buttonStyle(.plain)

            // v98 — manual wake-up safety net. Only visible when a sleep session
            // is in progress. Tap forces markSleepEnd + computeRecovery + locks
            // sleep state until 9pm. Solves the Fabi-pattern miss where his
            // chronic-low baseline keeps HR-driven wake detection from firing.
            if canManualWake {
                Button {
                    let h = UINotificationFeedbackGenerator()
                    h.notificationOccurred(.success)
                    engine.manualWakeUp()
                } label: {
                    Label("I'm awake", systemImage: "sun.max.fill")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.amber)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.sm)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule()
                                .fill(DS.Colors.amber.opacity(0.10))
                                .overlay(Capsule().stroke(DS.Colors.amber.opacity(0.25), lineWidth: 0.5))
                        )
                }
                .buttonStyle(.plain)
            }

            Button {
                let h = UIImpactFeedbackGenerator(style: .light)
                h.impactOccurred()
                showSleepAdjust = true
            } label: {
                Label("Adjust sleep", systemImage: "moon.zzz.fill")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.violet)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.sm)
                    .frame(maxWidth: .infinity)
                    .background(
                        Capsule()
                            .fill(DS.Colors.violet.opacity(0.10))
                            .overlay(Capsule().stroke(DS.Colors.violet.opacity(0.25), lineWidth: 0.5))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 1. Live Now (FORMAT: ROW — bigger than Today's version)

    @ViewBuilder
    private var liveNowSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                SectionHeader(icon: "waveform.path.ecg", title: "LIVE NOW", iconColor: DS.Colors.teal)
                AmbientLiveDot(
                    state: bleManager.connectionState == .connected ? .connected
                        : (bleManager.connectionState == .scanning ? .scanning : .disconnected)
                )
                Spacer()
                // HRV mini ring alongside live section
                if engine.currentRMSSD > 0 && !engine.baselineRMSSD.isEmpty {
                    let baseline = engine.baselineRMSSD.reduce(0, +) / Double(engine.baselineRMSSD.count)
                    HRVRingMini(today: engine.currentRMSSD, baseline: baseline)
                }
            }
            .padding(.horizontal, DS.Spacing.md)

            // Tighter 4-cell live row — battery/RSSI/FW moved to Settings → Diagnostics
            // (lucid-design: kill duplicates from Today, focal numbers belong on the headline)
            HStack(spacing: 0) {
                liveCell(icon: "heart.fill", label: "HR",
                         value: bleManager.heartRate > 0 ? "\(bleManager.heartRate)" : "—",
                         unit: "bpm", color: DS.Colors.pink, size: .medium)
                divider
                liveCell(icon: "waveform.path.ecg", label: "HRV",
                         value: engine.currentRMSSD > 0 ? "\(Int(engine.currentRMSSD))" : "—",
                         unit: "ms", color: DS.Colors.teal, size: .medium)
                divider
                liveCell(icon: "lungs", label: "BREATH",
                         value: engine.respiratoryRate > 0 ? String(format: "%.1f", engine.respiratoryRate) : "—",
                         unit: "/min", color: DS.Colors.violet, size: .medium)
                divider
                liveCell(icon: "thermometer.medium", label: "TEMP",
                         value: bleManager.skinTemperature > 0 ? String(format: "%.1f", bleManager.skinTemperature) : "—",
                         unit: "°C", color: DS.Colors.amber, size: .medium)
            }
            .padding(.vertical, DS.Spacing.sm)
            .glassDefault()
            .padding(.horizontal, DS.Spacing.md)
        }
    }

    // MARK: - 2. Recovery Breakdown (FORMAT: BAR)

    @ViewBuilder
    private var recoveryBreakdownSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                CategoryDot(category: .body)
                SectionHeader(title: "RECOVERY BREAKDOWN")
            }
            .padding(.horizontal, DS.Spacing.md)

            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                // Recovery score — demoted to 32pt (Today's hero ring is the focal)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(engine.recoveryScore > 0 ? "\(Int(engine.recoveryScore))" : "—")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(DS.Colors.recoveryColor(engine.recoveryScore))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("/ 100")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DS.Colors.textFaint)
                        .padding(.bottom, 4)
                    Spacer()
                    StatusChip(
                        text: engine.recoveryLabel.isEmpty ? "—" : engine.recoveryLabel,
                        style: engine.recoveryScore >= 67 ? .teal : (engine.recoveryScore >= 34 ? .amber : .danger)
                    )
                }

                // Breakdown segmented bar
                RecoveryBreakdownBar(
                    hrv: engine.recoveryHRVContribution,
                    rhr: engine.recoveryRHRContribution,
                    sleep: engine.recoverySleepContribution,
                    rr: engine.recoveryRRContribution
                )

                // Component legend
                HStack(spacing: DS.Spacing.md) {
                    legendItem(color: DS.Colors.teal, label: "HRV", value: Int(engine.recoveryHRVContribution * 100))
                    legendItem(color: DS.Colors.pink, label: "RHR", value: Int(engine.recoveryRHRContribution * 100))
                    legendItem(color: DS.Colors.violet, label: "Sleep", value: Int(engine.recoverySleepContribution * 100))
                    legendItem(color: DS.Colors.amber, label: "RR", value: Int(engine.recoveryRRContribution * 100))
                    Spacer()
                }
            }
            .padding(DS.Spacing.lg)
            .glassDefault()
            .padding(.horizontal, DS.Spacing.md)
        }
    }

    // MARK: - 3. HRV Trend (FORMAT: CHART)

    @ViewBuilder
    private var hrvTrendSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                CategoryDot(category: .mind)
                SectionHeader(title: "HRV TREND · 7 DAYS")
            }
            .padding(.horizontal, DS.Spacing.md)

            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                // RMSSD as the single headline. ln(RMSSD) demoted to mono caption underneath.
                VStack(alignment: .leading, spacing: 2) {
                    Text("RMSSD")
                        .font(DS.Font.label)
                        .foregroundStyle(DS.Colors.textFaint)
                        .tracking(0.8)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(engine.currentRMSSD > 0 ? "\(Int(engine.currentRMSSD))" : "—")
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .foregroundStyle(DS.Colors.teal)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("ms")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DS.Colors.textFaint)
                        Spacer()
                        if engine.lnRMSSD > 0 {
                            Text(String(format: "ln %.2f", engine.lnRMSSD))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(DS.Colors.textFaint)
                        }
                    }
                }

                // Sparkline chart
                if engine.baselineRMSSD.count >= 3 {
                    let vals = Array(engine.baselineRMSSD.suffix(7))
                    let baseline = engine.baselineRMSSD.reduce(0, +) / Double(engine.baselineRMSSD.count)
                    let sigma = engine.baselineRMSSD.count > 1
                        ? sqrt(engine.baselineRMSSD.map { pow($0 - baseline, 2) }.reduce(0, +) / Double(engine.baselineRMSSD.count))
                        : 5.0
                    SparklineChart(values: vals, baseline: baseline, sigma: sigma, height: 64)
                }

                // vs baseline chip
                if !engine.baselineRMSSD.isEmpty {
                    let baseline = engine.baselineRMSSD.reduce(0, +) / Double(engine.baselineRMSSD.count)
                    let delta = engine.currentRMSSD - baseline
                    let positive = delta >= 0
                    HStack(spacing: DS.Spacing.sm) {
                        StatusChip(
                            text: String(format: "%+.0f ms vs baseline", delta),
                            style: positive ? .teal : .danger,
                            icon: positive ? "arrow.up.right" : "arrow.down.right"
                        )
                        Spacer()
                        Text(String(format: "Ø %.0f ms", baseline))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.Colors.textFaint)
                    }
                }
            }
            .padding(DS.Spacing.lg)
            .glassDefault()
            .padding(.horizontal, DS.Spacing.md)
        }
    }

    // MARK: - 3b. Research Metrics (FORMAT: COMPACT TILES — separated from headline)
    // SDNN / pNN50 / DFA α1 split out to its own card so the HRV Trend hero
    // doesn't compete with itself. lucid-design: format diversity = each card
    // earns its own visual role.

    @ViewBuilder
    private var researchMetricsSection: some View {
        if engine.sdnn > 0 || engine.pnn50 > 0 || engine.dfaAlpha1 > 0 {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.sm) {
                    CategoryDot(category: .mind)
                    SectionHeader(title: "RESEARCH METRICS")
                }
                .padding(.horizontal, DS.Spacing.md)

                let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: cols, spacing: DS.Spacing.sm) {
                    MetricTile(label: "SDNN",   value: engine.sdnn > 0 ? "\(Int(engine.sdnn))" : "—",     unit: "ms", color: DS.Colors.teal)
                    MetricTile(label: "pNN50",  value: engine.pnn50 > 0 ? String(format: "%.1f", engine.pnn50) : "—", unit: "%",  color: DS.Colors.violet)
                    MetricTile(label: "DFA α1", value: engine.dfaAlpha1 > 0 ? String(format: "%.2f", engine.dfaAlpha1) : "—", unit: "α", color: DS.Colors.amber)
                }
                .padding(DS.Spacing.md)
                .glassSubtle()
                .padding(.horizontal, DS.Spacing.md)
            }
        }
    }

    // MARK: - 4. Sleep (FORMAT: STACKED BAR + TILES)

    @ViewBuilder
    private var sleepSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                CategoryDot(category: .sleep)
                SectionHeader(title: "SLEEP LAST NIGHT")
            }
            .padding(.horizontal, DS.Spacing.md)

            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                // Score + duration row
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SCORE")
                            .font(DS.Font.label)
                            .foregroundStyle(DS.Colors.textFaint)
                            .tracking(0.8)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(engine.sleepScore > 0 ? "\(Int(engine.sleepScore))" : "—")
                                .font(.system(size: 32, weight: .heavy, design: .rounded))
                                .foregroundStyle(DS.Colors.sleepColor(engine.sleepScore))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            Text("/ 100")
                                .font(.system(size: 12))
                                .foregroundStyle(DS.Colors.textFaint)
                        }
                    }
                    Spacer()
                    if engine.sleepDurationHours > 0 {
                        let h = Int(engine.sleepDurationHours)
                        let m = Int((engine.sleepDurationHours - Double(h)) * 60)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("DURATION")
                                .font(DS.Font.label)
                                .foregroundStyle(DS.Colors.textFaint)
                                .tracking(0.8)
                            Text("\(h)h \(m)m")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(DS.Colors.textPrimary)
                                .monospacedDigit()
                        }
                    }
                    if engine.sleepEfficiency > 0 {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("EFFICIENCY")
                                .font(DS.Font.label)
                                .foregroundStyle(DS.Colors.textFaint)
                                .tracking(0.8)
                            Text(String(format: "%.0f%%", engine.sleepEfficiency))
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(DS.Colors.violet)
                                .monospacedDigit()
                        }
                    }
                }

                // Stacked sleep stages bar
                let stages: [(HealthEngine.SleepStage, Double)] = HealthEngine.SleepStage.allCases.compactMap { stage in
                    guard let mins = engine.stageMinutes[stage], mins > 0 else { return nil }
                    return (stage, mins)
                }
                let totalMinutes = stages.map { $0.1 }.reduce(0, +)

                if !stages.isEmpty && totalMinutes > 0 {
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(stages, id: \.0) { stage, mins in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(DS.Colors.stageColor(stage))
                                    .frame(width: max(2, geo.size.width * CGFloat(mins / totalMinutes)))
                            }
                        }
                    }
                    .frame(height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    HStack(spacing: DS.Spacing.md) {
                        ForEach(stages, id: \.0) { stage, mins in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(DS.Colors.stageColor(stage))
                                    .frame(width: 7, height: 7)
                                Text(stageName(stage))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(DS.Colors.textFaint)
                                Text("\(Int(mins))m")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(DS.Colors.textSecondary)
                                    .monospacedDigit()
                            }
                        }
                        Spacer()
                    }
                }

            }
            .padding(DS.Spacing.lg)
            .glassDefault()
            .padding(.horizontal, DS.Spacing.md)

            // Sleep details — separate compact card. lucid-design: format diversity =
            // give detail tiles their own visual role instead of stuffing them
            // under the score+stages.
            if hasSleepDetails {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    SectionHeader(title: "SLEEP DETAILS", iconColor: DS.Colors.textFaint)

                    let cols = [GridItem(.flexible()), GridItem(.flexible())]
                    LazyVGrid(columns: cols, spacing: DS.Spacing.sm) {
                        if engine.sleepDebtHours > 0 {
                            MetricTile(label: "SLEEP DEBT",
                                       value: String(format: "%.1f", engine.sleepDebtHours), unit: "h",
                                       color: engine.sleepDebtHours > 2 ? DS.Colors.pink : DS.Colors.amber)
                        }
                        if engine.sleepFragmentationIndex > 0 {
                            MetricTile(label: "FRAGMENTATION",
                                       value: String(format: "%.1f", engine.sleepFragmentationIndex), unit: "/h",
                                       color: engine.sleepFragmentationIndex > 3 ? DS.Colors.amber : DS.Colors.teal)
                        }
                        if engine.nocturnalHRDip != 0 {
                            MetricTile(label: "HR DIP",
                                       value: String(format: "%.1f", engine.nocturnalHRDip), unit: "%",
                                       color: engine.nocturnalHRDip >= 10 ? DS.Colors.teal : DS.Colors.amber)
                        }
                        if engine.sleepConsistencyScore > 0 {
                            MetricTile(label: "CONSISTENCY",
                                       value: "\(Int(engine.sleepConsistencyScore))", unit: "/ 100",
                                       color: DS.Colors.violet)
                        }
                    }
                }
                .padding(DS.Spacing.md)
                .glassSubtle()
                .padding(.horizontal, DS.Spacing.md)
            }
        }
    }

    private var hasSleepDetails: Bool {
        engine.sleepDebtHours > 0 ||
        engine.sleepFragmentationIndex > 0 ||
        engine.nocturnalHRDip != 0 ||
        engine.sleepConsistencyScore > 0
    }

    // MARK: - 5. Strain & Activity (FORMAT: ZONED BAR + NUMBER)

    @ViewBuilder
    private var strainSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                CategoryDot(category: .body)
                SectionHeader(title: "STRAIN & ACTIVITY")
            }
            .padding(.horizontal, DS.Spacing.md)

            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.lg) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("STRAIN")
                            .font(DS.Font.label)
                            .foregroundStyle(DS.Colors.textFaint)
                            .tracking(0.8)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(engine.strainScore > 0 ? String(format: "%.1f", engine.strainScore) : "—")
                                .font(.system(size: 32, weight: .heavy, design: .rounded))
                                .foregroundStyle(DS.Colors.strainColor(engine.strainScore))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            Text("/ 21")
                                .font(.system(size: 12))
                                .foregroundStyle(DS.Colors.textFaint)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("ACWR")
                            .font(DS.Font.label)
                            .foregroundStyle(DS.Colors.textFaint)
                            .tracking(0.8)
                        Text(String(format: "%.2f", engine.trainingLoadRatio))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(engine.trainingLoadRatio > 1.3 ? DS.Colors.pink : DS.Colors.teal)
                            .monospacedDigit()
                    }
                }

                // Zone bar (different format — horizontal zoned bar)
                StrainZonesBar(zoneMinutes: engine.zoneMinutes)

                // Steps + status
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Colors.teal)
                    Text("\(engine.todaySteps) steps")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.textSecondary)
                    Spacer()
                    StatusChip(
                        text: engine.trainingLoadStatus,
                        style: engine.trainingLoadRatio > 1.3 ? .danger : .teal
                    )
                }
            }
            .padding(DS.Spacing.lg)
            .glassDefault()
            .padding(.horizontal, DS.Spacing.md)
        }
    }

    // MARK: - 6. Body Battery (FORMAT: TWIN TILES)

    @ViewBuilder
    private var bodyBatterySection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                CategoryDot(category: .mind)
                SectionHeader(title: "ENERGY & COGNITION")
            }
            .padding(.horizontal, DS.Spacing.md)

            // Asymmetric layout: Body Battery wide+bar (focal), Cognitive compact chip-row.
            // lucid-design: kill the AI 2-up identical-tile grid (#14).
            VStack(spacing: DS.Spacing.sm) {
                let battColor = DS.Colors.bodyBatteryColor(engine.bodyBattery)
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    HStack(alignment: .firstTextBaseline) {
                        Label("BODY BATTERY", systemImage: "battery.100")
                            .font(DS.Font.label)
                            .foregroundStyle(DS.Colors.textFaint)
                            .tracking(0.6)
                        Spacer()
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(engine.bodyBattery > 0 ? "\(Int(engine.bodyBattery))" : "—")
                                .font(.system(size: 28, weight: .heavy, design: .rounded))
                                .foregroundStyle(battColor)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            Text("/ 100")
                                .font(.system(size: 11))
                                .foregroundStyle(DS.Colors.textFaint)
                        }
                    }

                    if engine.bodyBattery > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(DS.Colors.surfaceElevated)
                                    .frame(height: 8)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(battColor)
                                    .frame(width: geo.size.width * CGFloat(engine.bodyBattery / 100), height: 8)
                                    .animation(DS.Anim.ringFill, value: engine.bodyBattery)
                            }
                        }
                        .frame(height: 8)
                    }
                }
                .padding(DS.Spacing.md)
                .frame(maxWidth: .infinity)
                .glassDefault()

                // Cognitive — compact chip row, not a competing tile
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "brain")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Colors.violet)
                    Text("COGNITIVE")
                        .font(DS.Font.label)
                        .foregroundStyle(DS.Colors.textFaint)
                        .tracking(0.6)
                    Spacer()
                    Text(engine.cognitiveCapacity > 0 ? "\(Int(engine.cognitiveCapacity))" : "—")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Colors.violet)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("/ 100")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Colors.textFaint)
                    if !engine.cognitiveLabel.isEmpty && engine.cognitiveLabel != "—" {
                        StatusChip(text: engine.cognitiveLabel, style: .violet)
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .glassSubtle()
            }
            .padding(.horizontal, DS.Spacing.md)
        }
    }

    // MARK: - 7. Illness Signals (FORMAT: GAUGE CHIPS)

    @ViewBuilder
    private var illnessSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                CategoryDot(category: .care)
                SectionHeader(title: "HEALTH SIGNALS", iconColor: DS.Colors.amber)
            }
            .padding(.horizontal, DS.Spacing.md)

            HStack(spacing: DS.Spacing.lg) {
                IllnessRiskGauge(risk: engine.illnessRisk, alert: engine.illnessAlert)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    if engine.lastAlcoholImpact > 5 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ALCOHOL EFFECT")
                                .font(DS.Font.label)
                                .foregroundStyle(DS.Colors.textFaint)
                                .tracking(0.8)
                            Text(String(format: "%.0f%%", engine.lastAlcoholImpact))
                                .font(.system(size: 28, weight: .heavy, design: .rounded))
                                .foregroundStyle(DS.Colors.amber)
                                .monospacedDigit()
                            Text("HRV below baseline")
                                .font(.system(size: 9))
                                .foregroundStyle(DS.Colors.textFaint)
                        }
                    }
                    Spacer()
                    if engine.consecutiveLowHRVDays > 0 {
                        StatusChip(
                            text: "\(engine.consecutiveLowHRVDays) days low HRV",
                            style: .amber,
                            icon: "arrow.down.forward"
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(DS.Spacing.lg)
            .glassDefault()
            .padding(.horizontal, DS.Spacing.md)
        }
    }

    // MARK: - 8. Device (FORMAT: ROWS)

    @ViewBuilder
    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            SectionHeader(icon: "antenna.radiowaves.left.and.right", title: "DEVICE", iconColor: DS.Colors.textFaint)
                .padding(.horizontal, DS.Spacing.md)

            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack {
                    BLEStatusDot()
                        .environmentObject(bleManager)
                    Spacer()
                    if bleManager.isWorn {
                        GlassStatusPill(icon: "figure.walk", text: "Worn", color: DS.Colors.teal)
                    }
                    if bleManager.isCharging {
                        GlassStatusPill(icon: "bolt.fill", text: "Charging", color: DS.Colors.amber)
                    }
                }

                let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: cols, spacing: DS.Spacing.sm) {
                    MetricTile(label: "BATTERY",
                               value: bleManager.battery > 0 ? "\(Int(bleManager.battery))" : "—",
                               unit: "%",
                               color: bleManager.battery < 20 ? DS.Colors.pink : DS.Colors.teal)
                    MetricTile(label: "READINGS",
                               value: "\(bleManager.readingsToday)",
                               unit: "today",
                               color: DS.Colors.violet)
                    MetricTile(label: "SYNC",
                               value: "\(bleManager.historySyncCount)",
                               unit: "points",
                               color: DS.Colors.textSecondary)
                }

                if let lastSync = bleManager.lastSync {
                    InfoRow(icon: "arrow.clockwise", label: "Last sync",
                            value: lastSync.formatted(.dateTime.hour().minute().second()),
                            color: DS.Colors.textFaint)
                }
            }
            .padding(DS.Spacing.md)
            .glassDefault()
            .padding(.horizontal, DS.Spacing.md)
        }
    }

    // MARK: - Helpers

    private enum LiveCellSize { case large, medium, small }

    private func liveCell(icon: String, label: String, value: String, unit: String, color: Color, size: LiveCellSize) -> some View {
        let iconSize: CGFloat = {
            switch size { case .large: return 11; case .medium: return 10; case .small: return 9 }
        }()
        let valueSize: CGFloat = {
            switch size { case .large: return 18; case .medium: return 16; case .small: return 13 }
        }()
        return VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: iconSize))
                .foregroundStyle(color.opacity(0.8))
            Text(value)
                .font(.system(size: valueSize, weight: .bold, design: .rounded))
                .foregroundStyle(DS.Colors.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(unit.isEmpty ? label : unit)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(DS.Colors.textFaint)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(DS.Colors.border.opacity(0.4))
            .frame(width: 0.5, height: 28)
    }

    private func stageName(_ s: HealthEngine.SleepStage) -> String {
        switch s {
        case .awake: return "Awake"
        case .light: return "Light"
        case .deep:  return "Deep"
        case .rem:   return "REM"
        }
    }

    private var batteryIcon: String {
        let b = Int(bleManager.battery)
        if bleManager.isCharging { return "battery.100.bolt" }
        switch b {
        case 75...: return "battery.100"
        case 50...: return "battery.75"
        case 25...: return "battery.50"
        default:    return "battery.25"
        }
    }

    private func legendItem(color: Color, label: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DS.Colors.textFaint)
            Text("\(value)%")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.textSecondary)
                .monospacedDigit()
        }
    }
}

// MARK: - Stagger modifier

private extension View {
    func staggerIn(appeared: Bool, index: Int) -> some View {
        self
            .offset(y: appeared ? 0 : 20)
            .opacity(appeared ? 1 : 0)
            .animation(DS.Anim.stagger(index: index), value: appeared)
    }
}
