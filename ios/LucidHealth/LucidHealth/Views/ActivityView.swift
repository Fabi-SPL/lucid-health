import SwiftUI

/// Timeline tab — one chronological feed for the day. Mixes:
///   • Sleep window (single row, opens SleepAdjustSheet)
///   • Activities (manual + auto-detected)
///   • Food / intake (espresso, meals — anything in food_entries today)
///   • Active session (live, when ble.manualActivityType is set)
///
/// Each row is editable. Activities → ActivityEditSheet. Food → EditFoodEntrySheet.
/// Sleep → SleepAdjustSheet. Swipe-trailing for delete on List rows.
///
/// Replaces the old "pending detections + corrections" dev panel — those were
/// debug surfaces, not product surfaces. Now the page reads like a story of
/// the day instead of an admin console.
struct ActivityView: View {
    @ObservedObject var ble: BLEManager
    @ObservedObject private var engine: HealthEngine

    @State private var activities: [ActivityEvent] = []
    @State private var foods: [FoodEntry] = []
    @State private var isLoading = true
    @State private var editingActivity: ActivityEvent?
    @State private var editingFood: FoodEntry?
    @State private var showSleepAdjust = false
    @State private var showBacktrackCreate = false
    @State private var deletingId: String?
    @State private var customActivityName = ""
    @State private var appeared = false

    init(ble: BLEManager) {
        self.ble = ble
        self._engine = ObservedObject(wrappedValue: ble.healthEngine)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: DS.Spacing.lg, pinnedViews: []) {
                heroHeader
                    .entrance(appeared, index: 0)

                if let manual = ble.manualActivityType, let start = ble.manualActivityStart {
                    activeSessionRow(type: manual, start: start)
                        .padding(.horizontal, DS.Spacing.md)
                        .entrance(appeared, index: 1)
                }

                feedSection
                    .entrance(appeared, index: 2)

                quickAddSection
                    .entrance(appeared, index: 3)

                Color.clear.frame(height: DS.Spacing.xl)
            }
            .padding(.top, DS.Spacing.xs)
        }
        .background(AuroraBackground().ignoresSafeArea())
        .task {
            await refresh()
            withAnimation(DS.Anim.cardAppear) { appeared = true }
        }
        .refreshable { await refresh() }
        .sheet(item: $editingActivity) { activity in
            ActivityEditSheet(
                mode: .edit(activity),
                ble: ble,
                onSaved: { Task { await refresh() } },
                onDeleted: { Task { await refresh() } }
            )
            .presentationDetents([.large])
        }
        .sheet(item: $editingFood) { food in
            EditFoodEntrySheet(
                entry: food,
                onSaved: { updated in
                    if let idx = foods.firstIndex(where: { $0.id == updated.id }) {
                        foods[idx] = updated
                    }
                    editingFood = nil
                },
                onCancel: { editingFood = nil }
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showBacktrackCreate) {
            ActivityEditSheet(
                mode: .create(defaultStart: Date().addingTimeInterval(-30 * 60)),
                ble: ble,
                onSaved: { Task { await refresh() } },
                onDeleted: {}
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showSleepAdjust) {
            SleepAdjustSheet(engine: engine, ble: ble) {
                showSleepAdjust = false
                Task { await refresh() }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Hero

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                TwoToneHeadline(
                    primary: "Today",
                    secondary: " · \(formatDateLong(Date()))",
                    font: .system(size: 28, weight: .heavy, design: .rounded)
                )
                Spacer()
                Text("\(timelineRows.count)")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(DS.Colors.violet)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            Text("Sleep, sessions, intake — one feed. Swipe to edit.")
                .font(.system(size: 13))
                .foregroundStyle(DS.Colors.textMuted)
        }
        .padding(.horizontal, DS.Spacing.md)
    }

    // MARK: - Active session

    @ViewBuilder
    private func activeSessionRow(type: String, start: Date) -> some View {
        HStack(spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .stroke(DS.Colors.violet.opacity(0.30), lineWidth: 2)
                    .frame(width: 36, height: 36)
                Circle()
                    .fill(DS.Colors.violet)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(DS.Colors.violet.opacity(0.6), lineWidth: 1)
                            .scaleEffect(1.8)
                            .opacity(0.8)
                    )
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("LIVE")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(DS.Colors.violet)
                        .tracking(1.2)
                    Text(activityName(type))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.textPrimary)
                }
                Text("\(timeAgo(start)) · \(ble.heartRate) bpm")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Colors.textMuted)
                    .monospacedDigit()
            }

            Spacer()

            Button {
                DS.Haptic.commit()
                ble.endManualActivity()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    Task { await refresh() }
                }
            } label: {
                Text("End")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(DS.Colors.violet))
            }
            .buttonStyle(.plain)
        }
        .padding(DS.Spacing.md)
        .accentGlassCard(tint: DS.Colors.violet)
    }

    // MARK: - Feed

    @ViewBuilder
    private var feedSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: 6) {
                Circle().fill(DS.Colors.violet).frame(width: 6, height: 6)
                Text("FEED")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DS.Colors.textFaint)
                    .tracking(1.2)
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.mini).tint(DS.Colors.violet)
                }
            }
            .padding(.horizontal, DS.Spacing.md + 4)

            if isLoading && timelineRows.isEmpty {
                emptyState(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Loading",
                    subtitle: "Pulling today's events."
                )
            } else if timelineRows.isEmpty {
                emptyState(
                    icon: "calendar.badge.clock",
                    title: "Nothing logged yet",
                    subtitle: "Double-tap your strap, start a session, or tap below."
                )
            } else {
                timelineList
            }
        }
    }

    private var timelineList: some View {
        VStack(spacing: 0) {
            ForEach(Array(timelineRows.enumerated()), id: \.element.id) { idx, row in
                timelineRow(row, isFirst: idx == 0, isLast: idx == timelineRows.count - 1)
            }
        }
        .padding(.horizontal, DS.Spacing.md)
    }

    @ViewBuilder
    private func timelineRow(_ row: TimelineRow, isFirst: Bool, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Rail: vertical line + dot
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : DS.Colors.border)
                    .frame(width: 1, height: 12)
                ZStack {
                    Circle()
                        .fill(DS.Colors.surface)
                        .frame(width: 14, height: 14)
                    Circle()
                        .fill(row.tint)
                        .frame(width: 8, height: 8)
                }
                Rectangle()
                    .fill(isLast ? Color.clear : DS.Colors.border)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 14)

            // Content
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(row.emoji)
                        .font(.system(size: 16))
                    Text(row.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.textPrimary)
                    Spacer(minLength: 0)
                    Text(formatTime(row.time))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DS.Colors.textMuted)
                }

                if !row.subtitle.isEmpty {
                    Text(row.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Colors.textSecondary)
                        .lineLimit(2)
                }

                if !row.metaBadges.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(row.metaBadges, id: \.self) { badge in
                            Text(badge)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(row.tint)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(row.tint.opacity(0.10))
                                        .overlay(Capsule().stroke(row.tint.opacity(0.20), lineWidth: 0.5))
                                )
                        }
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(DS.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(DS.Colors.border, lineWidth: 0.5)
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture { handleTap(row) }
            .contextMenu {
                Button { handleTap(row) } label: {
                    Label("Edit", systemImage: "slider.horizontal.3")
                }
                if row.isDeletable {
                    Button(role: .destructive) {
                        handleDelete(row)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .opacity(deletingId == row.id ? 0.45 : 1)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Quick add

    private var quickAddSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: 6) {
                Circle().fill(DS.Colors.teal).frame(width: 6, height: 6)
                Text("ADD")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DS.Colors.textFaint)
                    .tracking(1.2)
            }
            .padding(.horizontal, DS.Spacing.md + 4)

            VStack(spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.sm) {
                    TextField("Start an activity… (Deep work, Walk)", text: $customActivityName)
                        .font(.system(size: 14))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(DS.Colors.surfaceElevated)
                        .clipShape(Capsule())
                        .foregroundStyle(DS.Colors.textPrimary)
                        .submitLabel(.go)
                        .onSubmit { startCustomActivity() }
                    Button {
                        startCustomActivity()
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(trimmedCustom.isEmpty ? DS.Colors.textMuted : DS.Colors.violet)
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmedCustom.isEmpty)
                }

                HStack(spacing: 8) {
                    quickPill("Backtrack", icon: "clock.arrow.circlepath", color: DS.Colors.amber) {
                        showBacktrackCreate = true
                    }
                    quickPill("Adjust sleep", icon: "moon.zzz.fill", color: DS.Colors.violet) {
                        showSleepAdjust = true
                    }
                    quickPill("Quick tag", icon: "sparkles", color: DS.Colors.teal) {
                        ble.showDoubleTapSheet = true
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.md)
        }
    }

    private func quickPill(_ label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(color.opacity(0.10))
                    .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(DS.Colors.violet.opacity(0.6))
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.textPrimary)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(DS.Colors.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(DS.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(DS.Colors.border, lineWidth: 0.5)
                )
        )
        .padding(.horizontal, DS.Spacing.md)
    }

    // MARK: - Data

    private var timelineRows: [TimelineRow] {
        var rows: [TimelineRow] = []

        // Sleep — show as a single row at wake time, if we have a reasonable window
        if let bed = engine.sleepStartTime,
           let wake = engine.sleepEndTime {
            let gap = wake.timeIntervalSince(bed)
            if gap >= 3 * 3600 && gap <= 14 * 3600 {
                let h = Int(gap / 3600)
                let m = Int((gap.truncatingRemainder(dividingBy: 3600)) / 60)
                rows.append(TimelineRow(
                    id: "sleep_\(bed.timeIntervalSince1970)",
                    kind: .sleep,
                    time: wake,
                    emoji: "🌙",
                    title: "Slept \(h)h \(m)m",
                    subtitle: "\(formatTime(bed)) → \(formatTime(wake))",
                    metaBadges: [],
                    tint: DS.Colors.violet,
                    isDeletable: false,
                    payload: .sleep
                ))
            }
        }

        // Activities
        for a in activities {
            rows.append(TimelineRow(
                id: a.id,
                kind: .activity,
                time: a.startedAt,
                emoji: emojiForActivity(a.activityType),
                title: activityName(a.activityType),
                subtitle: activityNotes(a),
                metaBadges: activityBadges(a),
                tint: a.source == "auto" ? DS.Colors.success : DS.Colors.violet,
                isDeletable: true,
                payload: .activity(a)
            ))
        }

        // Foods. Stable id required — `UUID().uuidString` fallback was a
        // crash bug: timelineRows is a computed property running every body
        // cycle, so a fallback UUID generated each render meant SwiftUI saw
        // every row as new → infinite re-render → broken scroll → crash.
        // capturedAt is a real backend timestamp and unique enough as a
        // deterministic fallback id.
        for f in foods {
            let stableId = f.id?.uuidString ?? "food_\(f.capturedAt.timeIntervalSince1970)"
            rows.append(TimelineRow(
                id: stableId,
                kind: .food,
                time: f.capturedAt,
                emoji: emojiForFood(f),
                title: f.caption ?? foodTitle(f),
                subtitle: foodSubtitle(f),
                metaBadges: foodBadges(f),
                tint: DS.Colors.amber,
                isDeletable: true,
                payload: .food(f)
            ))
        }

        return rows.sorted { $0.time > $1.time }
    }

    private func refresh() async {
        async let actsTask = ble.supabase.fetchTodayActivities()
        async let foodsTask = ble.supabase.fetchRecentFoodEntries(limit: 50)
        let a = await actsTask
        let f = (try? await foodsTask) ?? []
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        let todayFoods = f.filter { $0.capturedAt >= startOfToday }

        await MainActor.run {
            self.activities = a
            self.foods = todayFoods
            self.isLoading = false
        }
    }

    private func handleTap(_ row: TimelineRow) {
        switch row.payload {
        case .activity(let a): editingActivity = a
        case .food(let f): editingFood = f
        case .sleep: showSleepAdjust = true
        }
    }

    private func handleDelete(_ row: TimelineRow) {
        deletingId = row.id
        Task {
            switch row.payload {
            case .activity(let a):
                let ok = await ble.supabase.deleteActivity(id: a.id)
                if ok { await MainActor.run { activities.removeAll { $0.id == a.id } } }
            case .food(let f):
                if let id = f.id?.uuidString {
                    let ok = await ble.supabase.deleteFoodEntry(id: id)
                    if ok { await MainActor.run { foods.removeAll { $0.id == f.id } } }
                }
            case .sleep:
                break
            }
            await MainActor.run { deletingId = nil }
        }
    }

    private func startCustomActivity() {
        guard !trimmedCustom.isEmpty else { return }
        let h = UIImpactFeedbackGenerator(style: .light)
        h.impactOccurred()
        ble.startManualActivity(type: trimmedCustom.lowercased())
        customActivityName = ""
    }

    private var trimmedCustom: String {
        customActivityName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Formatting helpers

    private func formatTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: d)
    }

    private func formatDateLong(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: d)
    }

    private func timeAgo(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h \(s % 3600 / 60)m"
    }

    private func activityName(_ type: String) -> String {
        type.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func activityNotes(_ a: ActivityEvent) -> String {
        if let notes = a.notes, !notes.isEmpty { return notes }
        return ""
    }

    private func activityBadges(_ a: ActivityEvent) -> [String] {
        var b: [String] = []
        if let end = a.endedAt {
            let m = max(Int(end.timeIntervalSince(a.startedAt) / 60), 1)
            if m < 60 { b.append("\(m)m") } else { b.append("\(m / 60)h \(m % 60)m") }
        }
        if let hr = a.hrAvg { b.append("\(hr) bpm") }
        b.append(a.source.capitalized)
        return b
    }

    private func emojiForActivity(_ type: String) -> String {
        let key = type.lowercased()
        if key.contains("workout") || key.contains("exercise") { return "🏋️" }
        if key.contains("walk") { return "🚶" }
        if key.contains("run") { return "🏃" }
        if key.contains("nap") { return "😴" }
        if key.contains("sauna") { return "🧖" }
        if key.contains("cold") { return "🥶" }
        if key.contains("meditation") || key.contains("breath") { return "🧘" }
        if key.contains("deep") || key.contains("focus") { return "🧠" }
        if key.contains("read") { return "📖" }
        if key.contains("creative") || key.contains("paint") { return "🎨" }
        if key.contains("social") { return "💬" }
        if key.contains("drive") || key.contains("ride") { return "🛵" }
        return "⚡"
    }

    private func foodTitle(_ f: FoodEntry) -> String {
        if let first = f.items.first?.name { return first.capitalized }
        return "Meal"
    }

    private func foodSubtitle(_ f: FoodEntry) -> String {
        let names = f.items.prefix(3).map { $0.name }.joined(separator: ", ")
        return names.isEmpty ? "" : names
    }

    private func foodBadges(_ f: FoodEntry) -> [String] {
        var b: [String] = []
        if let kcal = f.totalKcal, kcal > 0 { b.append("\(kcal) kcal") }
        if let nova = f.novaAvg { b.append("NOVA \(String(format: "%.1f", nova))") }
        return b
    }

    private func emojiForFood(_ f: FoodEntry) -> String {
        let key = (f.caption ?? f.items.first?.name ?? "").lowercased()
        if f.items.contains(where: { $0.isAlcohol == true }) { return "🍷" }
        if f.items.contains(where: { $0.isSupplement == true }) { return "💊" }
        if f.items.contains(where: { $0.isDrink == true }) {
            if key.contains("espresso") || key.contains("coffee") || key.contains("cappuccino") { return "☕" }
            if key.contains("water") { return "💧" }
            return "🥤"
        }
        if key.contains("breakfast") || key.contains("egg") { return "🍳" }
        if key.contains("salad") { return "🥗" }
        if key.contains("rice") || key.contains("chicken") { return "🍚" }
        return "🍽️"
    }
}

// MARK: - Row model

private struct TimelineRow: Identifiable {
    let id: String
    let kind: Kind
    let time: Date
    let emoji: String
    let title: String
    let subtitle: String
    let metaBadges: [String]
    let tint: Color
    let isDeletable: Bool
    let payload: Payload

    enum Kind { case sleep, activity, food }
    enum Payload {
        case sleep
        case activity(ActivityEvent)
        case food(FoodEntry)
    }
}
