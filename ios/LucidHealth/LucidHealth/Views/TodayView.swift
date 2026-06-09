import SwiftUI

// MARK: - TodayView (primary screen — most polished)
// Principles applied: 1 (two-tone toolbar), 2 (textured canvas), 4 (pill radii),
// 5 (category dots), 8 (floating pill bar), 10 (size = hierarchy — 180pt ring),
// 11 (format diversity: ring → row → pills → card → text), 12 (status colors only).

/// Single enum drives all 3 food-entry modals. SwiftUI's per-modifier sheet/cover
/// stacking is unreliable when 2+ are attached to the same view (silently no-ops
/// after the first). One `.fullScreenCover(item:)` switch handles all three
/// modes deterministically.
enum FoodEntryMode: Identifiable {
    case camera, barcode, manual
    var id: Int {
        switch self { case .camera: return 1; case .barcode: return 2; case .manual: return 3 }
    }
}

struct TodayView: View {
    @EnvironmentObject private var bleManager: BLEManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var entries: [FoodEntry] = []
    @State private var isLoading = false
    @State private var foodEntryMode: FoodEntryMode? = nil
    @State private var showFABMenu = false
    @State private var error: String?
    @State private var appeared = false
    @State private var hasLoaded = false
    @State private var recoveryTrend: [Double] = []
    @State private var saveSuccessCount = 0
    @State private var saveErrorCount = 0
    @StateObject private var modeStore = AppModeStore()
    @State private var showTimeline = false
    @State private var activityDraft: String = ""
    @State private var showWindDown = false

    // Shared glass sampling namespace — lets GlassEffectContainer treat
    // sibling glass surfaces as one continuous material per LiquidGlassReference.
    @Namespace private var glassNS

    private let supabase = SupabaseClient.shared

    // MARK: - Computed

    private var engine: HealthEngine { bleManager.healthEngine }
    private var overlay: RecoveryOverlay { RecoveryOverlayResolver.resolve(engine: engine) }

    /// Show the wind-down takeover at most once per calendar day, when wind-down
    /// mode is active. Also fires the wind-down image notification.
    private func maybeShowWindDown(_ mode: AppMode) {
        guard mode == .windDown else { return }
        let key = "lucid_winddown_shown_date"
        let today = Self.dayStamp(Date())
        if UserDefaults.standard.string(forKey: key) == today { return }
        UserDefaults.standard.set(today, forKey: key)
        showWindDown = true
        bleManager.sendWindDownNotification(note: bleManager.tonightPlanNote)
    }

    private static func dayStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private var todayEntries: [FoodEntry] {
        entries.filter { Calendar.current.isDateInToday($0.capturedAt) }
    }

    private var totalKcalToday: Int {
        todayEntries.compactMap { $0.totalKcal }.reduce(0, +)
    }

    private var novaAvgToday: Double? {
        let vals = todayEntries.compactMap { $0.novaAvg }
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    private var mindScoreToday: Int {
        let pos = Set(["leafy_green","fish","berries","olive_oil","nuts","legumes","whole_grain"])
        let neg = Set(["fried","processed_meat","pastries","ultra_processed"])
        var p = 0; var n = 0
        for entry in todayEntries {
            for item in entry.items {
                for tag in item.mindTags {
                    if pos.contains(tag) { p += 1 }
                    if neg.contains(tag) { n += 1 }
                }
            }
        }
        return max(0, min(15, p - min(n, 2)))
    }

    private var lastMeal: FoodEntry? {
        entries.first(where: { !$0.items.isEmpty })
    }

    private var fastingHours: Double? {
        guard let meal = lastMeal else { return nil }
        let hours = Date().timeIntervalSince(meal.capturedAt) / 3600
        return hours > 1 ? hours : nil
    }

    // MARK: - Recovery context line (PINCH, pre-baked, no AI narration)
    private var recoveryContextLine: String {
        let s = engine.recoveryScore
        if s >= 67 { return "Well recovered. Push what matters." }
        if s >= 34 { return "Middle ground. Take it easier." }
        return "Low. Let the tank refill." }

    // MARK: - Time-of-day toolbar greeting
    private var timeOfDayGreeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return "Morning"
        case 12..<17: return "Noon"
        case 17..<22: return "Evening"
        default:       return "Night"
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if modeStore.current == .lateNight {
                lateNightReplacement
            } else {
                regularContent
            }

            // FAB — bottom-right, above tab bar (hidden in late-night)
            if modeStore.current != .lateNight {
                fabSection
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                TwoToneHeadline(
                    primary: timeOfDayGreeting,
                    secondary: " · LucidHealth",
                    font: .system(size: 17, weight: .heavy, design: .rounded)
                )
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 4) {
                    Button {
                        let h = UIImpactFeedbackGenerator(style: .light)
                        h.impactOccurred()
                        showTimeline = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(DS.Colors.teal)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    SettingsGearButton()
                }
            }
        }
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
        .sheet(isPresented: $bleManager.showDoubleTapSheet) {
            QuickTagSheet(ble: bleManager)
        }
        // Wind-down takeover — comes up once per night when wind-down mode opens.
        .fullScreenCover(isPresented: $showWindDown) {
            WindDownView(bleManager: bleManager) { showWindDown = false }
        }
        // ONE cover for all three food-entry modes. SwiftUI's multi-modifier
        // stacking is flaky (3rd cover on same view silently no-ops). Item-based
        // presentation with an enum is the canonical workaround.
        .fullScreenCover(item: $foodEntryMode) { mode in
            switch mode {
            case .camera:
                CameraView { entry in entries.insert(entry, at: 0) }
            case .barcode:
                BarcodeScannerView { entry in entries.insert(entry, at: 0) }
            case .manual:
                ManualFoodEntrySheet { entry in entries.insert(entry, at: 0) }
            }
        }
        .task {
            modeStore.start(engine: engine)
            await loadEntries()
            withAnimation(DS.Anim.cardAppear) { appeared = true }
            hasLoaded = true
            recoveryTrend = await bleManager.supabase.fetchRecoveryTrend()
            await bleManager.syncTonightPlan()
            maybeShowWindDown(modeStore.current)
        }
        .onDisappear { modeStore.stop() }
        // Wind-down page comes up once per night when the mode flips to wind-down.
        .onChange(of: modeStore.current) { _, newMode in
            maybeShowWindDown(newMode)
        }
        // Reload entries when app comes back to foreground — picks up server-side
        // inserts (e.g. meals logged via REST while app was backgrounded).
        .onChange(of: scenePhase) { _, newPhase in
            bleManager.evt("app_state", "\(newPhase)")
            if newPhase == .active && hasLoaded {
                Task { await loadEntries() }
                // v100 architecture migration — pull fresh server-computed
                // recovery + sleep score on every foreground. Fixes the
                // "stuck at stale value" bug by making the server's
                // recompute_health_metrics RPC the source of truth.
                Task {
                    if let result = await bleManager.supabase.recomputeHealthMetrics() {
                        await MainActor.run {
                            bleManager.healthEngine.recoveryScore = result.recovery
                            bleManager.healthEngine.sleepScore = result.sleepScore
                        }
                    }
                    let trend = await bleManager.supabase.fetchRecoveryTrend()
                    await MainActor.run { recoveryTrend = trend }
                }
                Task { await bleManager.syncTonightPlan() }
            }
        }
        .sensoryFeedback(.success, trigger: hasLoaded)
        .sensoryFeedback(.success, trigger: saveSuccessCount)
        .sensoryFeedback(.error, trigger: saveErrorCount)
        .overlay(alignment: .top) {
            if let e = error {
                AlertBanner(icon: "exclamationmark.triangle", message: e, color: DS.Colors.pink)
                    .padding(.horizontal, DS.Spacing.md)
            }
        }
    }

    // MARK: - Regular Content (Morning / Day / Evening / Wind-Down)

    @ViewBuilder
    private var regularContent: some View {
        // Spacing scale per section role — fixes the "too big / too small" rhythm:
        //   • Mode/overlay banners — sm (8pt) — quick context, tight cluster
        //   • Hero ring zone — xl (32pt) — main focal point, needs breathing
        //   • Live stats — sm (8pt) — extends hero, tight cluster
        //   • Activity composer — xl (32pt) — separate concern
        //   • Last meal + bento — md (16pt) — food cluster, related
        //   • Conditional banners — md/lg — dynamic, varied weight
        //   • Baseline delta — xl (32pt) — analytical surface, separate
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Color.clear.frame(height: DS.Spacing.xs)

                ModeBanner(mode: modeStore.current, modeStore: modeStore)
                    .padding(.top, DS.Spacing.sm)
                    .opacity(appeared ? 1 : 0)
                    .animation(DS.Anim.cardAppear, value: appeared)
                    .scrollSectionTransition()

                // SMART ALARM — surfaced right under the mode banner during
                // wind-down (22:00–00:00) so Fabi can configure tonight's wake
                // before going to bed. Hidden during day/morning/etc to avoid
                // clutter — Settings has a copy for off-hours config.
                if modeStore.current == .windDown {
                    SmartAlarmCard(bleManager: bleManager)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.top, DS.Spacing.md)
                        .opacity(appeared ? 1 : 0)
                        .animation(DS.Anim.cardAppear, value: appeared)
                        .scrollSectionTransition()
                }

                RecoveryOverlayBanner(overlay: overlay)
                    .padding(.top, DS.Spacing.sm)
                    .opacity(appeared ? 1 : 0)
                    .animation(DS.Anim.cardAppear, value: appeared)
                    .scrollSectionTransition()

                // Hero + Live stats refract together as one material (LiquidGlassReference)
                GlassEffectContainer(spacing: 32) {
                    VStack(spacing: 0) {
                        heroSection
                            .padding(.top, DS.Spacing.xl)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 28)
                            .animation(DS.Anim.stagger(index: 0), value: appeared)

                        liveStatsSection
                            .padding(.top, DS.Spacing.sm)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)
                            .animation(DS.Anim.stagger(index: 1), value: appeared)
                    }
                }
                .scrollSectionTransition()

                // Hermes — body-state interpreter + chat. Sits right under the
                // recovery ring so the interpretation reads as commentary on
                // the ring's number.
                HermesCard()
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.top, DS.Spacing.lg)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(DS.Anim.stagger(index: 2), value: appeared)
                    .scrollSectionTransition()

                activityComposerSection
                    .padding(.top, DS.Spacing.xl)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(DS.Anim.stagger(index: 3), value: appeared)
                    .scrollSectionTransition()

                if let meal = lastMeal {
                    LastMealCard(entry: meal)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.top, DS.Spacing.lg)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(DS.Anim.stagger(index: 3), value: appeared)
                        .scrollSectionTransition()
                }

                // Food stats bento — 3 tiles share a glass sampling region
                GlassEffectContainer(spacing: 18) {
                    foodStatsSection
                }
                .padding(.top, DS.Spacing.md)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)
                .animation(DS.Anim.stagger(index: 4), value: appeared)
                .scrollSectionTransition()

                if let hours = fastingHours {
                    FastingBanner(hours: hours)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.top, DS.Spacing.lg)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(DS.Anim.stagger(index: 5), value: appeared)
                        .scrollSectionTransition()
                }

                if engine.illnessRisk >= 2, let alert = engine.illnessAlert {
                    AlertBanner(icon: "staroflife.fill", message: alert, color: DS.Colors.amber)
                        .padding(.top, DS.Spacing.md)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(DS.Anim.stagger(index: 6), value: appeared)
                        .scrollSectionTransition()
                }

                if engine.lastAlcoholImpact > 10 {
                    PatternNote(
                        text: String(format: "Likely the wine. HRV %.0f%% below baseline — not on you.", engine.lastAlcoholImpact),
                        icon: "wineglass",
                        color: DS.Colors.amber
                    )
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.top, DS.Spacing.md)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(DS.Anim.stagger(index: 7), value: appeared)
                    .scrollSectionTransition()
                }

                if engine.baselineRMSSD.count >= 14 {
                    baselineDeltaSection
                        .padding(.top, DS.Spacing.lg)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(DS.Anim.stagger(index: 8), value: appeared)
                        .scrollSectionTransition()
                }

                // Outside context — weather (always) + PC (if bridge running)
                WeatherContextTile()
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.top, DS.Spacing.lg)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(DS.Anim.stagger(index: 9), value: appeared)
                    .scrollSectionTransition()

                PCActivityTile()
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.top, DS.Spacing.md)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(DS.Anim.stagger(index: 10), value: appeared)
                    .scrollSectionTransition()

                Color.clear.frame(height: 100)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .refreshable { await loadEntries() }
    }

    // MARK: - Late-Night Replacement (00:00 — 05:00)
    // The page Fabi sees right before bed. NOT empty — actively useful:
    // smart alarm setup at the top, gentle bedtime marker below, live
    // HR/HRV chip at bottom. The whole point of late-night is "sleep is
    // the work" so this surface focuses on the one thing that helps
    // wake well: the alarm.
    @ViewBuilder
    private var lateNightReplacement: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DS.Spacing.lg) {
                Color.clear.frame(height: DS.Spacing.md)

                // SMART ALARM — the actual reason this page exists at 00:00-05:00.
                SmartAlarmCard(bleManager: bleManager)
                    .padding(.horizontal, DS.Spacing.md)

                // Bedtime marker — quiet, not screen-takeover.
                HStack(spacing: DS.Spacing.md) {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(DS.Colors.violet.opacity(0.7))
                        .symbolRenderingMode(.hierarchical)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Late-night protection")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(DS.Colors.textPrimary)
                        Text("Recommendations off. Sleep is the work.")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Colors.textMuted)
                    }
                    Spacer()
                }
                .padding(DS.Spacing.md)
                .glassSubtle()
                .padding(.horizontal, DS.Spacing.md)

                // Live HR/HRV — quiet chip row, only when streaming
                if bleManager.heartRate > 0 {
                    HStack(spacing: DS.Spacing.lg) {
                        VStack(spacing: 1) {
                            Text("\(bleManager.heartRate)")
                                .font(.system(size: 18, weight: .heavy, design: .rounded))
                                .foregroundStyle(DS.Colors.violet)
                                .monospacedDigit()
                            Text("HR")
                                .font(DS.Font.label)
                                .foregroundStyle(DS.Colors.textFaint)
                        }
                        Rectangle()
                            .fill(DS.Colors.border)
                            .frame(width: 0.5, height: 20)
                        VStack(spacing: 1) {
                            Text(engine.currentRMSSD > 0 ? "\(Int(engine.currentRMSSD))" : "—")
                                .font(.system(size: 18, weight: .heavy, design: .rounded))
                                .foregroundStyle(DS.Colors.teal)
                                .monospacedDigit()
                            Text("HRV")
                                .font(DS.Font.label)
                                .foregroundStyle(DS.Colors.textFaint)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.sm)
                    .glassSubtle()
                }

                Color.clear.frame(height: DS.Spacing.xl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Hero Section (FORMAT: RING)
    @AppStorage("recoveryRingStyle") private var ringStyleRaw: String = RecoveryRingStyle.classic.rawValue
    private var ringStyle: RecoveryRingStyle {
        RecoveryRingStyle(rawValue: ringStyleRaw) ?? .classic
    }

    @ViewBuilder
    private var heroSection: some View {
        VStack(spacing: DS.Spacing.md) {
            // 180pt ring — biggest thing on screen (principle #10)
            // v103 — switchable: Classic (continuous gradient) or Smoke (Mode A
            // with recovery-tinted wisps off the trim tip). Settings → Display.
            // Body Battery is now the hero (the "how much can I push" tank).
            // Recovery is demoted into the secondary strip inside this card.
            BodyBatteryHero(
                level: engine.bodyBattery,
                recovery: engine.recoveryScore,
                sleepHours: engine.sleepDurationHours,
                strain: engine.strainScore
            )
                .statusGlow(DS.Colors.bodyBatteryColor(engine.bodyBattery), intensity: 0.7)
                .padding(.top, DS.Spacing.sm)

            // v106: alcohol-night chip. Gives context to a low score so the
            // number doesn't read as "the app is broken" when it's actually
            // "your nervous system is wrecked from drinking".
            if engine.alcoholImpact > 0 {
                AlcoholNightChip()
                    .padding(.horizontal, DS.Spacing.lg)
            }

            // 14-day recovery trend — makes the (real, 9-100 swinging) score's
            // movement visible so a correct-but-varying number stops reading
            // as "stuck at 60".
            RecoveryTrendStrip(scores: recoveryTrend)
                .padding(.horizontal, DS.Spacing.lg)

            // Recovery context line — PINCH style, pre-baked, no AI narration
            Text(recoveryContextLine)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, DS.Spacing.sm)
        }
        .padding(.horizontal, DS.Spacing.md)
    }

    // MARK: - Live Stats Row (FORMAT: ROW)
    @ViewBuilder
    private var liveStatsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                SectionHeader(icon: "waveform.path.ecg", title: "LIVE", iconColor: DS.Colors.teal)
                AmbientLiveDot(
                    state: bleManager.connectionState == .connected ? .connected : .disconnected
                )
            }
            .padding(.horizontal, DS.Spacing.md)

            // Principle #11 — row format (not ring again)
            LiveBiometricsPanel()
                .environmentObject(bleManager)
                .padding(.horizontal, DS.Spacing.md)
        }
    }

    // MARK: - Activity Composer (FORMAT: COMPOSER) — inline custom-name activity start
    // No predefined picker — Fabi types what he's doing, taps Start. Lucid AI canonicalizes
    // server-side. When a session is active, this shows the active card with End button.
    @ViewBuilder
    private var activityComposerSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                CategoryDot(category: .body)
                SectionHeader(title: "ACTIVITY")
                Spacer()
            }
            .padding(.horizontal, DS.Spacing.md)

            if let active = bleManager.manualActivityType,
               let started = bleManager.manualActivityStart {
                activeSessionCard(type: active, startedAt: started)
                    .padding(.horizontal, DS.Spacing.md)
            } else {
                composerInputCard
                    .padding(.horizontal, DS.Spacing.md)
            }
        }
    }

    @ViewBuilder
    private var composerInputCard: some View {
        HStack(spacing: DS.Spacing.sm) {
            TextField("What are you doing?", text: $activityDraft)
                .font(.system(size: 14, weight: .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(DS.Colors.surfaceElevated)
                .clipShape(Capsule())
                .foregroundStyle(DS.Colors.textPrimary)
                .submitLabel(.go)
                .onSubmit { startActivity() }

            Button {
                startActivity()
            } label: {
                Label("Start", systemImage: "play.fill")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, 12)
                    .background(
                        Capsule().fill(activityDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                       ? DS.Colors.violet.opacity(0.3)
                                       : DS.Colors.violet)
                    )
            }
            .buttonStyle(.plain)
            .disabled(activityDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder
    private func activeSessionCard(type: String, startedAt: Date) -> some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { _ in
            HStack(spacing: DS.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(DS.Colors.violet.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DS.Colors.violet)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(type.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.textPrimary)
                        .lineLimit(1)
                    Text(elapsedString(from: startedAt) + (bleManager.heartRate > 0 ? " · \(bleManager.heartRate) bpm" : ""))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(DS.Colors.textMuted)
                }

                Spacer()

                Button {
                    let h = UIImpactFeedbackGenerator(style: .medium)
                    h.impactOccurred()
                    bleManager.endManualActivity()
                } label: {
                    Label("End", systemImage: "stop.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.danger)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(DS.Colors.danger.opacity(0.10))
                                .overlay(Capsule().stroke(DS.Colors.danger.opacity(0.30), lineWidth: 0.5))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(DS.Spacing.md)
            .glassDefault()
        }
    }

    private func elapsedString(from start: Date) -> String {
        let secs = Int(Date().timeIntervalSince(start))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        let s = secs % 60
        if h > 0 {
            return String(format: "%dh %02dm", h, m)
        }
        return String(format: "%d:%02d", m, s)
    }

    private func startActivity() {
        let trimmed = activityDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let h = UIImpactFeedbackGenerator(style: .medium)
        h.impactOccurred()
        // Slug the name (lowercase, underscores) — Lucid AI canonicalizes anyway
        let slug = trimmed.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
        bleManager.startManualActivity(type: slug)
        activityDraft = ""
    }

    // MARK: - Food Stats Bento (FORMAT: NUMBER)
    @ViewBuilder
    private var foodStatsSection: some View {
        HStack(spacing: DS.Spacing.md) {
            FoodStatCell(
                icon: "flame.fill",
                label: "CALORIES",
                value: totalKcalToday > 0 ? "\(totalKcalToday)" : "—",
                unit: "kcal",
                color: DS.Colors.amber
            )
            if let nova = novaAvgToday {
                FoodStatCell(
                    icon: "scalemass",
                    label: "NOVA",
                    value: String(format: "%.1f", nova),
                    unit: "/ 4",
                    color: DS.Colors.novaColor(nova)
                )
            }
            FoodStatCell(
                icon: "brain",
                label: "BRAIN",
                value: mindScoreToday > 0 ? "\(mindScoreToday)" : "—",
                unit: "/ 15",
                color: DS.Colors.mindColor(Double(mindScoreToday))
            )
        }
        .padding(.horizontal, DS.Spacing.md)
    }

    // MARK: - Baseline Delta (FORMAT: DELTA NUMBER — principle #11, not another ring)
    @ViewBuilder
    private var baselineDeltaSection: some View {
        let arr = engine.baselineRMSSD
        let baseline = arr.isEmpty ? 0.0 : arr.suffix(7).reduce(0, +) / Double(min(arr.count, 7))
        let delta = engine.currentRMSSD - baseline
        let positive = delta >= 0

        HStack(spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    CategoryDot(category: .body)
                    Text("HRV VS BASELINE")
                        .font(DS.Font.label)
                        .foregroundStyle(DS.Colors.textFaint)
                        .tracking(0.8)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: positive ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(positive ? DS.Colors.teal : DS.Colors.pink)
                    Text(String(format: "%+.0f ms", delta))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(positive ? DS.Colors.teal : DS.Colors.pink)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("BASELINE")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(DS.Colors.textFaint)
                    .tracking(0.8)
                Text(String(format: "%.0f ms", baseline))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.textSecondary)
                    .monospacedDigit()
            }

            VStack(alignment: .trailing, spacing: 3) {
                Text("NOW")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(DS.Colors.textFaint)
                    .tracking(0.8)
                Text(engine.currentRMSSD > 0 ? "\(Int(engine.currentRMSSD)) ms" : "—")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .padding(DS.Spacing.md)
        .glassDefault()
        .padding(.horizontal, DS.Spacing.md)
    }

    // MARK: - FAB
    @ViewBuilder
    private var fabSection: some View {
        VStack(spacing: DS.Spacing.sm) {
            if showFABMenu {
                FABMenu(isOpen: $showFABMenu) {
                    foodEntryMode = .camera
                } onBarcode: {
                    foodEntryMode = .barcode
                } onManual: {
                    foodEntryMode = .manual
                }
                .padding(.trailing, DS.Spacing.lg)
            }
            FABButton(isOpen: $showFABMenu)
                .padding(.trailing, DS.Spacing.lg)
                .padding(.bottom, 100)
        }
    }

    // MARK: - Data

    private func loadEntries() async {
        isLoading = true
        error = nil
        do {
            entries = try await supabase.fetchRecentFoodEntries(limit: 30)
        } catch {
            self.error = "Load failed"
        }
        isLoading = false
    }

    private func quickLog(_ item: QuickLogItem) async {
        do {
            let saved = try await supabase.saveQuickLog(item)
            entries.insert(saved, at: 0)
            saveSuccessCount += 1
        } catch {
            self.error = "Save failed"
            saveErrorCount += 1
        }
    }
}

// MARK: - Food Stat Cell (bento number tile)

private struct FoodStatCell: View {
    let icon: String
    let label: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Label(label, systemImage: icon)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(DS.Colors.textFaint)
                .tracking(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DS.Colors.textFaint)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.md)
        .glassDefault()
    }
}

// MARK: - Fasting Banner

private struct FastingBanner: View {
    let hours: Double

    private var color: Color {
        switch hours {
        case ..<12: return DS.Colors.amber
        case 12..<16: return DS.Colors.teal
        default: return DS.Colors.violet
        }
    }

    private var label: String {
        switch hours {
        case ..<12: return "Fasting"
        case 12..<16: return "Ketosis window"
        default: return "Extended fast"
        }
    }

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: "hourglass.tophalf.fill")
                .font(.system(size: 20))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
                Text(String(format: "%.0f hours since last meal", hours))
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Colors.textSecondary)
            }

            Spacer()

            Text(String(format: "%.0fh", hours))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .padding(DS.Spacing.md)
        .glassDefault()
    }
}

// MARK: - Smart Alarm Card
//
// The reason the late-night Today page exists. Used to be empty ("Sleep is
// the work right now") which was useless. This card is the actual setup
// surface — Fabi enables, picks wake time, picks window, hits "Test now"
// to verify, goes to bed.
//
// Wires three UserDefaults keys read by HealthEngine.checkSmartAlarm():
//   • lucid_alarm_enabled — Bool
//   • lucid_alarm_start   — Int (minutes-of-day for window START)
//   • lucid_alarm_end     — Int (minutes-of-day for window END)
//
// On enable → bleManager.scheduleFallbackAlarm() schedules a guaranteed
// time-sensitive UNNotification at window-end (defaultCritical sound)
// even if BLE drops or the app gets killed overnight. The smart-alarm
// trigger inside SleepEngine.checkSmartAlarm() runs every ~30s while BLE
// is streaming and fires earlier when light sleep is detected, then
// cancels the fallback.
private struct SmartAlarmCard: View {
    @ObservedObject var bleManager: BLEManager

    @AppStorage("lucid_alarm_enabled") private var enabled: Bool = false
    @AppStorage("lucid_alarm_start") private var windowStartMinutes: Int = 7 * 60   // 07:00
    @AppStorage("lucid_alarm_end") private var windowEndMinutes: Int = 7 * 60 + 30  // 07:30
    @State private var testQueued: Bool = false

    private var windowLength: Int {
        max(15, windowEndMinutes - windowStartMinutes)
    }

    /// Bind the END time as a Date so DatePicker is intuitive ("when do you
    /// want to be up by"). Window START is computed from end - length.
    private var wakeByDate: Binding<Date> {
        Binding(
            get: {
                var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                c.hour = windowEndMinutes / 60
                c.minute = windowEndMinutes % 60
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { newDate in
                let cal = Calendar.current
                let mins = cal.component(.hour, from: newDate) * 60 + cal.component(.minute, from: newDate)
                windowEndMinutes = mins
                windowStartMinutes = max(0, mins - windowLength)
                if enabled { bleManager.scheduleFallbackAlarm() }
            }
        )
    }

    private func formatWindow() -> String {
        let s = "\(String(format: "%02d", windowStartMinutes / 60)):\(String(format: "%02d", windowStartMinutes % 60))"
        let e = "\(String(format: "%02d", windowEndMinutes / 60)):\(String(format: "%02d", windowEndMinutes % 60))"
        return "\(s) – \(e)"
    }

    private func setWindowLength(_ minutes: Int) {
        windowStartMinutes = max(0, windowEndMinutes - minutes)
        if enabled { bleManager.scheduleFallbackAlarm() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: enabled ? "alarm.waves.left.and.right.fill" : "alarm")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(enabled ? DS.Colors.violet : DS.Colors.textMuted)
                    .symbolRenderingMode(.hierarchical)
                Text("SMART ALARM")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DS.Colors.textFaint)
                    .tracking(1.2)
                Spacer()
                Toggle("", isOn: $enabled)
                    .labelsHidden()
                    .tint(DS.Colors.violet)
                    .onChange(of: enabled) { _, isOn in
                        let h = UIImpactFeedbackGenerator(style: .light)
                        h.impactOccurred()
                        if isOn {
                            bleManager.scheduleFallbackAlarm()
                        } else {
                            bleManager.cancelFallbackAlarm()
                        }
                    }
            }

            // 🍷 Drinking tonight — flips the whole alarm into alcohol-recovery
            // mode (no early wake, humane noon backstop). Server-flagged + synced.
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("\u{1F377}").font(.system(size: 15))
                    Text("Drinking tonight")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Colors.textPrimary)
                    Spacer()
                    // Computed binding: getter reflects server truth; setter ONLY
                    // fires on a real user tap. (A @State + onChange re-fired on the
                    // programmatic onAppear/sync assignment, which re-flagged the
                    // NEXT day on every launch — alcohol mode walked forward forever.)
                    Toggle("", isOn: Binding(
                        get: { bleManager.tonightPlanMode == "alcohol" },
                        set: { isOn in
                            let h = UIImpactFeedbackGenerator(style: .light)
                            h.impactOccurred()
                            Task {
                                _ = await bleManager.supabase.setDrinkingTonight(isOn)
                                await bleManager.syncTonightPlan()
                            }
                        }
                    ))
                    .labelsHidden()
                    .tint(DS.Colors.amber)
                }
                if bleManager.tonightPlanMode == "alcohol" {
                    Text(bleManager.tonightPlanNote.isEmpty
                         ? "No early alarm tonight — you sleep until your body is done."
                         : bleManager.tonightPlanNote)
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Colors.textSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(DS.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Colors.amber.opacity(bleManager.tonightPlanMode == "alcohol" ? 0.10 : 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(DS.Colors.amber.opacity(0.25), lineWidth: 0.5)
                    )
            )

            // Status line — green/violet/grey based on enabled + window
            HStack(spacing: 6) {
                Circle()
                    .fill(enabled ? DS.Colors.success : DS.Colors.textMuted)
                    .frame(width: 6, height: 6)
                Text(enabled
                     ? "Will wake you between \(formatWindow())"
                     : "Disabled — toggle on to set wake window")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.Colors.textPrimary)
                Spacer()
            }

            // Wake-by picker (sets window END; START auto-computes)
            HStack {
                Text("Wake by")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.Colors.textPrimary)
                Spacer()
                DatePicker("", selection: wakeByDate, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .tint(DS.Colors.violet)
                    .disabled(!enabled)
            }

            // Window length segmented
            HStack(spacing: 6) {
                ForEach([15, 30, 45], id: \.self) { mins in
                    let isSelected = windowLength == mins
                    Button {
                        let h = UIImpactFeedbackGenerator(style: .light)
                        h.impactOccurred()
                        setWindowLength(mins)
                    } label: {
                        Text("\(mins) min")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(isSelected ? .white : DS.Colors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(isSelected ? DS.Colors.violet : DS.Colors.surface)
                                    .overlay(Capsule().stroke(DS.Colors.border, lineWidth: isSelected ? 0 : 0.5))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!enabled)
                }
            }
            .opacity(enabled ? 1.0 : 0.45)

            // Test now — schedules a 10-second-out notification so Fabi can
            // verify the alarm path (sound + lock screen + Dynamic Island)
            // works on his phone before trusting it overnight.
            Button {
                let h = UIImpactFeedbackGenerator(style: .medium)
                h.impactOccurred()
                scheduleTestNotification()
                testQueued = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                    testQueued = false
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: testQueued ? "bell.badge.fill" : "bell.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(testQueued ? "Test queued — fires in ~10s" : "Test now")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(DS.Colors.violet)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(DS.Colors.violet.opacity(0.10))
                        .overlay(Capsule().stroke(DS.Colors.violet.opacity(0.30), lineWidth: 0.5))
                )
            }
            .buttonStyle(.plain)
            .disabled(testQueued)

            // Overnight timeline — what's actually scheduled. Helps Fabi
            // trust the system and verify the schedule looks right before bed.
            if enabled {
                Divider().background(DS.Colors.border)

                VStack(alignment: .leading, spacing: 6) {
                    Text("TONIGHT'S SCHEDULE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DS.Colors.textFaint)
                        .tracking(1.0)
                        .padding(.bottom, 2)

                    timelineRow(
                        time: formatTime(max(0, windowStartMinutes - 25)),
                        label: "Pre-wake nudge",
                        detail: "Single soft haptic — primes light-sleep transition",
                        color: DS.Colors.teal
                    )
                    timelineRow(
                        time: formatTime(windowStartMinutes),
                        label: "Window opens",
                        detail: "Watching for light-sleep moment",
                        color: DS.Colors.violet
                    )
                    timelineRow(
                        time: formatTime(windowEndMinutes),
                        label: "Hard wake",
                        detail: "Fires no matter what — 30s sustained vibration",
                        color: DS.Colors.amber
                    )
                }

                Divider().background(DS.Colors.border)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(bleManager.heartRate > 0 ? DS.Colors.success : DS.Colors.warning)
                            .frame(width: 6, height: 6)
                        Text(bleManager.heartRate > 0
                             ? "Strap connected · light-sleep detection live"
                             : "Strap not streaming · time-based fallback only")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.Colors.textSecondary)
                        Spacer()
                    }
                    Text("Light-sleep window uses your HRV slope + sleep stage classifier. If BLE drops overnight, the hard-wake at \(formatTime(windowEndMinutes)) fires a guaranteed system alarm chain regardless.")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Colors.textMuted)
                        .lineSpacing(2)
                }
            } else {
                Text("Toggle on to schedule tonight's wake. The fallback only fires when the alarm is enabled.")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Colors.textMuted)
            }
        }
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(DS.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(DS.Colors.violet.opacity(enabled ? 0.30 : 0.12), lineWidth: 0.5)
                )
        )
    }

    private func formatTime(_ mins: Int) -> String {
        "\(String(format: "%02d", mins / 60)):\(String(format: "%02d", mins % 60))"
    }

    /// One row in the overnight timeline — colored dot, time on the left,
    /// label + detail on the right. Visually breaks up the card so it's
    /// scannable instead of a wall of small text.
    @ViewBuilder
    private func timelineRow(time: String, label: String, detail: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 2) {
                Text(time)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                    .monospacedDigit()
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
            }
            .frame(width: 40, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Colors.textMuted)
                    .lineLimit(2)
            }
            Spacer()
        }
    }

    /// Test alarm — fires the EXACT same notification chain the real alarm
    /// uses overnight, so the buzz/vibration pattern Fabi hears in the test
    /// matches what he'll wake to. 10 notifications, 2s apart = ~20s of
    /// sustained vibration. Lock phone before tapping to verify lock-screen +
    /// Dynamic Island behavior.
    private func scheduleTestNotification() {
        bleManager.scheduleAlarmBuzzChain(
            title: "⏰ Test alarm",
            body: "If you got this, the smart alarm path works. This is the exact buzz pattern overnight.",
            count: 10,
            spacingSec: 2.0,
            firstDelaySec: 8.0,
            idPrefix: "lucid_smart_alarm_test"
        )
    }
}
