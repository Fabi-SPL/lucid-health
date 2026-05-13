import SwiftUI

// ════════════════════════════════════════════════════════════════════════
// Experimental feature cards (Discord, Hue, Spiral log) for SettingsView
// All four Whoop-pattern foundations land here. Coherence drill lives in
// its own full-screen view (CoherenceDrillView).
// ════════════════════════════════════════════════════════════════════════

// MARK: - Discord Broadcast Card

struct DiscordBroadcastCard: View {
    @State private var enabled = false
    @State private var webhookURL = ""
    @State private var customLabel = ""
    @State private var showHR = true
    @State private var showHRV = true
    @State private var showStrain = false
    @State private var showState = false
    @State private var refreshSeconds = 10
    @State private var pushCount = 0
    @State private var lastPushedAt: String? = nil
    @State private var loaded = false
    @State private var saving = false
    @State private var savedFlash = false
    @State private var expanded = false

    private let svc = ExperimentalFeaturesService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                SectionHeader(icon: "megaphone.fill", title: "Discord Broadcast", iconColor: DS.Colors.violet)
                Spacer()
                if enabled && pushCount > 0 {
                    StatusChip(text: "live · \(pushCount)", style: .teal, icon: "dot.radiowaves.left.and.right")
                }
            }

            Text("Replaces Pulsoid / HypeRate. Posts your live biometrics to a Discord channel via webhook — edits one message instead of spamming chat.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(DS.Colors.textSecondary)
                .lineLimit(nil)

            // Master toggle
            Toggle(isOn: $enabled) {
                Text("Broadcast enabled")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)
            }
            .tint(DS.Colors.violet)

            // Expand for config
            Button {
                withAnimation(.spring(duration: 0.4)) { expanded.toggle() }
            } label: {
                HStack {
                    Text(expanded ? "Hide config" : "Show config")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.Colors.violet)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Colors.violet)
                }
            }

            if expanded {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    // Webhook URL
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DISCORD WEBHOOK URL")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(DS.Colors.textMuted)
                        TextField("https://discord.com/api/webhooks/...", text: $webhookURL)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(8)
                            .background(DS.Colors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }

                    // Custom label
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CUSTOM LABEL (optional)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(DS.Colors.textMuted)
                        TextField("fabi gaming", text: $customLabel)
                            .font(.system(size: 12, design: .rounded))
                            .padding(8)
                            .background(DS.Colors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Field toggles
                    VStack(spacing: 6) {
                        toggleRow("♥ heart rate", $showHR, color: .red)
                        toggleRow("𝓥 hrv", $showHRV, color: DS.Colors.teal)
                        toggleRow("💪 strain (edwards trimp)", $showStrain, color: DS.Colors.amber)
                        toggleRow("🧠 hmm state", $showState, color: DS.Colors.violet)
                    }

                    // Refresh interval
                    HStack {
                        Text("REFRESH")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(DS.Colors.textMuted)
                        Spacer()
                        ForEach([5, 10, 30], id: \.self) { sec in
                            Button { refreshSeconds = sec } label: {
                                Text("\(sec)s")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .foregroundStyle(refreshSeconds == sec ? .white : DS.Colors.textSecondary)
                                    .background(refreshSeconds == sec ? DS.Colors.violet : DS.Colors.surface)
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    if pushCount > 0 {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(DS.Colors.teal)
                                .font(.system(size: 12))
                            Text("\(pushCount) updates pushed")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(DS.Colors.textMuted)
                        }
                    }
                }
            }

            // Save button
            Button {
                Task { await save() }
            } label: {
                HStack {
                    if saving {
                        ProgressView().scaleEffect(0.7)
                    } else if savedFlash {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    Text(savedFlash ? "Saved" : "Save settings")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(LinearGradient(colors: [DS.Colors.violet, DS.Colors.teal], startPoint: .leading, endPoint: .trailing))
                .clipShape(Capsule())
            }
            .disabled(saving || webhookURL.isEmpty)
            .opacity(webhookURL.isEmpty ? 0.4 : 1.0)
        }
        .padding(DS.Spacing.lg)
        .glassDefault()
        .task {
            if !loaded { await loadSettings() }
        }
    }

    @ViewBuilder
    private func toggleRow(_ label: String, _ binding: Binding<Bool>, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(DS.Colors.textPrimary)
            Spacer()
            Toggle("", isOn: binding)
                .labelsHidden()
                .tint(color)
                .scaleEffect(0.85)
        }
    }

    private func loadSettings() async {
        if let s = await svc.fetchBroadcastSettings() {
            await MainActor.run {
                enabled = s.enabled
                webhookURL = s.discord_webhook ?? ""
                customLabel = s.custom_label ?? ""
                showHR = s.show_hr
                showHRV = s.show_hrv
                showStrain = s.show_strain
                showState = s.show_state
                refreshSeconds = s.refresh_seconds
                pushCount = s.push_count ?? 0
                lastPushedAt = s.last_pushed_at
                loaded = true
            }
        } else {
            loaded = true
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let s = ExperimentalFeaturesService.BroadcastSettings(
            enabled: enabled,
            discord_webhook: webhookURL.isEmpty ? nil : webhookURL,
            show_hr: showHR, show_hrv: showHRV,
            show_strain: showStrain, show_state: showState,
            refresh_seconds: refreshSeconds,
            custom_label: customLabel.isEmpty ? nil : customLabel,
            push_count: nil, last_pushed_at: nil
        )
        let ok = await svc.upsertBroadcastSettings(s)
        if ok {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            await MainActor.run {
                savedFlash = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    savedFlash = false
                }
            }
        }
    }
}

// MARK: - VRChat OSC Broadcast Card

struct VRChatBroadcastCard: View {
    @State private var enabled = false
    @State private var lastMessage: String? = nil
    @State private var loaded = false
    @State private var saving = false

    private let svc = ExperimentalFeaturesService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                SectionHeader(icon: "globe", title: "VRChat Chatbox", iconColor: DS.Colors.teal)
                Spacer()
                if enabled {
                    StatusChip(text: "live", style: .teal, icon: "dot.radiowaves.left.and.right")
                }
            }

            Text("Broadcasts your live biometrics to VRChat. All formatting and mode config lives in the Magic Chatbox app on Windows. This toggle just gates whether broadcasting runs.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(DS.Colors.textSecondary)

            if let last = lastMessage, !last.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Colors.teal)
                    Text(last)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(DS.Colors.textPrimary)
                        .lineLimit(2)
                }
                .padding(8)
                .background(DS.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Toggle(isOn: $enabled) {
                Text("Broadcaster on")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)
            }
            .tint(DS.Colors.teal)
            .onChange(of: enabled) { _, newValue in
                // Mirror to UserDefaults + notify BLEManager to retune pushInterval.
                // BLEManager pushes every 1s when broadcaster is ON (real-time
                // chatbox/avatar) and every 10s when OFF (battery conservation).
                UserDefaults.standard.set(newValue, forKey: BLEManager.vrcBroadcastEnabledKey)
                NotificationCenter.default.post(name: .lucidVRCToggleChanged, object: nil)
                Task { await save() }
            }
        }
        .padding(DS.Spacing.lg)
        .glassDefault()
        .task { if !loaded { await load() } }
    }

    private func load() async {
        if let s = await svc.fetchVRCSettings() {
            await MainActor.run {
                enabled = s.enabled
                lastMessage = s.last_message
                loaded = true
                // Sync UserDefaults mirror + notify BLEManager so pushInterval
                // matches the persisted Supabase state on every app launch.
                UserDefaults.standard.set(s.enabled, forKey: BLEManager.vrcBroadcastEnabledKey)
                NotificationCenter.default.post(name: .lucidVRCToggleChanged, object: nil)
            }
        } else {
            loaded = true
        }
    }

    private func save() async {
        guard loaded else { return }
        saving = true
        defer { saving = false }
        // Fetch existing settings to preserve fields the broadcaster's UI now owns
        // (mode, vibe_style, privacy_mode, etc.). We only mutate enabled.
        if var s = await svc.fetchVRCSettings() {
            s.enabled = enabled
            _ = await svc.upsertVRCSettings(s)
        } else {
            // First-run: write a sensible default record with just enabled
            let fresh = ExperimentalFeaturesService.VRCSettings(
                enabled: enabled,
                osc_host: "127.0.0.1", osc_port: 9000, refresh_seconds: 1.0,
                mode: "vibe",
                show_hr: true, show_hrv: true, show_baevsky: false,
                show_strain: false, show_state: false,
                show_recovery: false, show_body_battery: false,
                show_skin_temp: false, show_coherence: false,
                show_streak: false, show_spiral_count: false,
                show_label: true,
                custom_template: nil, custom_label: nil,
                rotate_seconds: 8,
                push_count: nil, last_message: nil,
                privacy_mode: true, vibe_style: "heart",
                show_vibe_duration: true,
                show_energy_bar: false, show_drunk_bar: false,
                drunk_only_when_tagged: true,
                energy_bar_chars: 10, drunk_bar_chars: 10
            )
            _ = await svc.upsertVRCSettings(fresh)
        }
        if enabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

// MARK: - Hue Mirror Card (small, foundation only)

struct HueMirrorCard: View {
    @State private var enabled = false
    @State private var bridgeIP = ""
    @State private var bridgeToken = ""
    @State private var groupID = ""
    @State private var onlyAfterSundown = true
    @State private var loaded = false
    @State private var saving = false
    @State private var expanded = false

    private let svc = ExperimentalFeaturesService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                SectionHeader(icon: "lightbulb.fill", title: "Hue Mirror", iconColor: DS.Colors.amber)
                Spacer()
                StatusChip(text: enabled ? "on" : "off", style: enabled ? .teal : .violet)
            }

            Text("Optional. Maps your nervous system state → bedside light color (calm = teal, stressed = amber → red). Foundation only — not actively pushed.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(DS.Colors.textSecondary)

            Toggle("Enable Hue mirror", isOn: $enabled)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .tint(DS.Colors.amber)

            Button {
                withAnimation(.spring(duration: 0.4)) { expanded.toggle() }
            } label: {
                Text(expanded ? "Hide config" : "Configure bridge")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.Colors.amber)
            }

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    inputField("BRIDGE IP", $bridgeIP, placeholder: "192.168.1.42")
                    inputField("API TOKEN", $bridgeToken, placeholder: "from Hue API")
                    inputField("GROUP ID", $groupID, placeholder: "1")
                    Toggle("Only after sundown", isOn: $onlyAfterSundown)
                        .font(.system(size: 11, design: .rounded))
                        .tint(DS.Colors.amber)
                }
            }

            Button {
                Task { await save() }
            } label: {
                Text("Save")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(DS.Colors.amber)
                    .clipShape(Capsule())
            }
            .disabled(saving)
        }
        .padding(DS.Spacing.lg)
        .glassDefault()
        .task { if !loaded { await loadSettings() } }
    }

    @ViewBuilder
    private func inputField(_ label: String, _ binding: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(DS.Colors.textMuted)
            TextField(placeholder, text: binding)
                .font(.system(size: 11, design: .monospaced))
                .padding(6)
                .background(DS.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .autocapitalization(.none)
                .autocorrectionDisabled()
        }
    }

    private func loadSettings() async {
        if let s = await svc.fetchHueSettings() {
            await MainActor.run {
                enabled = s.enabled
                bridgeIP = s.bridge_ip ?? ""
                bridgeToken = s.bridge_token ?? ""
                groupID = s.group_id ?? ""
                onlyAfterSundown = s.only_after_sundown
                loaded = true
            }
        } else { loaded = true }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let s = ExperimentalFeaturesService.HueSettings(
            enabled: enabled,
            bridge_ip: bridgeIP.isEmpty ? nil : bridgeIP,
            bridge_token: bridgeToken.isEmpty ? nil : bridgeToken,
            group_id: groupID.isEmpty ? nil : groupID,
            only_after_sundown: onlyAfterSundown
        )
        _ = await svc.upsertHueSettings(s)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Spiral Alerts Log Card

struct SpiralAlertsLogCard: View {
    @State private var alerts: [ExperimentalFeaturesService.SpiralAlert] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                SectionHeader(icon: "tornado", title: "Spiral Alerts", iconColor: DS.Colors.pink)
                Spacer()
                StatusChip(text: "\(alerts.count) recent", style: .violet)
            }

            Text("Mini-Lucid pings when HRV crashes 20%+ and HR rises 15%+ for ≥10 min. Cooldown 4h.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(DS.Colors.textSecondary)

            if !loaded {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
            } else if alerts.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DS.Colors.teal)
                    Text("no spirals detected · clean week")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(DS.Colors.textMuted)
                }
                .padding(.vertical, 8)
            } else {
                ForEach(alerts) { alert in
                    spiralRow(alert)
                }
            }
        }
        .padding(DS.Spacing.lg)
        .glassDefault()
        .task { await loadAlerts() }
    }

    @ViewBuilder
    private func spiralRow(_ alert: ExperimentalFeaturesService.SpiralAlert) -> some View {
        let dropPct = alert.hrv_drop_pct ?? 0
        let risePct = alert.hr_rise_pct ?? 0
        HStack(spacing: 10) {
            Circle()
                .fill(dropPct > 30 ? DS.Colors.danger : DS.Colors.amber)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(formatTime(alert.fired_at))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DS.Colors.textPrimary)
                HStack(spacing: 6) {
                    Text("HRV ↓\(Int(dropPct))%")
                        .foregroundStyle(DS.Colors.danger)
                    Text("·").foregroundStyle(DS.Colors.textFaint)
                    Text("HR ↑\(Int(risePct))%")
                        .foregroundStyle(DS.Colors.amber)
                    if let st = alert.hmm_state {
                        Text("·").foregroundStyle(DS.Colors.textFaint)
                        Text(st)
                            .foregroundStyle(DS.Colors.violet)
                    }
                }
                .font(.system(size: 10, design: .monospaced))
            }
            Spacer()
            if let resp = alert.user_response {
                StatusChip(text: resp, style: resp == "opened" ? .teal : .violet)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatTime(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return iso }
        let out = DateFormatter()
        out.dateFormat = "MMM d · HH:mm"
        return out.string(from: d)
    }

    private func loadAlerts() async {
        let result = await ExperimentalFeaturesService.shared.fetchSpiralAlerts(limit: 5)
        await MainActor.run {
            alerts = result
            loaded = true
        }
    }
}
