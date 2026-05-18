import SwiftUI

/// Compact 14-day recovery trend shown directly under HeroRecoveryRing.
/// Exists because the ring shows a single context-free number — real
/// day-to-day movement (recovery genuinely swings 9-100) was invisible,
/// so a correct-but-varying score read as "stuck". This makes the
/// movement visible and the number trustworthy.
struct RecoveryTrendStrip: View {
    /// Recovery scores, oldest → newest (server `recovery_score`, NULLs dropped).
    let scores: [Double]

    private var avg: Double {
        guard !scores.isEmpty else { return 0 }
        return scores.reduce(0, +) / Double(scores.count)
    }
    private var today: Double { scores.last ?? 0 }
    private var delta: Int { Int((today - avg).rounded()) }

    var body: some View {
        // Need at least 3 points before a "trend" means anything.
        if scores.count >= 3 {
            VStack(spacing: DS.Spacing.xs) {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(scores.enumerated()), id: \.offset) { idx, s in
                        let isToday = idx == scores.count - 1
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(DS.Colors.recoveryColor(s))
                            .opacity(isToday ? 1.0 : 0.45)
                            .frame(height: barHeight(s))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 34)
                .animation(DS.Anim.cardAppear, value: scores)

                HStack(spacing: 4) {
                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("\(delta >= 0 ? "+" : "")\(delta) vs \(scores.count)-day avg")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(delta >= 0 ? DS.Colors.teal : DS.Colors.danger)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Recovery \(Int(today)), \(delta >= 0 ? "up" : "down") \(abs(delta)) versus your \(scores.count) day average")
        }
    }

    /// Map score 0-100 to a 6-34pt bar so even a low day stays visible.
    private func barHeight(_ s: Double) -> CGFloat {
        let clamped = max(0, min(100, s))
        return 6 + CGFloat(clamped / 100) * 28
    }
}
