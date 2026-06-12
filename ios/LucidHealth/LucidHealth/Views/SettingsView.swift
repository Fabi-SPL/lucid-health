import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    @EnvironmentObject private var bleManager: BLEManager
    @State private var appeared = false
    @State private var showCredentialOverride = false
    @State private var overrideEmail = ""
    @State private var overridePassword = ""
    @State private var isSavingCredentials = false
    @State private var credentialSaved = false
    @State private var showLogs = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: DS.Spacing.md) {
                headerSpacer

                // ── CORE ─────────────────────────────────────────────
                groupHeader("ACCOUNT & DEVICE", icon: "person.crop.circle", index: 0)

                staggered(1) { AuthStatusCard() }
                staggered(2) { PersonalizationCard() }
                staggered(3) { BLEControlCard(bleManager: bleManager) }
                staggered(4) { AppInfoCard() }
                staggered(5) { DisplayCard() }

                // ── EXPERIMENTAL ─────────────────────────────────────
                // Whoop-pattern experiments — opt-in, may break, that's the point.
                groupHeader("EXPERIMENTAL · LABS", icon: "flask.fill", index: 6, tint: DS.Colors.violet)

                staggered(7) { DiscordBroadcastCard() }
                staggered(8) { HighFrequencyBroadcastCard() }
                staggered(9) { SpiralAlertsLogCard() }
                staggered(10) { HueMirrorCard() }

                // ── DIAGNOSTICS ──────────────────────────────────────
                // Strap/data plumbing + dev tools. NOT experimental features —
                // these are the "is the hardware working" instruments.
                groupHeader("DIAGNOSTICS", icon: "stethoscope", index: 11, tint: DS.Colors.teal)

                staggered(12) {
                    CredentialOverrideCard(
                        isExpanded: $showCredentialOverride,
                        email: $overrideEmail,
                        password: $overridePassword,
                        isSaving: isSavingCredentials,
                        saved: credentialSaved
                    ) { await saveCredentials() }
                }
                staggered(13) { BLEDiagnosticsCard(bleManager: bleManager) }
                staggered(14) { DataSyncCard(bleManager: bleManager) }
                staggered(15) { ManualBackfillCard(bleManager: bleManager) }
                staggered(16) { DevCard() }
                staggered(17) { SkinTempDiagnosticsCard(bleManager: bleManager) }
                staggered(18) { AllStreamsDiagnosticsCard(bleManager: bleManager) }
                staggered(19) { BatteryDiagnosticsCard(bleManager: bleManager) }
                staggered(20) { LogViewerCard { showLogs = true } }

                bottomSpacer
            }
            .padding(.horizontal, DS.Spacing.md)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLogs) {
            LogViewerView()
                .presentationDetents([.large])
        }
        .onAppear { withAnimation { appeared = true } }
    }

    private var headerSpacer: some View { Color.clear.frame(height: DS.Spacing.sm) }
    private var bottomSpacer: some View { Color.clear.frame(height: 100) }

    /// One entrance choreography for every Settings card — sequential index,
    /// no more hand-numbered duplicates. (DS.Anim.stagger caps at 8 so the long
    /// diagnostics tail settles together instead of dragging in late.)
    @ViewBuilder
    private func staggered<Content: View>(_ index: Int, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .offset(y: appeared ? 0 : 20)
            .opacity(appeared ? 1 : 0)
            .animation(DS.Anim.stagger(index: index), value: appeared)
    }

    /// Consistent group divider label so Settings reads as CORE / LABS /
    /// DIAGNOSTICS sections instead of one undifferentiated dump.
    private func groupHeader(_ title: String, icon: String, index: Int, tint: Color = DS.Colors.textMuted) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .tracking(1.2)
            Spacer()
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.top, DS.Spacing.lg)
        .padding(.bottom, 2)
        .offset(y: appeared ? 0 : 20)
        .opacity(appeared ? 1 : 0)
        .animation(DS.Anim.stagger(index: index), value: appeared)
    }

    private func saveCredentials() async {
        guard !overrideEmail.isEmpty, !overridePassword.isEmpty else { return }
        isSavingCredentials = true
        SupabaseClient.saveCredentials(email: overrideEmail, password: overridePassword)
        await SupabaseClient.shared.signInIfNeeded()
        credentialSaved = true
        isSavingCredentials = false
    }
}

// MARK: - Skin Temp Diagnostics

/// Surfaces the BLE skin-temp pipeline state on-phone (no Mac required).
/// Three possible states:
///   • Never received any TEMP packets → strap firmware doesn't send them
///     on this version, OR notify subscription missing → log + add fallback.
///   • Received but skinTemperature == 0 → decoder couldn't parse the bytes.
///     Raw hex is shown so we can trace the format.
///   • Received and parsed → great, just slow update cadence (Whoop pushes
///     skin temp every few minutes, not continuously).
private struct SkinTempDiagnosticsCard: View {
    @ObservedObject var bleManager: BLEManager

    private var statusLine: String {
        if let _ = bleManager.lastTempEventAt {
            if bleManager.skinTemperature > 0 {
                return "Receiving + parsing OK"
            } else {
                return "Receiving but decode failed — raw hex below"
            }
        }
        return "No temperature events received yet"
    }

    private var statusColor: Color {
        if bleManager.skinTemperature > 0 { return DS.Colors.success }
        if bleManager.lastTempEventAt != nil { return DS.Colors.warning }
        return DS.Colors.textMuted
    }

    private func timeAgo(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "\(s)s ago" }
        if s < 3600 { return "\(s / 60)m ago" }
        return "\(s / 3600)h \((s % 3600) / 60)m ago"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            SectionHeader(icon: "thermometer.medium", title: "SKIN TEMP", iconColor: DS.Colors.amber)

            HStack(spacing: DS.Spacing.md) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(statusLine)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.Colors.textPrimary)
                Spacer()
                if bleManager.skinTemperature > 0 {
                    Text("\(String(format: "%.1f", bleManager.skinTemperature))°C")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Colors.amber)
                        .monospacedDigit()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                diagnosticRow(label: "Events received", value: "\(bleManager.totalTempEventsReceived)")
                diagnosticRow(
                    label: "Type-49 packets seen",
                    value: "\(bleManager.totalType49PacketsSeen)"
                )
                diagnosticRow(
                    label: "History sync flag",
                    value: bleManager.isHistorySyncing ? "🔄 SYNCING (gates temp)" : "✅ idle"
                )
                diagnosticRow(
                    label: "Last event",
                    value: bleManager.lastTempEventAt.map { timeAgo($0) } ?? "never"
                )
                diagnosticRow(
                    label: "Source",
                    value: bleManager.lastTempEventSource ?? "—"
                )
                if let raw = bleManager.lastTempRawHex {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("LAST RAW BYTES")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(DS.Colors.textFaint)
                            .tracking(0.8)
                        Text(raw)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(DS.Colors.textSecondary)
                            .lineLimit(3)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(DS.Spacing.md)
        .glassDefault()
    }

    @ViewBuilder
    private func diagnosticRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(DS.Colors.textMuted)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(DS.Colors.textPrimary)
        }
    }
}

// MARK: - All-Streams Diagnostics

/// Surfaces every BLE packet type the strap is currently emitting, so we can
/// verify whether power-user mode (cmd 106 IMU, 107/81 raw PPG) actually
/// unlocked new streams or got silently rejected by firmware.
///
/// Known packet types per WhoopProtocol enum + community RE work:
///   • 2  = REALTIME_DATA (HR + RR)
///   • 27 = HISTORICAL_DATA (sync)
///   • 32 = COMMAND_RESPONSE
///   • 33 = EVENT (battery, charging, double-tap, TEMPERATURE event 17)
///   • 43 = REALTIME_RAW_DATA (raw PPG channels)
///   • 47 = HISTORICAL sensor / decode_5c
///   • 49 = METADATA (skin temp 0x31 OR history start/end)
///   • 51 = REALTIME_IMU_DATA (accel + gyro @ 52Hz)
///   • 52 = HISTORICAL_IMU_DATA
private struct AllStreamsDiagnosticsCard: View {
    @ObservedObject var bleManager: BLEManager
    @State private var refreshTick = Date()

    private let typeLabels: [Int: String] = [
        2: "HR + RR",
        27: "History sync",
        32: "Cmd response",
        33: "Event",
        43: "Raw PPG",
        47: "Sensor v70",
        49: "Metadata / temp",
        51: "IMU 52Hz",
        52: "IMU history"
    ]

    private let priorityHighlights: [Int] = [2, 51, 43, 49]

    private var sessionMinutes: Double {
        let s = Date().timeIntervalSince(bleManager.sessionStartedAt) / 60
        return max(s, 0.01)
    }

    private func rate(for type: Int) -> String {
        let count = bleManager.packetTypeCounts[type] ?? 0
        let perMin = Double(count) / sessionMinutes
        if perMin >= 60 { return String(format: "%.0f/s", perMin / 60) }
        if perMin >= 1 { return String(format: "%.1f/min", perMin) }
        if count == 0 { return "—" }
        return "\(count) total"
    }

    private func ageText(_ d: Date?) -> String {
        guard let d else { return "—" }
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "\(s)s ago" }
        if s < 3600 { return "\(s/60)m ago" }
        return "\(s/3600)h ago"
    }

    private func statusColor(_ count: Int, isPriority: Bool) -> Color {
        if count == 0 { return isPriority ? DS.Colors.danger : DS.Colors.textFaint }
        if count < 5 { return DS.Colors.warning }
        return DS.Colors.success
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            SectionHeader(icon: "waveform.path.ecg", title: "ALL STREAMS", iconColor: DS.Colors.violet)

            VStack(alignment: .leading, spacing: 6) {
                streamRow(type: 2,  label: "HR + RR")
                streamRow(type: 51, label: "IMU 52Hz")
                streamRow(type: 43, label: "Raw PPG")
                streamRow(type: 49, label: "Metadata / temp")
                streamRow(type: 33, label: "Event")
                streamRow(type: 47, label: "Sensor v70")

                // Show any UNKNOWN packet types observed (potential new capabilities)
                let known = Set([2, 27, 32, 33, 43, 47, 49, 51, 52])
                let unknown = bleManager.packetTypeCounts.keys.filter { !known.contains($0) }.sorted()
                if !unknown.isEmpty {
                    Divider().padding(.vertical, 2)
                    Text("UNKNOWN TYPES (potential new signals)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(DS.Colors.textFaint)
                        .tracking(0.8)
                    ForEach(unknown, id: \.self) { t in
                        streamRow(type: t, label: "Unknown type-\(t)")
                    }
                }
            }
            .id(refreshTick)

            Text("Session: \(Int(sessionMinutes))m elapsed")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DS.Colors.textFaint)
        }
        .padding(DS.Spacing.md)
        .glassDefault()
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            refreshTick = Date()
        }
    }

    @ViewBuilder
    private func streamRow(type: Int, label: String) -> some View {
        let count = bleManager.packetTypeCounts[type] ?? 0
        let isPriority = priorityHighlights.contains(type)
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor(count, isPriority: isPriority))
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11, weight: isPriority ? .semibold : .regular))
                .foregroundStyle(DS.Colors.textPrimary)
            Spacer()
            Text(rate(for: type))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(count > 0 ? DS.Colors.textPrimary : DS.Colors.textFaint)
            Text(ageText(bleManager.packetTypeLastSeen[type]))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(DS.Colors.textMuted)
                .frame(width: 56, alignment: .trailing)
        }
    }
}

// MARK: - Battery Diagnostics

/// Surfaces strap battery level + drain rate. Power-user mode (continuous
/// IMU + raw PPG) costs battery — Fabi wants visibility on how much.
private struct BatteryDiagnosticsCard: View {
    @ObservedObject var bleManager: BLEManager

    private var drainText: String {
        guard let r = bleManager.batteryDrainPerHour else { return "Need 30+ min of data" }
        if r < 0 {
            let perHour = abs(r)
            let hoursLeft = bleManager.battery / perHour
            return String(format: "%.1f%%/hr · ~%.1fh left", perHour, hoursLeft)
        }
        return String(format: "+%.1f%%/hr (charging)", r)
    }

    private var drainColor: Color {
        guard let r = bleManager.batteryDrainPerHour else { return DS.Colors.textFaint }
        if r >= 0 { return DS.Colors.success }
        if abs(r) > 5 { return DS.Colors.danger }   // draining > 5%/hr = ~20h life
        if abs(r) > 2 { return DS.Colors.warning }  // 2-5%/hr = ~50h life (~2 days)
        return DS.Colors.success                    // <2%/hr = 50h+ (normal-ish)
    }

    private var statusEmoji: String {
        if bleManager.battery > 50 { return "🔋" }
        if bleManager.battery > 20 { return "🪫" }
        return "🚨"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            SectionHeader(icon: "bolt.fill", title: "STRAP BATTERY", iconColor: DS.Colors.amber)

            HStack(alignment: .center, spacing: DS.Spacing.md) {
                Text(statusEmoji)
                    .font(.system(size: 28))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(bleManager.battery))%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Colors.textPrimary)
                        .monospacedDigit()
                    Text(drainText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(drainColor)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                let history = bleManager.batteryHistorySnapshot
                miniRow(label: "Samples logged", value: "\(history.count)")
                if let oldest = history.first {
                    let h = Int(Date().timeIntervalSince(oldest.date) / 3600)
                    miniRow(label: "Oldest sample", value: "\(h)h ago @ \(Int(oldest.level))%")
                }
                if !bleManager.batteryPrediction.isEmpty {
                    miniRow(label: "Estimate", value: bleManager.batteryPrediction)
                }
            }

            Text("Power-user mode (continuous IMU + raw PPG) drains faster than stock Whoop. ~5%/hr is normal here.")
                .font(.system(size: 9))
                .foregroundStyle(DS.Colors.textFaint)
                .padding(.top, 4)
        }
        .padding(DS.Spacing.md)
        .glassDefault()
    }

    @ViewBuilder
    private func miniRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(DS.Colors.textMuted)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(DS.Colors.textPrimary)
        }
    }
}

// MARK: - Log Viewer Card

private struct LogViewerCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(DS.Colors.teal.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.Colors.teal)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Logs")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.textPrimary)
                    Text("On-phone debug log — widget reads, BLE state, errors")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Colors.textMuted)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Colors.textFaint)
            }
            .padding(DS.Spacing.md)
            .glassDefault()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Auth Status Card

private struct AuthStatusCard: View {
    // SupabaseClient isn't ObservableObject (would need a deep refactor),
    // so we use a local @State that mirrors auth state and refreshes on:
    //   • View appear (initial render)
    //   • lucidAuthChanged notification (App posts this after every refresh)
    //   • A 5s timer (catches edge cases like network blips)
    @State private var authed: Bool = SupabaseClient.shared.isAuthenticated

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            SectionHeader(icon: "person.circle.fill", title: "Account", iconColor: DS.Colors.violet)

            HStack(spacing: DS.Spacing.md) {
                AmbientLiveDot(state: authed ? .connected : .disconnected, size: 10)

                VStack(alignment: .leading, spacing: 3) {
                    Text(authed ? "Signed in" : "Signed out")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(authed ? DS.Colors.teal : DS.Colors.pink)

                    if SupabaseClient.hasCredentials {
                        let email = UserDefaults.standard.string(forKey: "lucidhealth_email") ?? ""
                        Text(email)
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(DS.Colors.textFaint)
                            .lineLimit(1)
                    }
                }

                Spacer()

                StatusChip(
                    text: authed ? "Active" : "Offline",
                    style: authed ? .teal : .violet
                )
            }
        }
        .padding(DS.Spacing.lg)
        .glassDefault()
        .onAppear { refreshAuthed() }
        .onReceive(NotificationCenter.default.publisher(for: .lucidAuthChanged)) { _ in
            refreshAuthed()
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            refreshAuthed()
        }
    }

    private func refreshAuthed() {
        authed = SupabaseClient.shared.isAuthenticated
    }
}

// MARK: - BLE Control Card

private struct BLEControlCard: View {
    @ObservedObject var bleManager: BLEManager

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            SectionHeader(icon: "antenna.radiowaves.left.and.right", title: "Bluetooth Device", iconColor: DS.Colors.teal)

            HStack {
                BLEStatusDot()
                    .environmentObject(bleManager)
                Spacer()
                if bleManager.isWorn {
                    StatusChip(text: "Worn", style: .teal, icon: "checkmark.circle.fill")
                }
            }

            if bleManager.connectionState == .disconnected {
                // Full-width pill button — Principle #4
                Button {
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                    NotificationCenter.default.post(name: .lucidReconnectBLE, object: nil)
                } label: {
                    Label("Reconnect", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.violet)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.md)
                        .background(
                            Capsule()
                                .fill(DS.Colors.violet.opacity(0.12))
                                .overlay(Capsule().stroke(DS.Colors.violet.opacity(0.3), lineWidth: 0.5))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DS.Spacing.lg)
        .glassDefault()
    }
}

// MARK: - App Info Card

// MARK: - Display Settings (v103 — recovery ring style picker)
//
// Live preview of the chosen ring rendering above the picker so Fabi can
// see-and-pick. Saves to UserDefaults via @AppStorage("recoveryRingStyle"),
// TodayView reads the same key and switches between HeroRecoveryRing and
// SmokeRecoveryRing on the Today screen.

private struct DisplayCard: View {
    @AppStorage("recoveryRingStyle") private var ringStyleRaw: String = RecoveryRingStyle.classic.rawValue
    private var ringStyle: RecoveryRingStyle {
        get { RecoveryRingStyle(rawValue: ringStyleRaw) ?? .classic }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            SectionHeader(icon: "circle.dotted", title: "Recovery Ring", iconColor: DS.Colors.violet)

            // Live preview at score 60 — the sweet-spot value Fabi tuned the
            // gradient around. Both renderers update reactively when picker
            // changes via @AppStorage observation.
            HStack(spacing: DS.Spacing.lg) {
                Spacer()
                Group {
                    switch ringStyle {
                    case .classic: HeroRecoveryRing(score: 60, size: 110, lineWidth: 12)
                    case .smoke:   SmokeRecoveryRing(score: 60, size: 110, lineWidth: 12)
                    }
                }
                Spacer()
            }
            .padding(.vertical, DS.Spacing.sm)

            Picker("Style", selection: $ringStyleRaw) {
                ForEach(RecoveryRingStyle.allCases) { style in
                    Text(style.label).tag(style.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Text(ringStyle.detail)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(DS.Colors.textFaint)
                .padding(.top, 2)
        }
        .padding(DS.Spacing.lg)
        .glassDefault()
    }
}

private struct AppInfoCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            SectionHeader(icon: "app.badge", title: "App", iconColor: DS.Colors.textFaint)

            InfoRow(icon: "number", label: "Version", value: BuildInfo.codeVersion)
            InfoRow(icon: "chevron.left.forwardslash.chevron.right", label: "Commit", value: BuildInfo.commitHash)
            InfoRow(icon: "globe", label: "Backend", value: "Supabase · \(URL(string: SupabaseClient.shared.baseURL)?.host ?? "—")")
        }
        .padding(DS.Spacing.lg)
        .glassDefault()
    }
}

// MARK: - Credential Override

private struct CredentialOverrideCard: View {
    @Binding var isExpanded: Bool
    @Binding var email: String
    @Binding var password: String
    let isSaving: Bool
    let saved: Bool
    let onSave: () async -> Void

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: DS.Spacing.md) {
                TextField("Email", text: $email)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(DS.Colors.textPrimary)
                    .padding(DS.Spacing.sm)
                    .background(DS.Colors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)

                SecureField("Password", text: $password)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(DS.Colors.textPrimary)
                    .padding(DS.Spacing.sm)
                    .background(DS.Colors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))

                Button {
                    Task { await onSave() }
                } label: {
                    HStack {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else if saved {
                            Image(systemName: "checkmark")
                        } else {
                            Text("Save")
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(saved ? DS.Colors.teal : DS.Colors.violet)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
            .padding(.top, DS.Spacing.sm)
        } label: {
            Label("Override credentials", systemImage: "key.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Colors.textSecondary)
        }
        .accentColor(DS.Colors.violet)
        .padding(DS.Spacing.lg)
        .glassDefault()
    }
}

// MARK: - BLE Diagnostics Card

private struct BLEDiagnosticsCard: View {
    @ObservedObject var bleManager: BLEManager

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            SectionHeader(icon: "waveform.path.ecg", title: "BLE Diagnostics", iconColor: DS.Colors.pink)

            let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: cols, spacing: DS.Spacing.sm) {
                diagCell(label: "HR", value: bleManager.heartRate > 0 ? "\(bleManager.heartRate)" : "—", unit: "bpm", color: DS.Colors.pink)
                diagCell(label: "Battery", value: bleManager.battery > 0 ? "\(Int(bleManager.battery))" : "—", unit: "%", color: DS.Colors.teal)
                diagCell(label: "Readings", value: "\(bleManager.readingsToday)", unit: "today", color: DS.Colors.violet)
            }

            if let fw = bleManager.deviceInfo["firmware"], !fw.isEmpty {
                InfoRow(icon: "cpu", label: "Firmware", value: fw, color: DS.Colors.textFaint)
            }
            if let hw = bleManager.deviceInfo["hardware"], !hw.isEmpty {
                InfoRow(icon: "memorychip", label: "Hardware", value: hw, color: DS.Colors.textFaint)
            }

            // Manual reconnect — full-width pill
            if bleManager.connectionState == .disconnected {
                Button {
                    let h = UIImpactFeedbackGenerator(style: .light)
                    h.impactOccurred()
                    NotificationCenter.default.post(name: .lucidReconnectBLE, object: nil)
                } label: {
                    Label("Reconnect", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.violet)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.md)
                        .background(
                            Capsule()
                                .fill(DS.Colors.violet.opacity(0.12))
                                .overlay(Capsule().stroke(DS.Colors.violet.opacity(0.3), lineWidth: 0.5))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DS.Spacing.lg)
        .glassDefault()
    }

    private func diagCell(label: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(unit)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(DS.Colors.textFaint)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(DS.Colors.textFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xs)
        .background(DS.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
    }
}

// MARK: - Data Sync Card

private struct DataSyncCard: View {
    @ObservedObject var bleManager: BLEManager

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            SectionHeader(icon: "icloud.and.arrow.up", title: "Data Sync", iconColor: DS.Colors.teal)

            HStack(spacing: DS.Spacing.md) {
                Image(systemName: bleManager.historySyncCount > 0 ? "checkmark.icloud.fill" : "icloud.slash")
                    .font(.system(size: 28))
                    .foregroundStyle(bleManager.historySyncCount > 0 ? DS.Colors.teal : DS.Colors.textFaint)

                VStack(alignment: .leading, spacing: 3) {
                    Text(bleManager.historySyncCount > 0 ? "Synced" : "No sync")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(bleManager.historySyncCount > 0 ? DS.Colors.teal : DS.Colors.textFaint)

                    if bleManager.historySyncCount > 0 {
                        Text("\(bleManager.historySyncCount) data points uploaded")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.Colors.textFaint)
                    }

                    if !bleManager.historySyncProgress.isEmpty {
                        Text(bleManager.historySyncProgress)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(DS.Colors.amber)
                    }
                }

                Spacer()
            }
        }
        .padding(DS.Spacing.lg)
        .glassDefault()
    }
}

// MARK: - Manual Backfill Card
//
// Lets the user trigger a 72h gap-fill from the strap's buffer when something
// like a phone-died-overnight scenario leaves holes in realtime_health.
// State machine driven by BLEManager.manualBackfillState:
//   idle → querying → requesting → parsing → uploading → done | failed
// Button stays disabled while a run is in flight. Result line stays visible
// after a run so the user can see what happened.

private struct ManualBackfillCard: View {
    @ObservedObject var bleManager: BLEManager

    private var isRunning: Bool {
        switch bleManager.manualBackfillState {
        case "querying", "requesting", "parsing", "uploading": return true
        default: return false
        }
    }

    private var stateColor: Color {
        switch bleManager.manualBackfillState {
        case "done":   return DS.Colors.success
        case "failed": return DS.Colors.danger
        default:       return DS.Colors.violet
        }
    }

    private var stateIcon: String {
        switch bleManager.manualBackfillState {
        case "done":       return "checkmark.circle.fill"
        case "failed":     return "exclamationmark.circle.fill"
        case "querying":   return "magnifyingglass"
        case "requesting": return "arrow.down.to.line"
        case "parsing":    return "list.bullet.rectangle"
        case "uploading":  return "arrow.up.to.line"
        default:           return "clock.arrow.circlepath"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: stateIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(stateColor)
                Text("MANUAL BACKFILL · 72H")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DS.Colors.textFaint)
                    .tracking(1.0)
                Spacer()
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .tint(DS.Colors.violet)
                }
            }

            Text("If your phone disconnected overnight and left a gap, this asks the strap to dump its buffer and fills any minutes that aren't already covered. Only writes new data — won't duplicate existing rows.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(DS.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            // Live progress / result line
            if !bleManager.manualBackfillProgress.isEmpty {
                Text(bleManager.manualBackfillProgress)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(DS.Colors.violet)
            }
            if !bleManager.manualBackfillResult.isEmpty {
                Text(bleManager.manualBackfillResult)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(stateColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                let h = UIImpactFeedbackGenerator(style: .medium)
                h.impactOccurred()
                bleManager.manualBackfill72h()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .bold))
                    Text(isRunning ? "Running…" : "Backfill last 72h")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(isRunning ? DS.Colors.surfaceElevated : DS.Colors.violet.opacity(0.18))
                        .overlay(Capsule().stroke(DS.Colors.violet.opacity(0.4), lineWidth: 0.5))
                )
                .foregroundStyle(isRunning ? DS.Colors.textFaint : DS.Colors.violet)
            }
            .buttonStyle(.plain)
            .disabled(isRunning || bleManager.connectionState != .streaming)

            if bleManager.connectionState != .streaming && !isRunning {
                Text("Connect the strap first to enable.")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(DS.Colors.textFaint)
            }
        }
        .padding(DS.Spacing.lg)
        .glassDefault()
    }
}

// MARK: - Dev Card

private struct DevCard: View {
    @State private var showDevInfo = false

    var body: some View {
        DisclosureGroup(isExpanded: $showDevInfo) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                InfoRow(icon: "server.rack", label: "Supabase URL", value: URL(string: SupabaseClient.shared.baseURL)?.host ?? "—")
                InfoRow(icon: "iphone", label: "iOS Version", value: UIDevice.current.systemVersion)
                InfoRow(icon: "cpu", label: "Model", value: UIDevice.current.model)
            }
            .padding(.top, DS.Spacing.sm)
        } label: {
            Label("Developer info", systemImage: "wrench.and.screwdriver")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Colors.textFaint)
        }
        .accentColor(DS.Colors.textFaint)
        .padding(DS.Spacing.lg)
        .glassDefault()
    }
}

// MARK: - Personalization Card

/// Weight + derived BMR/TDEE — feeds calorie targets, alcohol BAC calc,
/// and strain-per-kg metrics. Persisted via @AppStorage (UserDefaults key
/// `lucid_user_weight_kg`) so any engine can read it without a singleton.
private struct PersonalizationCard: View {
    @AppStorage(PersonalizationCard.weightKey) private var weightKg: Double = 76.0
    @AppStorage("lucid_user_height_cm") private var heightCm: Double = 178
    @AppStorage("lucid_user_age") private var ageYears: Int = 20
    @State private var weightText: String = ""
    @State private var heightText: String = ""
    @State private var ageText: String = ""
    @State private var savedFlash = false

    static let weightKey = "lucid_user_weight_kg"

    // Mifflin-St Jeor BMR — now uses your real height + age, not assumptions.
    private var bmr: Int {
        let value = 10 * weightKg + 6.25 * heightCm - 5 * Double(ageYears) + 5
        return Int(value.rounded())
    }

    private var tdee: Int {
        // moderate activity factor 1.55
        Int((Double(bmr) * 1.55).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            SectionHeader(
                icon: "person.text.rectangle",
                title: "PERSONALIZATION",
                iconColor: DS.Colors.violet
            )

            profileRow(label: "Weight", text: $weightText, unit: "kg",  placeholder: "76")
            profileRow(label: "Height", text: $heightText, unit: "cm",  placeholder: "178")
            profileRow(label: "Age",    text: $ageText,    unit: "yrs", placeholder: "20")

            Button { commit() } label: {
                Text(savedFlash ? "Saved — the food AI now uses this" : "Save profile")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(savedFlash ? DS.Colors.success : DS.Colors.violet))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            // Derived metrics — preview value of the input
            HStack(spacing: DS.Spacing.sm) {
                derivedTile(label: "BMR", value: "\(bmr)", unit: "kcal/day")
                derivedTile(label: "TDEE", value: "\(tdee)", unit: "× 1.55")
            }
            .padding(.top, 2)

            Text("Feeds calorie targets, alcohol BAC, strain-per-kg — and now the food AI's portion estimates. Sex assumed male; tell Lucid to change it.")
                .font(.system(size: 10))
                .foregroundStyle(DS.Colors.textMuted)
                .padding(.top, 2)
        }
        .padding(DS.Spacing.md)
        .glassDefault()
        .onAppear {
            weightText = formatWeight(weightKg)
            heightText = formatWeight(heightCm)
            ageText = "\(ageYears)"
            // Sync stored/seeded values to the server on open so the AI is current.
            Task { await pushProfile() }
        }
    }

    @ViewBuilder
    private func profileRow(label: String, text: Binding<String>, unit: String, placeholder: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.Colors.textSecondary)
            Spacer()
            HStack(spacing: 4) {
                TextField(placeholder, text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)
                    .frame(width: 70)
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.Colors.textMuted)
            }
        }
    }

    private func commit() {
        if let w = Double(weightText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)), w >= 30, w <= 250 { weightKg = w }
        if let h = Double(heightText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)), h >= 120, h <= 230 { heightCm = h }
        if let a = Int(ageText.trimmingCharacters(in: .whitespaces)), a >= 10, a <= 120 { ageYears = a }
        weightText = formatWeight(weightKg)
        heightText = formatWeight(heightCm)
        ageText = "\(ageYears)"
        withAnimation { savedFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { savedFlash = false }
        }
        Task { await pushProfile() }
    }

    private func pushProfile() async {
        await SupabaseClient.shared.saveBodyProfile(weightKg: weightKg, heightCm: heightCm, age: ageYears, sex: "male")
    }

    private func formatWeight(_ v: Double) -> String {
        // 1 decimal for non-integer, no decimal for whole numbers (76.0 → "76")
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    @ViewBuilder
    private func derivedTile(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(DS.Colors.textMuted)
                .tracking(0.6)
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(DS.Colors.textPrimary)
                .monospacedDigit()
            Text(unit)
                .font(.system(size: 9))
                .foregroundStyle(DS.Colors.textFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(DS.Colors.violet.opacity(0.06))
        )
    }
}
