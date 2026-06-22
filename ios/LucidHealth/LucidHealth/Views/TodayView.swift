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
    @State private var bbTrend: [BodyBatteryPoint] = []
    @State private var saveSuccessCount = 0
    @State private var saveErrorCount = 0
    @StateObject private var modeStore = AppModeStore()
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
                // Greeting moved to the prominent in-scroll header; toolbar is just
                // the wordmark now (no duplicate greeting).
                TwoToneHeadline(
                    primary: "Lucid",
                    secondary: "Health",
                    font: .system(size: 17, weight: .heavy, design: .rounded)
                )
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                SettingsGearButton()
            }
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
                    // v121: pull the server-authoritative Body Battery (reservoir
                    // − live drain) on every foreground. App is display-only now.
                    if let bb = await bleManager.supabase.fetchBodyBatteryAnchor() {
                        await MainActor.run { bleManager.healthEngine.bodyBattery = bb }
                    }
                    // 24h body-battery curve for the hero chart (smooth, server-built)
                    let series = await bleManager.supabase.fetchBodyBatterySeries()
                    await MainActor.run { bbTrend = series }
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

    // MARK: - Greeting header (prominent, adaptive, dated)

    private var greetingPhrase: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:       return "Still up"
        }
    }

    private var greetingDateLine: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMMM"
        f.locale = Locale(identifier: "en_US")
        return f.string(from: Date()).uppercased()
    }

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            (
                Text(greetingPhrase + ", ")
                    .foregroundStyle(DS.Colors.textPrimary)
                + Text("Fabi")
                    .foregroundStyle(DS.Colors.violet)
            )
            .font(.system(size: 30, weight: .heavy, design: .rounded))
            .kerning(-0.6)

            Text(greetingDateLine)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(DS.Colors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Spacing.md)
        .padding(.top, DS.Spacing.sm)
        .padding(.bottom, DS.Spacing.xs)
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

                // Prominent adaptive greeting — the day's anchor. Time-aware phrase
                // + today's full date (so it's also a live "you're on a fresh build"
                // tell). Replaces the tiny nav-bar greeting as the warm entry point.
                greetingHeader
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 14)
                    .animation(DS.Anim.cardAppear, value: appeared)

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
                    // v111 live readiness coach — how far the body is from sleep-ready,
                    // server-computed from the last 10 min of stream vs his baselines.
                    WindDownCoachCard(bleManager: bleManager)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.top, DS.Spacing.md)
                        .opacity(appeared ? 1 : 0)
                        .animation(DS.Anim.cardAppear, value: appeared)
                        .scrollSectionTransition()

                    SmartAlarmCard(bleManager: bleManager)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.top, DS.Spacing.md)
                        .opacity(appeared ? 1 : 0)
                        .animation(DS.Anim.cardAppear, value: appeared)
                        .scrollSectionTransition()
                }

                // GO BACK OR GET UP? — in-window wake coach. Surfaces when Fabi
                // wakes early: either he tapped "I'm awake" (→ justWokeUp) or it's
                // the 05–10 morning window before he's confirmed up. Asks the server
                // for a personalized go-back / get-up call and (if go-back) arms a
                // gentle wake at his next cycle boundary. Once per day.
                if modeStore.current == .justWokeUp || modeStore.current == .morning {
                    WakeCoachCard(bleManager: bleManager)
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

                // Outside context — weather + PC, grouped under a collapsed
                // "Context" disclosure so the home screen stays calm but the raw
                // data is one tap away ("keep all, group ambient").
                CollapsibleContext(title: "CONTEXT", icon: "globe.europe.africa.fill") {
                    VStack(spacing: DS.Spacing.md) {
                        WeatherContextTile()
                            .padding(.horizontal, DS.Spacing.md)
                        PCActivityTile()
                            .padding(.horizontal, DS.Spacing.md)
                    }
                    .padding(.top, DS.Spacing.sm)
                }
                .padding(.top, DS.Spacing.lg)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)
                .animation(DS.Anim.stagger(index: 9), value: appeared)
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
                strain: engine.strainScore,
                trend: bbTrend
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

            // Recovery context line — PINCH style, pre-baked, no AI narration.
            // Followed by the live "vs your normal" recovery percentile (v110).
            VStack(spacing: DS.Spacing.sm) {
                Text(recoveryContextLine)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                if engine.recoveryScore > 0 {
                    PersonalPercentileChip(metric: "recovery_score", value: engine.recoveryScore)
                }
            }
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
                    PersonalPercentileChip(metric: "hrv_avg", value: engine.currentRMSSD)
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

// MARK: - Personal Percentile Chip (v110 "vs your normal")
// Live percentile of a value against his OWN rolling history. Self-contained async
// fetch — renders nothing until it resolves, and nothing if there's no baseline.
// Drop next to any metric. Internal (not private) so Health can reuse it.
struct PersonalPercentileChip: View {
    let metric: String
    let value: Double
    var windowDays: Int = 30

    @State private var pct: Double?

    var body: some View {
        Group {
            if let p = pct {
                HStack(spacing: 3) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text("\(ordinal(Int(p.rounded()))) for you")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(tint(p))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(tint(p).opacity(0.12)))
                .overlay(Capsule().stroke(tint(p).opacity(0.25), lineWidth: 0.5))
            }
        }
        .task {
            if pct == nil, value > 0 {
                pct = await SupabaseClient.shared.fetchPersonalPercentile(
                    metric: metric, value: value, windowDays: windowDays)
            }
        }
    }

    private func tint(_ p: Double) -> Color {
        if p >= 66 { return DS.Colors.teal }
        if p >= 33 { return DS.Colors.amber }
        return DS.Colors.textMuted
    }

    private func ordinal(_ n: Int) -> String {
        let suffix: String
        switch n % 100 {
        case 11, 12, 13: suffix = "th"
        default:
            switch n % 10 {
            case 1: suffix = "st"; case 2: suffix = "nd"; case 3: suffix = "rd"; default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }
}

// MARK: - Collapsible Context (groups ambient tiles — weather, PC)
// Header row + chevron; expanded state persists. Collapsed by default so Today's
// top stays calm while keeping every raw data point one tap away.
private struct CollapsibleContext<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: () -> Content
    @AppStorage("lucid_today_context_open") private var open: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                let h = UIImpactFeedbackGenerator(style: .light); h.impactOccurred()
                withAnimation(DS.Anim.cardAppear) { open.toggle() }
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.Colors.textMuted)
                    Text(title)
                        .font(DS.Font.label)
                        .foregroundStyle(DS.Colors.textMuted)
                        .tracking(0.8)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DS.Colors.textFaint)
                        .rotationEffect(.degrees(open ? 0 : -90))
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
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
// WakeCoachCard — "Go back or get up?" The in-window decision helper. When Fabi
// wakes before his sleep target, it asks plan_back_to_sleep and shows ONE verdict
// + action. If he goes back, it arms a gentle wake at his next boundary so he
// never gets woken mid-cycle (the thing that makes going back feel pointless).
// Shows once per day (UserDefaults date guard).
private struct WakeCoachCard: View {
    @ObservedObject var bleManager: BLEManager

    @State private var plan: BackToSleepPlan?
    @State private var loading = true
    @State private var dismissed = false

    @AppStorage("lucid_goback_handled_date") private var handledDate: String = ""

    private var todayKey: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
    private var alreadyHandled: Bool { handledDate == todayKey }
    private var accent: Color {
        (plan?.shouldGoBack ?? false) ? DS.Colors.violet : DS.Colors.warning
    }

    var body: some View {
        if dismissed || alreadyHandled {
            EmptyView()
        } else {
            content.task { await load() }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: 8) {
                Image(systemName: "bed.double.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                    .symbolRenderingMode(.hierarchical)
                Text("GO BACK OR GET UP?")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DS.Colors.textFaint)
                    .tracking(1.2)
                Spacer()
            }

            if loading {
                HStack(spacing: 8) {
                    ProgressView().tint(DS.Colors.textMuted)
                    Text("Checking your night\u{2026}")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            } else if let plan = plan {
                Text(plan.headline)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .tracking(-0.3)
                    .foregroundStyle(DS.Colors.textPrimary)
                Text(plan.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(DS.Colors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                actions(for: plan)
            } else {
                Text("Couldn't reach your sleep data. Trust your gut \u{2014} under an hour left, just get up.")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.Colors.textSecondary)
                Button { handle() } label: {
                    Text("Got it")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Colors.textMuted)
                }
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accentGlassCard(tint: accent)
    }

    @ViewBuilder
    private func actions(for plan: BackToSleepPlan) -> some View {
        if plan.shouldGoBack {
            VStack(spacing: 8) {
                Button {
                    if let w = plan.wakeAt { bleManager.armGoBackWake(at: w) }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    handle()
                } label: {
                    Text(plan.wakeLabel.isEmpty
                         ? "Sleep \u{2014} wake me at my time"
                         : "Sleep \u{2014} wake me at \(plan.wakeLabel)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(DS.Colors.violet))
                }
                Button { handle() } label: {
                    Text("I'm up anyway")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DS.Colors.textMuted)
                }
            }
        } else {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                handle()
            } label: {
                Text("Start my day")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(DS.Colors.warning))
            }
        }
    }

    private func load() async {
        let start = await currentSleepStart()
        let result = await SupabaseClient.shared.planBackToSleep(sleepStart: start)
        await MainActor.run {
            self.plan = result
            self.loading = false
        }
    }

    @MainActor
    private func currentSleepStart() -> Date {
        bleManager.healthEngine.sleepStartTime ?? Calendar.current.startOfDay(for: Date())
    }

    private func handle() {
        handledDate = todayKey
        withAnimation(.easeOut(duration: 0.25)) { dismissed = true }
    }
}

// MARK: - Wind-Down Coach (v111 Sleep Readiness Index)
// Shown in wind-down mode above the smart alarm. Reads the last 10 min of strap
// stream vs his personal sleep baselines (server-computed) and tells him how far
// his body is from sleep-ready + roughly how long to wind down. Display-only.
private struct WindDownCoachCard: View {
    @ObservedObject var bleManager: BLEManager
    @State private var sri: SleepReadiness?
    @State private var loading = true

    private var accent: Color {
        guard let s = sri else { return DS.Colors.textMuted }
        if s.ready { return DS.Colors.success }
        return s.sri >= 40 ? DS.Colors.warning : DS.Colors.danger
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: 8) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                    .symbolRenderingMode(.hierarchical)
                Text("SLEEP READINESS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DS.Colors.textFaint)
                    .tracking(1.2)
                Spacer()
                if let s = sri {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(s.sri)")
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundStyle(accent)
                            .monospacedDigit()
                        Text("/100")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DS.Colors.textFaint)
                    }
                }
            }

            if loading {
                HStack(spacing: 8) {
                    ProgressView().tint(DS.Colors.textMuted)
                    Text("Reading your body\u{2026}")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let s = sri {
                Text(s.message)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .tracking(-0.2)
                    .foregroundStyle(DS.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: DS.Spacing.lg) {
                    statCell(value: "\(Int(s.hrNow))", label: "HR now", color: DS.Colors.pink)
                    statCell(value: "\(Int(s.hrFloor))", label: "your floor", color: DS.Colors.textSecondary)
                    statCell(value: s.ready ? "ready" : "~\(s.etaMin)m",
                             label: s.ready ? "now" : "to ready", color: accent)
                }
                .padding(.top, 2)
            } else {
                Text("No recent strap data \u{2014} put the band on to read your wind-down.")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.Colors.textSecondary)
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accentGlassCard(tint: accent)
        .task { await load() }
    }

    private func statCell(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DS.Colors.textFaint)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        let r = await SupabaseClient.shared.fetchSleepReadiness()
        await MainActor.run { self.sri = r; self.loading = false }
    }
}

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
        .accentGlassCard(tint: DS.Colors.violet, active: enabled)
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
