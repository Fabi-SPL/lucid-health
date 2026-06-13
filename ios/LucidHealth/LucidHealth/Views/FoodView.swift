import SwiftUI
import PhotosUI

// MARK: - FoodView
// Principle #11: format diversity — METRICS (bento) → CHIPS (filter) → CARDS (meal list)
// Principle #5: category dot food=amber on each meal entry
// Principle #4: pill radius 100 on all filter chips

struct FoodView: View {
    @EnvironmentObject private var bleManager: BLEManager
    @State private var entries: [FoodEntry] = []
    @State private var favorites: [FoodFavorite] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var filter: FoodFilter = .all
    @State private var showCamera = false
    @State private var showBarcode = false
    @State private var showManual = false
    @State private var showFABMenu = false
    @State private var showBuilder = false
    @State private var appeared = false
    @State private var saveSuccessCount = 0
    @State private var saveErrorCount = 0
    @State private var deleteSuccessCount = 0
    @State private var pendingDelete: FoodEntry?
    @State private var editing: FoodEntry?
    @State private var detailEntry: FoodEntry?

    private var filtered: [FoodEntry] {
        switch filter {
        case .all:     return entries
        case .photo:   return entries.filter { $0.source == "photo" }
        case .barcode: return entries.filter { $0.source == "barcode" }
        case .quick:   return entries.filter { $0.source == "quick_tag" || $0.source == "quick_log" }
        }
    }

    private var todayEntries: [FoodEntry] { entries.filter(isToday) }
    private var todayKcal: Int { entries.filter(isToday).compactMap(\.totalKcal).reduce(0, +) }
    private var todayMindAvg: Double {
        let t = entries.filter(isToday).compactMap(\.mindScore)
        guard !t.isEmpty else { return 0 }
        return Double(t.reduce(0, +)) / Double(t.count)
    }

    private var todayNovaAvg: Double {
        let vals = entries.filter(isToday).compactMap(\.novaAvg)
        guard !vals.isEmpty else { return 0 }
        return vals.reduce(0, +) / Double(vals.count)
    }

    private var hoursSinceLastMeal: Int? {
        guard let last = entries.first(where: { Calendar.current.isDateInToday($0.capturedAt) }) else { return nil }
        let hours = Int(Date().timeIntervalSince(last.capturedAt) / 3600)
        return hours
    }

    private func isToday(_ e: FoodEntry) -> Bool {
        Calendar.current.isDateInToday(e.capturedAt)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // List instead of ScrollView/LazyVStack — gives us native .swipeActions
            // for entries that won't fight the scroll gesture (the previous custom
            // SwipeActionsCard was eating vertical scrolls).
            List {
                // Top-of-list sections — explicit per-row .padding(.top:) because
                // listRowInsets(EdgeInsets()) + defaultMinListRowHeight 0 kill
                // SwiftUI's native row spacing. Without this they squish flush.
                // Spacing rhythm is intentional:
                //   • Bento — sm above (just under the toolbar)
                //   • Quality — md (related to bento, tighter cluster)
                //   • Fasting — lg (separate concern, more breathing)
                //   • Filter — lg (control affordance, transitions into the list)
                Section {
                    TodayBentoRow(
                        kcal: todayKcal,
                        mindAvg: todayMindAvg,
                        novaAvg: todayNovaAvg,
                        mealCount: todayEntries.count
                    )
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.top, DS.Spacing.sm)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    FavoritesBar(
                        favorites: favorites,
                        onLog: { item in Task { await quickLog(item) } },
                        onLogFavorite: { fav in Task { await logFavorite(fav) } }
                    )
                    .padding(.top, DS.Spacing.md)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    if !todayEntries.isEmpty {
                        FoodQualityRow(entries: todayEntries)
                            .padding(.top, DS.Spacing.md)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }

                    if let hours = hoursSinceLastMeal {
                        FastingTrackerChip(hours: hours)
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.top, DS.Spacing.lg)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }

                    FilterChipRow(selected: $filter)
                        .padding(.top, DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.sm)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                entriesContent

                Color.clear
                    .frame(height: 100)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)

            // FAB
            VStack(spacing: DS.Spacing.sm) {
                if showFABMenu {
                    FABMenu(
                        isOpen: $showFABMenu,
                        onCamera: { showCamera = true },
                        onBarcode: { showBarcode = true },
                        onManual: { showManual = true },
                        onBuild: { showBuilder = true }
                    )
                    .padding(.trailing, DS.Spacing.lg)
                }

                FABButton(isOpen: $showFABMenu)
                    .padding(.trailing, DS.Spacing.lg)
                    .padding(.bottom, 100)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                TwoToneHeadline(primary: "Food", secondary: " · Meals", font: .system(size: 17, weight: .bold, design: .rounded))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                SettingsGearButton()
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView { entry in
                entries.insert(entry, at: 0)
            }
        }
        .fullScreenCover(isPresented: $showBarcode) {
            BarcodeScannerView { entry in
                entries.insert(entry, at: 0)
            }
        }
        .fullScreenCover(isPresented: $showManual) {
            ManualFoodEntrySheet { entry in
                entries.insert(entry, at: 0)
            }
        }
        .fullScreenCover(isPresented: $showBuilder) {
            MealBuilderSheet { entry in
                entries.insert(entry, at: 0)
            }
        }
        .task {
            await loadEntries()
            await loadFavorites()
            withAnimation { appeared = true }
        }
        .sensoryFeedback(.success, trigger: saveSuccessCount)
        .sensoryFeedback(.error, trigger: saveErrorCount)
        .sensoryFeedback(.impact(weight: .medium), trigger: deleteSuccessCount)
        .sheet(item: $editing) { entry in
            EditFoodEntrySheet(
                entry: entry,
                onSaved: { updated in
                    if let idx = entries.firstIndex(where: { $0.id == updated.id }) {
                        entries[idx] = updated
                    }
                    editing = nil
                    deleteSuccessCount += 1  // re-use trigger for haptic on save success
                },
                onCancel: { editing = nil }
            )
            .presentationDetents([.large])
        }
        .sheet(item: $detailEntry) { entry in
            FoodDetailView(entry: entry) { updated in
                if let idx = entries.firstIndex(where: { $0.id == updated.id }) {
                    entries[idx] = updated
                }
            }
        }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { entry in
            Button("Delete", role: .destructive) {
                Task { await delete(entry) }
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: { entry in
            Text(entry.caption ?? entry.items.map(\.name).joined(separator: ", "))
        }
        .overlay(alignment: .top) {
            if let e = error {
                AlertBanner(icon: "exclamationmark.triangle", message: e, color: DS.Colors.pink)
                    .padding(.horizontal, DS.Spacing.md)
            }
        }
    }

    @ViewBuilder
    private var entriesContent: some View {
        if isLoading {
            LoadingState(label: "Loading meals…")
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } else if filtered.isEmpty {
            EmptyGlassState(
                icon: "fork.knife",
                title: "Nothing logged yet",
                detail: filter == .all
                    ? "Tap + to start."
                    : "No entries for this filter."
            )
            .padding(DS.Spacing.md)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else {
            let grouped = Dictionary(grouping: filtered) { entry in
                Calendar.current.startOfDay(for: entry.capturedAt)
            }
            let sortedDays = grouped.keys.sorted(by: >)

            ForEach(sortedDays, id: \.self) { day in
                Section {
                    ForEach(grouped[day]!.sorted { $0.capturedAt > $1.capturedAt }) { entry in
                        EnhancedMealCard(entry: entry)
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical, 4)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .contentShape(Rectangle())
                            .onTapGesture { detailEntry = entry }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingDelete = entry
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    editing = entry
                                } label: {
                                    Label("Edit", systemImage: "square.and.pencil")
                                }
                                .tint(DS.Colors.violet)
                            }
                            .contextMenu {
                                Button {
                                    Task { await saveAsFavorite(entry) }
                                } label: {
                                    Label("Save as favorite", systemImage: "star")
                                }
                                Button {
                                    editing = entry
                                } label: {
                                    Label("Edit", systemImage: "square.and.pencil")
                                }
                                Button(role: .destructive) {
                                    pendingDelete = entry
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    SectionHeader(title: dayLabel(day))
                        .padding(.horizontal, DS.Spacing.md)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
        }
    }

    private var headerSpacer: some View { Color.clear.frame(height: DS.Spacing.sm) }
    private var bottomSpacer: some View { Color.clear.frame(height: 100) }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d. MMMM"
        f.locale = Locale(identifier: "en_US")
        return f
    }()

    private func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date)     { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return Self.dayFormatter.string(from: date)
    }

    private func loadEntries() async {
        isLoading = true
        error = nil
        do {
            entries = try await SupabaseClient.shared.fetchRecentFoodEntries(limit: 60)
        } catch {
            self.error = "Load failed"
        }
        isLoading = false
    }

    private func quickLog(_ item: QuickLogItem) async {
        do {
            let saved = try await SupabaseClient.shared.saveQuickLog(item)
            entries.insert(saved, at: 0)
            // Feed the shared "most used" ranking so this also becomes the
            // Whoop double-tap favorite over time.
            QuickLogHistory.shared.record(
                name: item.name.lowercased(), displayName: item.name,
                emoji: item.emoji, category: item.mirrorCategory, type: item.mirrorType
            )
            saveSuccessCount += 1
        } catch {
            self.error = "Save failed"
            saveErrorCount += 1
        }
    }

    private func loadFavorites() async {
        if let favs = try? await SupabaseClient.shared.fetchFavorites() {
            favorites = favs
        }
    }

    private func logFavorite(_ fav: FoodFavorite) async {
        do {
            let saved = try await SupabaseClient.shared.logFromFavorite(fav)
            entries.insert(saved, at: 0)
            saveSuccessCount += 1
        } catch {
            self.error = "Save failed"
            saveErrorCount += 1
        }
    }

    private func saveAsFavorite(_ entry: FoodEntry) async {
        let trimmed = entry.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = trimmed.isEmpty ? entry.items.map(\.name).joined(separator: ", ") : trimmed
        guard !name.isEmpty else { return }
        do {
            try await SupabaseClient.shared.saveFavorite(from: entry, name: name)
            await loadFavorites()
            saveSuccessCount += 1
        } catch {
            self.error = "Couldn't save favorite"
            saveErrorCount += 1
        }
    }

    private func delete(_ entry: FoodEntry) async {
        guard let id = entry.id?.uuidString else { return }
        let ok = await SupabaseClient.shared.deleteFoodEntry(id: id)
        if ok {
            await MainActor.run {
                entries.removeAll { $0.id == entry.id }
                deleteSuccessCount += 1
                pendingDelete = nil
            }
        } else {
            await MainActor.run {
                self.error = "Delete failed"
                pendingDelete = nil
            }
        }
    }

}

// MARK: - Filter

enum FoodFilter: String, CaseIterable {
    case all     = "All"
    case photo   = "Photo"
    case barcode = "Barcode"
    case quick   = "Quick"
}

private struct FilterChipRow: View {
    @Binding var selected: FoodFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(FoodFilter.allCases, id: \.self) { f in
                    Button {
                        DS.Haptic.select()
                        withAnimation(DS.Anim.quick) { selected = f }
                    } label: {
                        Text(f.rawValue)
                            .font(.system(size: 12, weight: selected == f ? .semibold : .medium, design: .rounded))
                            .foregroundStyle(selected == f ? DS.Colors.violet : DS.Colors.textFaint)
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(selected == f ? DS.Colors.violet.opacity(0.12) : DS.Colors.surface)
                                    .overlay(
                                        Capsule()
                                            .stroke(selected == f ? DS.Colors.violet.opacity(0.3) : DS.Colors.border, lineWidth: 0.5)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.xs)
        }
    }
}

// MARK: - Favorites Bar (one-tap quick log, most-used first)

private struct FavoritesBar: View {
    @ObservedObject private var history = QuickLogHistory.shared
    let favorites: [FoodFavorite]
    let onLog: (QuickLogItem) -> Void
    let onLogFavorite: (FoodFavorite) -> Void

    /// Curated presets, re-sorted so the items you log most float to the front.
    private var items: [QuickLogItem] {
        let counts = Dictionary(history.entries.map { ($0.name, $0.count) }, uniquingKeysWith: { a, _ in a })
        return QuickLogItem.defaults.sorted {
            (counts[$0.name.lowercased()] ?? 0) > (counts[$1.name.lowercased()] ?? 0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("QUICK LOG")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(DS.Colors.textFaint)
                .tracking(1)
                .padding(.horizontal, DS.Spacing.md)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.sm) {
                    // User's saved meals first (violet-tinted), then curated presets.
                    ForEach(favorites) { fav in
                        FavoritePill(favorite: fav) { onLogFavorite(fav) }
                    }
                    ForEach(items) { item in
                        QuickLogPill(item: item) { onLog(item) }
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
            }
        }
    }
}

/// Tap-to-log pill for a user FoodFavorite (emoji + name + kcal). Violet-tinted to
/// distinguish saved meals from the curated single-item quick presets.
private struct FavoritePill: View {
    let favorite: FoodFavorite
    let onTap: () -> Void

    @State private var isPressed = false
    @State private var didLog = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(DS.Anim.quick) { didLog = true }
            onTap()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(DS.Anim.quick) { didLog = false }
            }
        } label: {
            HStack(spacing: 6) {
                Text(favorite.emoji ?? "🍽️")
                    .font(.system(size: 14))
                Text(favorite.name)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(didLog ? DS.Colors.teal : DS.Colors.textPrimary)
                    .lineLimit(1)
                if let k = favorite.totalKcal, k > 0 {
                    Text("\(k)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DS.Colors.textFaint)
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(
                Capsule()
                    .fill(didLog
                          ? DS.Colors.teal.opacity(0.15)
                          : DS.Colors.violet.opacity(0.10))
                    .overlay(
                        Capsule()
                            .stroke(
                                didLog ? DS.Colors.teal.opacity(0.4) : DS.Colors.borderViolet,
                                lineWidth: 0.5
                            )
                    )
            )
            .scaleEffect(isPressed ? 0.95 : (didLog ? 1.03 : 1.0))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(DS.Anim.quick) { isPressed = true } }
                .onEnded   { _ in withAnimation(DS.Anim.quick) { isPressed = false } }
        )
        .animation(DS.Anim.quick, value: didLog)
    }
}

// MARK: - Today Bento Row (4-tile MetricTile grid)

private struct TodayBentoRow: View {
    let kcal: Int
    let mindAvg: Double
    let novaAvg: Double
    let mealCount: Int

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            MetricTile(
                label: "KCAL",
                value: kcal > 0 ? "\(kcal)" : "—",
                unit: "",
                color: DS.Colors.amber
            )
            MetricTile(
                label: "BRAIN Ø",
                value: mindAvg > 0 ? String(format: "%.1f", mindAvg) : "—",
                unit: "/15",
                color: DS.Colors.mindColor(mindAvg)
            )
            MetricTile(
                label: "NOVA Ø",
                value: novaAvg > 0 ? String(format: "%.1f", novaAvg) : "—",
                unit: "",
                color: DS.Colors.novaColor(novaAvg)
            )
            MetricTile(
                label: "TODAY",
                value: "\(mealCount)",
                unit: "meals",
                color: DS.Colors.violet
            )
        }
    }
}

// MARK: - Fasting Tracker Chip

private struct FastingTrackerChip: View {
    let hours: Int

    private var label: String {
        if hours == 0 { return "Just ate" }
        if hours == 1 { return "Last meal 1h ago" }
        return "Last meal \(hours)h ago"
    }

    private var chipColor: Color {
        if hours < 3 { return DS.Colors.teal }
        if hours < 6 { return DS.Colors.amber }
        return DS.Colors.violet
    }

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            CategoryDot(category: .food)
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(chipColor)
            Spacer()
            Text("\(hours)h fast")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(DS.Colors.textFaint)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .glassDefault()
    }
}

// MARK: - Enhanced Meal Card (CategoryDot + StatusChip for NOVA/HRV impact)

private struct EnhancedMealCard: View {
    let entry: FoodEntry

    private var timeString: String {
        entry.capturedAt.formatted(.dateTime.hour().minute())
    }

    private var mindColor: Color {
        DS.Colors.mindColor(Double(entry.mindScore ?? 0))
    }

    private var novaChipStyle: StatusChipStyle? {
        guard let nova = entry.novaAvg else { return nil }
        if nova >= 3.5 { return .danger }
        if nova >= 2.5 { return .amber }
        return .teal
    }

    private var novaChipLabel: String? {
        guard let nova = entry.novaAvg else { return nil }
        if nova >= 3.5 { return "Ultra-processed" }
        if nova >= 2.5 { return "Processed" }
        return "Minimal"
    }

    private var logQuality: Int {
        entry.logQuality ?? FoodEntry.computeLogQuality(source: entry.source, confidence: entry.confidence, items: entry.items)
    }
    private var logQualityStyle: StatusChipStyle {
        switch logQuality {
        case 8...10: return .teal
        case 5...7:  return .amber
        default:     return .danger
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                // Principle #5: category dot — food = amber
                CategoryDot(category: .food)

                Text(entry.caption ?? entry.items.map(\.name).joined(separator: ", "))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)
                    .lineLimit(1)

                Spacer()

                Text(timeString)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(DS.Colors.textFaint)
            }

            HStack(spacing: DS.Spacing.sm) {
                // Left accent bar (mind-score color)
                RoundedRectangle(cornerRadius: 2)
                    .fill(mindColor)
                    .frame(width: 3, height: 28)

                if let kcal = entry.totalKcal, kcal > 0 {
                    Label("\(kcal) kcal", systemImage: "flame.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Colors.amber)
                }

                if let style = novaChipStyle, let label = novaChipLabel {
                    StatusChip(text: label, style: style)
                }

                if let mind = entry.mindScore, mind >= 10 {
                    StatusChip(text: "Brain+", style: .teal, icon: "brain")
                }

                Spacer()

                StatusChip(text: "Q\(logQuality)", style: logQualityStyle)
            }
        }
        .padding(DS.Spacing.md)
        .glassDefault()
    }
}

// MARK: - Food Quality Row (NOVA histogram + alcohol)

private struct FoodQualityRow: View {
    let entries: [FoodEntry]

    // NOVA bucket counts
    private var novaBuckets: [Int] {
        var counts = [0, 0, 0, 0]  // NOVA 1, 2, 3, 4
        for entry in entries {
            for item in entry.items {
                let idx = max(0, min(3, item.novaClass - 1))
                counts[idx] += 1
            }
        }
        return counts
    }

    private var totalItems: Int { novaBuckets.reduce(0, +) }
    private var hasAlcohol: Bool {
        entries.flatMap { $0.items }.contains { $0.mindTags.contains("alcohol") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: 4) {
                Text("NOVA TODAY")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DS.Colors.textFaint)
                    .tracking(1)
                if hasAlcohol {
                    Text("Alcohol")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DS.Colors.amber)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(DS.Colors.amber.opacity(0.12)))
                }
            }

            if totalItems > 0 {
                HStack(spacing: 2) {
                    ForEach(0..<4, id: \.self) { i in
                        let count = novaBuckets[i]
                        if count > 0 {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(novaColor(i + 1))
                                .frame(width: max(4, CGFloat(count) / CGFloat(totalItems) * 200), height: 10)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))

                HStack(spacing: DS.Spacing.sm) {
                    ForEach(0..<4, id: \.self) { i in
                        if novaBuckets[i] > 0 {
                            HStack(spacing: 3) {
                                Circle().fill(novaColor(i + 1)).frame(width: 6, height: 6)
                                Text("N\(i+1): \(novaBuckets[i])")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(DS.Colors.textFaint)
                            }
                        }
                    }
                }
            } else {
                Text("No items today")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Colors.textFaint)
            }
        }
        .padding(DS.Spacing.md)
        .glassDefault()
        .padding(.horizontal, DS.Spacing.md)
    }

    private func novaColor(_ nova: Int) -> Color {
        DS.Colors.novaColor(Double(nova))
    }
}

// MARK: - Food Detail View (tap a meal → full breakdown + body response)

private struct FoodDetailView: View {
    @State private var entry: FoodEntry
    let onChanged: (FoodEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var hr: [String: Any]? = nil
    @State private var hrLoading = true

    init(entry: FoodEntry, onChanged: @escaping (FoodEntry) -> Void) {
        _entry = State(initialValue: entry)
        self.onChanged = onChanged
    }

    // MARK: derived

    private var raw: [String: Any]? {
        guard let s = entry.geminiRawJson, let d = s.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }
    private var mealTotals: [String: Any]? { raw?["meal_totals"] as? [String: Any] }
    private var brain: [String: Any]? { raw?["brain_score"] as? [String: Any] }

    private func intOf(_ a: Any?) -> Int? { (a as? NSNumber)?.intValue ?? (a as? Int) }
    private func dblOf(_ a: Any?) -> Double? { (a as? NSNumber)?.doubleValue ?? (a as? Double) }
    private func strOf(_ a: Any?) -> String? { a as? String }
    private func strArr(_ a: Any?) -> [String] { (a as? [String]) ?? [] }

    private func macroSum(_ kp: (DetectedItem) -> Double?) -> Double? {
        let v = entry.items.compactMap(kp); return v.isEmpty ? nil : v.reduce(0, +)
    }

    private var kcalLow: Int? { intOf(mealTotals?["estimated_calories_low"]) }
    private var kcalHigh: Int? { intOf(mealTotals?["estimated_calories_high"]) }
    private var protein: Double? { dblOf(mealTotals?["protein_g_estimate"]) ?? macroSum { $0.proteinG } }
    private var carbs: Double? { dblOf(mealTotals?["carbs_g_estimate"]) ?? macroSum { $0.carbsG } }
    private var fat: Double? { dblOf(mealTotals?["fat_g_estimate"]) ?? macroSum { $0.fatG } }
    private var fiber: Double? { dblOf(mealTotals?["fiber_g_estimate"]) ?? macroSum { $0.fiberG } }
    private var brainScore: Int? {
        // Defensive clamp 0-10 — Gemini occasionally returns an unclamped total (e.g. 56).
        guard let s = entry.mindScore ?? intOf(brain?["total"]) else { return nil }
        return min(10, max(0, s))
    }
    private var confidence: String {
        let c = entry.confidence ?? strOf(mealTotals?["confidence_level"]) ?? "—"
        switch c {
        case "rough_text", "estimate": return "rough estimate"
        case "barcode": return "label data"
        case "quick_log", "quick_tag": return "quick log"
        default: return c
        }
    }

    /// Log-quality 1-10 — stored on the row; computed on the fly for older rows.
    private var logQuality: Int {
        entry.logQuality ?? FoodEntry.computeLogQuality(source: entry.source, confidence: entry.confidence, items: entry.items)
    }
    private var logQualityColor: Color {
        switch logQuality {
        case 8...10: return DS.Colors.success
        case 5...7:  return DS.Colors.amber
        default:     return DS.Colors.danger
        }
    }

    private var sourceLabel: String {
        switch entry.source {
        case "photo": return "Photo + AI"
        case "text": return "Described · AI"
        case "manual": return "Typed · AI"
        case "barcode": return "Barcode · label data"
        case "quick_tag", "quick_log": return "Quick log"
        default: return entry.source
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.lg) {
                    Color.clear.frame(height: 2)
                    headerCard
                    kcalCard
                    if protein != nil || carbs != nil || fat != nil { macroCard }
                    scoreCard
                    hrCard
                    itemsSection
                    methodNote
                    editButton
                    Color.clear.frame(height: DS.Spacing.lg)
                }
                .padding(.horizontal, DS.Spacing.md)
            }
            .background(MeshGradientBackground().ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    TwoToneHeadline(primary: "Meal", secondary: " · detail", font: .system(size: 17, weight: .heavy, design: .rounded))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(DS.Colors.textSecondary)
                }
            }
        }
        .task {
            guard let id = entry.id?.uuidString else { hrLoading = false; return }
            hr = await SupabaseClient.shared.fetchMealHrResponse(mealId: id)
            hrLoading = false
        }
        .sheet(isPresented: $showEdit) {
            EditFoodEntrySheet(entry: entry, onSaved: { updated in
                entry = updated; onChanged(updated); showEdit = false
            }, onCancel: { showEdit = false })
            .presentationDetents([.large])
        }
    }

    // MARK: cards

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.caption ?? entry.items.map(\.name).joined(separator: ", "))
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(DS.Colors.textPrimary)
            HStack(spacing: DS.Spacing.sm) {
                Text(entry.capturedAt.formatted(.dateTime.weekday().hour().minute()))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(DS.Colors.textFaint)
                StatusChip(text: sourceLabel, style: .violet)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.md)
        .glassDefault()
    }

    private var kcalCard: some View {
        VStack(spacing: 4) {
            Text("\(entry.totalKcal ?? entry.items.reduce(0) { $0 + $1.kcal })")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(DS.Colors.amber)
                .monospacedDigit()
            Text("kcal").font(.system(size: 12, weight: .semibold)).foregroundStyle(DS.Colors.textMuted)
            if let lo = kcalLow, let hi = kcalHigh, hi > lo {
                Text("likely \(lo)–\(hi) kcal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.Colors.textFaint)
                    .padding(.top, 2)
            }
            Text("confidence: \(confidence)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.Colors.textFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(DS.Spacing.lg)
        .glassDefault()
    }

    private var macroCard: some View {
        HStack(spacing: DS.Spacing.sm) {
            macroTile("Protein", protein, "g", DS.Colors.teal)
            macroTile("Carbs", carbs, "g", DS.Colors.amber)
            macroTile("Fat", fat, "g", DS.Colors.pink)
            macroTile("Fiber", fiber, "g", DS.Colors.violet)
        }
    }

    private func macroTile(_ label: String, _ v: Double?, _ unit: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(v != nil ? String(format: "%.0f", v!) : "—")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color).monospacedDigit()
            Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(DS.Colors.textFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.md)
        .glassDefault()
    }

    private var scoreCard: some View {
        HStack(spacing: DS.Spacing.md) {
            VStack(spacing: 2) {
                Text(brainScore.map { "\($0)" } ?? "—")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(DS.Colors.mindColor(Double(brainScore ?? 0)))
                    .monospacedDigit()
                Text("BRAIN").font(.system(size: 9, weight: .bold)).foregroundStyle(DS.Colors.textFaint).tracking(0.8)
            }
            .frame(maxWidth: .infinity)
            Divider().frame(height: 30)
            VStack(spacing: 2) {
                Text(entry.novaAvg.map { String(format: "%.1f", $0) } ?? "—")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(DS.Colors.novaColor(entry.novaAvg ?? 1))
                    .monospacedDigit()
                Text("NOVA Ø").font(.system(size: 9, weight: .bold)).foregroundStyle(DS.Colors.textFaint).tracking(0.8)
            }
            .frame(maxWidth: .infinity)
            Divider().frame(height: 30)
            VStack(spacing: 2) {
                Text("\(logQuality)")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(logQualityColor)
                    .monospacedDigit()
                Text("LOG Q").font(.system(size: 9, weight: .bold)).foregroundStyle(DS.Colors.textFaint).tracking(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(DS.Spacing.md)
        .glassDefault()
    }

    @ViewBuilder
    private var hrCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            SectionHeader(icon: "heart.fill", title: "YOUR BODY'S RESPONSE", iconColor: DS.Colors.pink)
            if hrLoading {
                HStack(spacing: 8) { ProgressView().tint(DS.Colors.pink); Text("Reading your heart-rate response…").font(.system(size: 12)).foregroundStyle(DS.Colors.textMuted) }
            } else if let hr, let note = strOf(hr["note"]) {
                Text(note).font(.system(size: 13, weight: .medium)).foregroundStyle(DS.Colors.textPrimary).fixedSize(horizontal: false, vertical: true)
                if let bump = dblOf(hr["adj_bump_bpm"]) {
                    HStack(spacing: DS.Spacing.sm) {
                        StatusChip(text: String(format: "%+.1f bpm", bump), style: bump >= 8 ? .amber : .teal)
                        if let v = strOf(hr["verdict"]) {
                            StatusChip(text: v == "clean" ? "clean read" : v.replacingOccurrences(of: "_", with: " "), style: v == "clean" ? .teal : .violet)
                        }
                    }
                }
            } else {
                Text("Not enough heart-rate data around this meal yet. Wear the strap while resting after eating and this fills in — it shows how much this meal moved your HR (a rough glucose-response stand-in).")
                    .font(.system(size: 12)).foregroundStyle(DS.Colors.textMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.md)
        .glassDefault()
    }

    @ViewBuilder
    private var itemsSection: some View {
        if !entry.items.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                SectionHeader(icon: "list.bullet", title: "ITEMS", iconColor: DS.Colors.teal)
                ForEach(entry.items) { item in itemRow(item) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func itemRow(_ item: DetectedItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.name).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(DS.Colors.textPrimary)
                Spacer()
                if item.grams > 0 {
                    Text("\(item.grams) g").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(DS.Colors.textFaint)
                }
                Text("\(item.kcal) kcal").font(.system(size: 11, weight: .semibold)).foregroundStyle(DS.Colors.amber)
            }
            HStack(spacing: DS.Spacing.sm) {
                StatusChip(text: "NOVA \(item.novaClass)", style: item.novaClass >= 4 ? .danger : (item.novaClass >= 3 ? .amber : .teal))
                if let q = item.quantityDescription, !q.isEmpty {
                    Text(q).font(.system(size: 10)).foregroundStyle(DS.Colors.textMuted).lineLimit(1)
                }
                Spacer()
                if let qc = item.quantityConfidence { Text(qc).font(.system(size: 9, weight: .semibold)).foregroundStyle(DS.Colors.textFaint) }
            }
            if let nr = item.novaReasoning, !nr.isEmpty {
                Text(nr).font(.system(size: 10)).foregroundStyle(DS.Colors.textFaint).fixedSize(horizontal: false, vertical: true)
            }
            if !item.mindTags.isEmpty {
                Text(item.mindTags.joined(separator: " · ")).font(.system(size: 10, weight: .medium)).foregroundStyle(DS.Colors.teal)
            }
        }
        .padding(DS.Spacing.md)
        .glassDefault()
    }

    private var methodNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("HOW THIS WAS ESTIMATED").font(.system(size: 9, weight: .bold)).foregroundStyle(DS.Colors.textFaint).tracking(0.8)
            Text(methodText).font(.system(size: 11)).foregroundStyle(DS.Colors.textMuted).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.md)
        .glassDefault()
    }

    private var methodText: String {
        let qualityLine = " · Log quality \(logQuality)/10 reflects how this was captured."
        switch entry.source {
        case "barcode": return "Read straight off the product label (Open Food Facts) — the most accurate source. Calories scale to the portion you logged." + qualityLine
        case "combined": return "Built from multiple sources (barcode + photo + description). Barcoded items are label-exact; the rest are AI estimates." + qualityLine
        case "photo": return "AI identified the foods from your photo and estimated portions using your body profile. Photo is great for what's on the plate; portion is the rough part — tap Edit to correct grams." + qualityLine
        case "text", "manual":
            if (entry.confidence ?? "") == "rough_text" || (entry.confidence ?? "") == "estimate" {
                return "Estimated by a quick keyword match (AI was unavailable). Numbers are rough — re-open and tap Deep analysis for an accurate read." + qualityLine
            }
            return "AI estimated this from your description + your body profile. Food identity is solid; portion is the main uncertainty — add grams in the description for a tighter number." + qualityLine
        default: return "Quick-logged with a default estimate. Tap Edit to refine kcal or items." + qualityLine
        }
    }

    private var editButton: some View {
        Button { showEdit = true } label: {
            Label("Edit this meal", systemImage: "square.and.pencil")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.violet)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.md)
                .background(Capsule().fill(DS.Colors.violet.opacity(0.12)).overlay(Capsule().stroke(DS.Colors.violet.opacity(0.3), lineWidth: 0.5)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Meal Builder (combine barcode + described + photo into one entry)

private struct MealBuilderSheet: View {
    let onSaved: (FoodEntry) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var caption = ""
    @State private var eatenAt = Date()
    @State private var items: [DetectedItem] = []
    @State private var describeText = ""
    @State private var isAnalyzing = false
    @State private var analyzingLabel = ""
    @State private var showBarcode = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isSaving = false
    @State private var error: String?

    private var totalKcal: Int { items.reduce(0) { $0 + $1.kcal } }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.lg) {
                    Color.clear.frame(height: 2)
                    nameCard
                    addRow
                    describeCard
                    if isAnalyzing { analyzingBanner }
                    if !items.isEmpty { draftCard; timeCard }
                    if let error {
                        AlertBanner(icon: "exclamationmark.triangle", message: error, color: DS.Colors.pink)
                    }
                    saveButton
                    Color.clear.frame(height: DS.Spacing.lg)
                }
                .padding(.horizontal, DS.Spacing.md)
            }
            .background(MeshGradientBackground().ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    TwoToneHeadline(primary: "Build", secondary: " · meal", font: .system(size: 17, weight: .heavy, design: .rounded))
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(DS.Colors.textSecondary)
                }
            }
        }
        .fullScreenCover(isPresented: $showBarcode) {
            BarcodeItemScannerSheet { item in items.append(item) }
        }
        .onChange(of: photoItem) { _, newVal in
            guard let newVal else { return }
            Task { await analyzePhoto(newVal) }
        }
    }

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            SectionHeader(icon: "text.cursor", title: "MEAL NAME", iconColor: DS.Colors.violet)
            TextField("e.g. Toast with cheddar + ham", text: $caption)
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(DS.Colors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .foregroundStyle(DS.Colors.textPrimary)
        }
        .padding(DS.Spacing.md).glassDefault()
    }

    private var addRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                addButton(icon: "camera.fill", label: "Photo", color: DS.Colors.violet)
            }
            Button { showBarcode = true } label: {
                addButton(icon: "barcode.viewfinder", label: "Barcode", color: DS.Colors.teal)
            }
            .buttonStyle(.plain)
        }
    }

    private func addButton(icon: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(color)
            Text(label).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(DS.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, DS.Spacing.md).glassDefault()
    }

    private var describeCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            SectionHeader(icon: "text.bubble", title: "DESCRIBE & ADD", iconColor: DS.Colors.amber)
            HStack(spacing: DS.Spacing.sm) {
                TextField("e.g. 2 slices toast, baked", text: $describeText, axis: .vertical)
                    .font(.system(size: 14)).lineLimit(1...3)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(DS.Colors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                    .foregroundStyle(DS.Colors.textPrimary)
                Button { Task { await analyzeText() } } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 30))
                        .foregroundStyle(describeText.isEmpty ? DS.Colors.textMuted : DS.Colors.amber)
                }
                .buttonStyle(.plain).disabled(describeText.trimmingCharacters(in: .whitespaces).isEmpty || isAnalyzing)
            }
        }
        .padding(DS.Spacing.md).glassDefault()
    }

    private var analyzingBanner: some View {
        HStack(spacing: 8) {
            ProgressView().tint(DS.Colors.violet)
            Text(analyzingLabel.isEmpty ? "Analyzing…" : analyzingLabel)
                .font(.system(size: 12)).foregroundStyle(DS.Colors.textMuted)
        }
        .frame(maxWidth: .infinity).padding(DS.Spacing.md).glassDefault()
    }

    private var draftCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                SectionHeader(icon: "list.bullet", title: "THIS MEAL", iconColor: DS.Colors.teal)
                Spacer()
                Text("\(totalKcal) kcal").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(DS.Colors.amber)
            }
            ForEach(items) { item in
                HStack(spacing: DS.Spacing.sm) {
                    Text(item.name).font(.system(size: 13, weight: .medium)).foregroundStyle(DS.Colors.textPrimary).lineLimit(1)
                    Spacer()
                    if item.grams > 0 { Text("\(item.grams)g").font(.system(size: 10, design: .monospaced)).foregroundStyle(DS.Colors.textFaint) }
                    Text("\(item.kcal)").font(.system(size: 11, weight: .semibold)).foregroundStyle(DS.Colors.amber)
                    Button { items.removeAll { $0.id == item.id } } label: {
                        Image(systemName: "minus.circle.fill").font(.system(size: 16)).foregroundStyle(DS.Colors.danger.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous).fill(DS.Colors.surface))
            }
        }
        .padding(DS.Spacing.md).glassDefault()
    }

    private var timeCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            SectionHeader(icon: "clock", title: "WHEN DID YOU EAT IT?", iconColor: DS.Colors.violet)
            DatePicker("", selection: $eatenAt, in: ...Date(),
                       displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(DS.Colors.violet)
            HStack(spacing: DS.Spacing.xs) {
                builderTimeChip("Now") { eatenAt = Date() }
                builderTimeChip("1h ago") { eatenAt = Date().addingTimeInterval(-3600) }
                builderTimeChip("2h ago") { eatenAt = Date().addingTimeInterval(-7200) }
            }
        }
        .padding(DS.Spacing.md).glassDefault()
    }

    private func builderTimeChip(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: { DS.Haptic.tap(); action() }) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.violet)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(DS.Colors.violet.opacity(0.12))
                    .overlay(Capsule().stroke(DS.Colors.violet.opacity(0.25), lineWidth: 0.5)))
        }
        .buttonStyle(.plain)
    }

    private var saveButton: some View {
        Button { Task { await save() } } label: {
            HStack {
                if isSaving { ProgressView().tint(.white) }
                else {
                    Image(systemName: "checkmark")
                    Text(items.isEmpty ? "Add something first" : "Save meal · \(items.count) item\(items.count == 1 ? "" : "s")")
                }
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, DS.Spacing.md)
            .background(Capsule().fill(items.isEmpty ? DS.Colors.textMuted : DS.Colors.violet))
        }
        .buttonStyle(.plain).disabled(items.isEmpty || isSaving)
    }

    // MARK: actions

    private func analyzeText() async {
        let t = describeText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        isAnalyzing = true; analyzingLabel = "Reading “\(t.prefix(24))”…"; error = nil
        if let r = try? await GeminiClient.shared.analyzeFood(description: t) {
            items.append(contentsOf: r.items)
            describeText = ""
        } else {
            error = "Couldn't analyze that — try simpler wording."
            SupabaseClient.shared.logClientError(area: "builder.analyze_text_failed",
                                                 message: "Gemini text analysis returned nil in meal builder",
                                                 context: String(t.prefix(200)))
        }
        isAnalyzing = false; analyzingLabel = ""
    }

    private func analyzePhoto(_ pick: PhotosPickerItem) async {
        isAnalyzing = true; analyzingLabel = "Analyzing photo…"; error = nil
        if let data = try? await pick.loadTransferable(type: Data.self), let img = UIImage(data: data) {
            if let r = try? await GeminiClient.shared.analyzeFood(image: img, caption: caption.isEmpty ? nil : caption) {
                items.append(contentsOf: r.items)
            } else {
                error = "Photo analysis failed — add it another way."
                SupabaseClient.shared.logClientError(area: "builder.analyze_photo_failed",
                                                     message: "Gemini photo analysis returned nil in meal builder",
                                                     context: caption.isEmpty ? nil : String(caption.prefix(200)))
            }
        } else {
            error = "Couldn't read that photo — try another."
            SupabaseClient.shared.logClientError(area: "builder.photo_load_failed",
                                                 message: "PhotosPicker loadTransferable failed or UIImage init failed",
                                                 context: nil)
        }
        photoItem = nil
        isAnalyzing = false; analyzingLabel = ""
    }

    private func save() async {
        guard !items.isEmpty else { return }
        isSaving = true; error = nil
        do {
            let saved = try await SupabaseClient.shared.saveCombinedMeal(items: items, caption: caption, capturedAt: eatenAt)
            onSaved(saved)
            dismiss()
        } catch {
            self.error = "Save failed — check connection."
            SupabaseClient.shared.logClientError(area: "builder.save_failed",
                                                 message: error.localizedDescription,
                                                 context: caption.isEmpty ? nil : String(caption.prefix(200)))
            isSaving = false
        }
    }
}

// MARK: - Barcode scanner in item-return mode (for the meal builder)

private struct BarcodeItemScannerSheet: View {
    let onItem: (DetectedItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            BarcodeScannerView(onItem: { item in onItem(item) }, onEntry: { _ in })
                .ignoresSafeArea()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding()
            }
            .buttonStyle(.plain)
            VStack {
                Spacer()
                Text("Scan a barcode to add it to the meal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(8).background(.black.opacity(0.4)).clipShape(Capsule())
                    .padding(.bottom, DS.Spacing.xl)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
