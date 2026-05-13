# LucidHealth — Product Brief

> **register: product** — design SERVES the product, not the other way around. This is a personal cockpit, not a marketing surface.

## What this is

LucidHealth is a **single-user iOS 26 personal health cockpit** that combines:
- **Whoop 4.0 BLE biometric streaming** (HR, HRV/RMSSD, RR, sleep stages, recovery, strain, body battery, illness signals — algorithms inherited verbatim from LucidBridge, never modified)
- **Photo-based food logging** with Gemini 2.5 Flash vision + Open Food Facts barcode lookup
- **Pattern engine** that surfaces correlations between food and biometrics (n≥14 paired-observation gate before claims)

Built only for **Fabi** (the developer/owner). Distributed via AltStore alongside LucidBridge (legacy) and LucidFoods (legacy). Both legacy apps are kept installed-able as fallbacks but are being deprecated in favor of LucidHealth.

## Users

**Fabi** — single user. ADHD-driven, mild dyslexia, entrepreneur. Builds Essential Elements (German supplements) and Lucid (personal AI productivity OS). Uses iPhone running iOS 26. Wears a jailbroken Whoop 4.0 strap at all hours. Eats lunch with family every day (no phone at table). Doesn't drink keto, doesn't intermittent fast, drinks alcohol occasionally. Cooks for himself, eats out sometimes.

**No other users.** "Perfect for me, horrible for everyone else is fine." This is non-negotiable framing — opinionated decisions over universal compromises.

## Brand & tone

- **Lucid mesh-gradient + Liquid Glass + violet (#8B7CF6) + teal (#4FD1C5) accents** — see `Desktop/New Concepts/lucid-claude-design-bundle/01_DESIGN_SYSTEM.md` for exact tokens
- **Outfit font** preferred (matches Lucid web brand). SF Pro Rounded acceptable fallback if bundling Outfit isn't viable in this iteration
- **Voice: PINCH** (Passion / Interest / Novelty / Challenge / Humor). Never guilt, never "you should", never "crush your goals", never streaks-as-shame, never red-shaming missed meals
- **ADHD-protective**: pattern notes only when n≥14 paired observations. Alcohol framed as **explanation** ("the wine — not from you"), never warning

## Anti-references

- ❌ MyFitnessPal — gamified restriction, streak punishment, calorie-as-hero
- ❌ Apple Settings.app aesthetic — `List`, `Form`, default `TabView`, gray hairlines
- ❌ Generic AI-built health apps — pure black backgrounds, full-saturation accent everywhere, three-equal-cards row, default system blue
- ❌ Fitness-bro aesthetic — bold reds, locker-room copy, motivational shouting
- ❌ Dashboards-as-spreadsheets — too many widgets, no "one big thing" hero

## References to mimic (philosophically, not visually clone)

- ✅ **Whoop** — recovery-first hierarchy, body battery storyline, strain timeline as horizontal track
- ✅ **Oura** — single-hero "Readiness Score" with one-sentence AI narration (we will ADD this later when Lucid model is ready, **not** in this iteration)
- ✅ **Bevel Health** — Liquid Glass / depth / breath animation
- ✅ **Athlytic** — chart styling, recovery arc, AI tone

## Strategic principles (the 14 from `00_PRINCIPLES_EXTRACTED.md`)

Apply 1–14 from the Lucid bundle. Highest-impact for iOS dashboard are:
- **#1 Two-tone typographic hierarchy** — TwoToneHeadline component already exists, use everywhere
- **#4 Pill radii** as brand signature — 100px on chips, tabs, status badges, FAB
- **#5 Category dots** — 8px circles + label for grouping (Body / Mind / Sleep / Food)
- **#10 Size = hierarchy** — Recovery ring is the BIGGEST thing on Today, period
- **#11 Format diversity** — never two adjacent widgets in the same format. Ring → bar → number → list → grid, rotating
- **#12 Strong colors for status only** — saturated red/green/amber ONLY on recovery score, alcohol nights, illness risk. Everything structural stays muted

## Information architecture

**4 tabs** (Settings tab REMOVED, accessed via gear icon → sheet):
1. **Today** — at-a-glance health + food, time-of-day adaptive top section, hero recovery ring, quick-log row, last meal, pattern note when warranted
2. **Health** — biometric explorer: Live now / Recovery breakdown / HRV trends / Sleep stages / Strain & activity / Body battery / Illness signals
3. **Food** — daily totals, quick-log, filter chips, grouped meal history, fasting tracker, alcohol units this week
4. **Insights** — confidence-tier cards (Established / Emerging / Possible), n=X/14 progress card empty state, alcohol-explanation pattern post-hoc

Settings sheet (gear icon top-right of Today): auto-login status, BLE diagnostics (RSSI, packet rate, firmware), data sync, manual reconnect, export.

## Hard rules (non-negotiable)

1. **iOS 26 minimum** — no fallback code, use latest APIs (MeshGradient SwiftUI, `.glassEffect()`, `.sensoryFeedback`)
2. **Never `Color.blue`, `Color.gray`, raw hex in screens** — DS.Colors only
3. **Never `.padding(16)`, `.cornerRadius(8)` raw** — DS.Spacing / DS.Radius only
4. **Never modify** BLEManager, WhoopProtocol, any health engine, SupabaseClient, GeminiClient, any food service
5. **Never break** auto-login (CI sed-injected credentials), camera flow, barcode flow, quick-log flow
6. **Never** AI narration in this iteration (Lucid model will provide later)
7. **Both light and dark modes** ship simultaneously — no exceptions
8. **Pattern notes silent until n≥14** paired food + biometric observations
9. **Alcohol = explanation, not warning** — post-hoc framing only

## Strategic narrative

The killer feature isn't "track food" or "track biometrics" — it's **paired data**. 634 days of Whoop data + every meal Fabi logs from now = a personal metabolic research engine nobody else has. The UI must make this paired-data story feel **alive** — every food log shows its biometric impact tag, every recovery score shows what likely contributed.

This is not a fitness tracker. It's a **personal pattern engine**.
