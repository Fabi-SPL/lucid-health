import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════
// FormatDiversityHint — design rule documentation, principle #11
//
// RULE: No two adjacent widgets on any screen may use the same visual format.
//
// Mandatory rotation on Today screen:
//   1. Recovery  → RING          (HeroRecoveryRing)
//   2. Tasks     → LIST          (task rows with CategoryDot)
//   3. Habits    → GRID of rings (small ScoreRing grid)
//   4. Mood      → BIG NUMBER    (single metric + label)
//   5. Streak    → PROGRESS BAR  (linear fill)
//   6. Brain dump→ TEXT PREVIEW  (truncated text card)
//
// Never: two rings in a row. Never: two lists in a row.
//
// Why it matters: ADHD visual processing skips repeated formats.
// Novelty = attention lock. Rotate format = rotate attention back.
// ═══════════════════════════════════════════════════════════════════════════

// This file is intentionally a documentation-only module.
// No exported types — just the comment above for Phase B agent context.
