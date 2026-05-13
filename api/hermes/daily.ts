import type { VercelRequest, VercelResponse } from '@vercel/node'
import { createClient } from '@supabase/supabase-js'
import { PATTERNS, type Pattern, type PatternIO, type PatternsFile } from './patterns.js'
import { hermesAuthOk, authClient } from './_auth.js'

// ── Hermes V0 — pattern correlation engine ─────────────────────────────
// Reads patterns.yaml, queries daily aggregates, computes Pearson r per pattern,
// writes one row per pattern per run into `hermes_pattern_matches`.
//
// Triggers:
//   GET  /api/hermes/daily                         → run all patterns
//   POST /api/hermes/daily { "patterns": [...] }   → run only specified patterns
// Auth: `Authorization: Bearer $HERMES_TRIGGER_SECRET` (skipped if env unset)
//
// V0 scope: Pearson + Spearman (rank-Pearson) correlations on numeric daily
// time-series. Strat-ANOVA / t-test pattern types are recognised but skipped
// (logged as `skipped_unsupported_type`). Auto-discover pattern is also skipped.

const SUPABASE_URL = process.env.VITE_SUPABASE_URL || process.env.SUPABASE_URL || ''
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.VITE_SUPABASE_ANON_KEY || ''

const supabase = createClient(SUPABASE_URL, SUPABASE_KEY, {
  auth: { persistSession: false },
})

// ── Types ─────────────────────────────────────────────────────────────
interface RunResult {
  pattern: string
  matched: boolean | null
  r: number | null
  n: number
  threshold: number
  status: 'ok' | 'insufficient_data' | 'skipped_unsupported_type' | 'error'
  error?: string
}

// ── Pearson r ─────────────────────────────────────────────────────────
function pearson(xs: number[], ys: number[]): number | null {
  const n = xs.length
  if (n < 3 || ys.length !== n) return null
  let sx = 0, sy = 0
  for (let i = 0; i < n; i++) { sx += xs[i]; sy += ys[i] }
  const mx = sx / n, my = sy / n
  let num = 0, dx2 = 0, dy2 = 0
  for (let i = 0; i < n; i++) {
    const ax = xs[i] - mx, ay = ys[i] - my
    num += ax * ay; dx2 += ax * ax; dy2 += ay * ay
  }
  const den = Math.sqrt(dx2 * dy2)
  if (den === 0) return null
  return num / den
}

// Spearman = Pearson on ranks. Average ties.
function ranks(arr: number[]): number[] {
  const idx = arr.map((v, i) => ({ v, i })).sort((a, b) => a.v - b.v)
  const out = new Array(arr.length)
  let i = 0
  while (i < idx.length) {
    let j = i
    while (j + 1 < idx.length && idx[j + 1].v === idx[i].v) j++
    const avgRank = (i + j) / 2 + 1 // 1-indexed mean rank
    for (let k = i; k <= j; k++) out[idx[k].i] = avgRank
    i = j + 1
  }
  return out
}
function spearman(xs: number[], ys: number[]): number | null {
  if (xs.length !== ys.length || xs.length < 3) return null
  return pearson(ranks(xs), ranks(ys))
}

// ── Lag parsing ───────────────────────────────────────────────────────
function parseLagDays(lag: string | undefined): number {
  if (!lag) return 0
  const m = /^(-?\d+)d$/.exec(lag.trim())
  return m ? parseInt(m[1], 10) : 0
}

// ── Date helpers ──────────────────────────────────────────────────────
function isoDate(d: Date): string { return d.toISOString().slice(0, 10) }
function addDays(d: Date, days: number): Date {
  const r = new Date(d); r.setUTCDate(r.getUTCDate() + days); return r
}
function dateKey(s: string): string {
  // accept timestamp or date strings, normalise to YYYY-MM-DD UTC
  return s.length >= 10 ? s.slice(0, 10) : s
}

// ── Daily aggregation ─────────────────────────────────────────────────
// Each spec returns a map: dateString → numericValue
type DailyMap = Map<string, number>

async function fetchDaily(io: PatternIO, dateFrom: string, dateTo: string, userId: string): Promise<DailyMap> {
  const out: DailyMap = new Map()

  // Determine date column
  let dateCol = io.output_date_col || ''
  if (!dateCol) {
    // table-specific defaults
    if (io.table === 'health_metrics') dateCol = 'metric_date'
    else if (io.table === 'health_journal') dateCol = 'entry_date'
    else if (io.table === 'emotional_snapshots') dateCol = 'snapshot_date'
    else if (io.table === 'realtime_health') dateCol = 'recorded_at'
    else if (io.table === 'tasks') dateCol = 'completed_at'
    else if (io.table === 'brain_dumps') dateCol = 'created_at'
    else if (io.table === 'task_comments') dateCol = 'created_at'
    else dateCol = 'created_at'
  }

  // Build column list — keep it minimal
  const wantTransform = io.transform // expects valence + intensity for the canonical case
  const wantValenceShare = io.aggregation === 'daily_positive_share'
  const cols = new Set<string>([dateCol, io.column])
  if (wantTransform || wantValenceShare) cols.add('valence')
  if (wantTransform) cols.add('intensity')
  // realtime_health window/morning aggregations need recorded_at as timestamp
  if (io.table === 'realtime_health') cols.add('recorded_at')

  // Date range filter — use timestamp for created_at/recorded_at, date for *_date
  const isTs = dateCol === 'created_at' || dateCol === 'recorded_at' || dateCol === 'completed_at'
  const fromVal = isTs ? `${dateFrom}T00:00:00Z` : dateFrom
  const toVal = isTs ? `${dateTo}T23:59:59Z` : dateTo

  // Page in chunks (Supabase default cap is 1000; realtime_health is huge so cap window)
  let q = supabase.from(io.table).select(Array.from(cols).join(','))
    .eq('user_id', userId)
    .gte(dateCol, fromVal)
    .lte(dateCol, toVal)
    .order(dateCol, { ascending: true })
    .limit(50000)

  // health_journal filter is `question = '...'`
  if (io.filter && io.filter.includes("question = ")) {
    const m = /question\s*=\s*'([^']+)'/.exec(io.filter)
    if (m) q = q.eq('question', m[1])
  }

  const { data, error } = await q
  if (error) throw new Error(`fetch ${io.table}.${io.column}: ${error.message}`)
  if (!data) return out

  // Group rows by date according to aggregation spec
  type Row = Record<string, unknown>
  const groups = new Map<string, Row[]>()
  for (const rRaw of data as Row[]) {
    const dRaw = rRaw[dateCol]
    if (dRaw == null) continue
    const dk = dateKey(String(dRaw))
    if (!groups.has(dk)) groups.set(dk, [])
    groups.get(dk)!.push(rRaw)
  }

  for (const [dk, rows] of groups.entries()) {
    let v: number | null = null

    switch (io.aggregation) {
      case 'daily_first': {
        const r = rows[0]
        const raw = r[io.column]
        if (raw == null) break
        if (typeof raw === 'boolean') v = raw ? 1 : 0
        else if (typeof raw === 'number') v = raw
        else if (typeof raw === 'string') {
          const n = Number(raw); if (!Number.isNaN(n)) v = n
        }
        break
      }
      case 'daily_count': {
        // count rows that pass any extra (non-question) filter
        let count = rows.length
        if (io.filter && !io.filter.includes('question = ') && io.filter.includes('completed_at IS NOT NULL')) {
          count = rows.filter(r => r['completed_at'] != null).length
        }
        v = count
        break
      }
      case 'daily_avg': {
        // canonical: emotional_snapshots intensity * valence-sign
        const vals: number[] = []
        for (const r of rows) {
          let intensity = Number(r['intensity'] ?? r[io.column] ?? NaN)
          if (Number.isNaN(intensity)) continue
          if (io.transform && r['valence'] === 'negative') intensity = -intensity
          vals.push(intensity)
        }
        if (vals.length) v = vals.reduce((a, b) => a + b, 0) / vals.length
        break
      }
      case 'daily_positive_share': {
        const total = rows.length
        if (!total) break
        const pos = rows.filter(r => r['valence'] === 'positive').length
        v = pos / total
        break
      }
      case 'morning_window_avg': {
        // realtime_health 04:00–08:00 local (UTC offset ignored — V0 approximation)
        const vals: number[] = []
        for (const r of rows) {
          const ts = r['recorded_at']; if (!ts) continue
          const hr = new Date(String(ts)).getUTCHours()
          if (hr >= 4 && hr < 8) {
            const x = Number(r[io.column] ?? NaN)
            if (!Number.isNaN(x) && x > 0) vals.push(x)
          }
        }
        if (vals.length) v = vals.reduce((a, b) => a + b, 0) / vals.length
        break
      }
      case 'window_avg': {
        // generic HH:MM..HH:MM window
        const win = io.window || '00:00..23:59'
        const [a, b] = win.split('..')
        const [aH] = a.split(':').map(Number)
        const [bH] = b.split(':').map(Number)
        const vals: number[] = []
        for (const r of rows) {
          const ts = r['recorded_at']; if (!ts) continue
          const hr = new Date(String(ts)).getUTCHours()
          if (hr >= aH && hr < bH) {
            const x = Number(r[io.column] ?? NaN)
            if (!Number.isNaN(x)) vals.push(x)
          }
        }
        if (vals.length) v = vals.reduce((a, b) => a + b, 0) / vals.length
        break
      }
      case 'evening_avg': {
        // emotional_snapshots from 18:00 onward — but emotional_snapshots uses snapshot_date (date), not timestamp.
        // V0: fall back to daily_avg behaviour. Future: track snapshot timestamp once column exists.
        const vals: number[] = []
        for (const r of rows) {
          let intensity = Number(r['intensity'] ?? r[io.column] ?? NaN)
          if (Number.isNaN(intensity)) continue
          if (io.transform && r['valence'] === 'negative') intensity = -intensity
          vals.push(intensity)
        }
        if (vals.length) v = vals.reduce((a, b) => a + b, 0) / vals.length
        break
      }
      default:
        // unknown aggregation — treat as first numeric value
        for (const r of rows) {
          const x = Number(r[io.column] ?? NaN)
          if (!Number.isNaN(x)) { v = x; break }
        }
    }

    if (v != null && Number.isFinite(v)) out.set(dk, v)
  }

  return out
}

// ── Pair input/output by date with lag ────────────────────────────────
function pairWithLag(input: DailyMap, output: DailyMap, lagDays: number): { xs: number[]; ys: number[]; dates: string[] } {
  const xs: number[] = []; const ys: number[] = []; const dates: string[] = []
  for (const [dk, x] of input.entries()) {
    const d = new Date(`${dk}T00:00:00Z`)
    const lagged = isoDate(addDays(d, lagDays))
    const y = output.get(lagged)
    if (y != null) { xs.push(x); ys.push(y); dates.push(dk) }
  }
  return { xs, ys, dates }
}

// ── V1 stat helpers (t-test + one-way ANOVA, effect-size based) ────────
function mean(xs: number[]): number {
  if (!xs.length) return 0
  return xs.reduce((a, b) => a + b, 0) / xs.length
}
function variance(xs: number[], m: number): number {
  if (xs.length < 2) return 0
  let s = 0
  for (const x of xs) { const d = x - m; s += d * d }
  return s / (xs.length - 1)
}

/**
 * Welch's two-sample t-test → returns Cohen's d (effect size).
 * Skips p-value calculation in V1; matching uses effect_size_min directly.
 * Sign convention: positive = g1 > g2 (input=true higher).
 */
function welchEffect(g1: number[], g2: number[]): { d: number; m1: number; m2: number; n1: number; n2: number } | null {
  if (g1.length < 3 || g2.length < 3) return null
  const m1 = mean(g1), m2 = mean(g2)
  const v1 = variance(g1, m1), v2 = variance(g2, m2)
  const pooledSd = Math.sqrt((v1 + v2) / 2)
  if (pooledSd === 0 || !Number.isFinite(pooledSd)) return null
  return { d: (m1 - m2) / pooledSd, m1, m2, n1: g1.length, n2: g2.length }
}

/**
 * One-way ANOVA → returns eta-squared (effect size).
 * Maps each value to a group key, computes between/within sum of squares.
 */
function etaSquared(groups: Map<string | number, number[]>): { eta: number; k: number; n: number; group_means: Record<string, number> } | null {
  let allVals: number[] = []
  const groupArr = [...groups.entries()].filter(([, v]) => v.length >= 2)
  if (groupArr.length < 2) return null
  for (const [, v] of groupArr) allVals = allVals.concat(v)
  if (allVals.length < 6) return null
  const grand = mean(allVals)
  let ssb = 0
  let ssw = 0
  const group_means: Record<string, number> = {}
  for (const [k, v] of groupArr) {
    const m = mean(v)
    group_means[String(k)] = Number(m.toFixed(2))
    ssb += v.length * (m - grand) * (m - grand)
    for (const x of v) ssw += (x - m) * (x - m)
  }
  const total = ssb + ssw
  if (total === 0) return null
  return { eta: ssb / total, k: groupArr.length, n: allVals.length, group_means }
}

function groupKeyForDate(dateKey: string, groupBy: string | undefined): string | number | null {
  const d = new Date(`${dateKey}T00:00:00Z`)
  if (groupBy === 'day_of_week') return d.getUTCDay()
  if (groupBy === 'month') return d.getUTCMonth()
  return null
}

// ── Run a single pattern ──────────────────────────────────────────────
async function runPattern(p: Pattern, defaults: PatternsFile['defaults']): Promise<RunResult> {
  const minN = p.min_n ?? defaults.min_n
  const threshold = p.threshold ?? defaults.threshold
  const corrType = (p.correlation_type ?? defaults.correlation_type ?? 'pearson').toLowerCase()
  const ptype = p.type ?? corrType

  // V0.7 — t-test handler (binary input → continuous output)
  if (ptype === 't_test_two_sample') {
    return runTTestPattern(p, defaults)
  }
  // V0.7 — one-way ANOVA handler (stratified by day_of_week or month)
  if (ptype === 'stratified_anova') {
    return runAnovaPattern(p, defaults)
  }
  // Auto-discover still skipped — needs separate weekly endpoint
  if (ptype === 'auto_discover') {
    return { pattern: p.name, matched: null, r: null, n: 0, threshold, status: 'skipped_unsupported_type' }
  }

  if (!p.input || !p.output) {
    return { pattern: p.name, matched: null, r: null, n: 0, threshold, status: 'error', error: 'missing input/output' }
  }

  const lagDays = parseLagDays(p.lag)
  // Window: need pairs spanning at least minN*3 days. Pull a window of minN*3 + lag days
  // ending today, so we have history.
  const today = new Date()
  const windowDays = Math.max(60, minN * 3 + Math.abs(lagDays))
  const dateTo = isoDate(today)
  const dateFrom = isoDate(addDays(today, -windowDays))

  const userId = defaults.user_id
  let inputMap: DailyMap
  let outputMap: DailyMap
  try {
    inputMap = await fetchDaily(p.input, dateFrom, dateTo, userId)
    outputMap = await fetchDaily(p.output, dateFrom, dateTo, userId)
  } catch (e: unknown) {
    return { pattern: p.name, matched: null, r: null, n: 0, threshold, status: 'error', error: (e as Error).message }
  }

  const { xs, ys, dates } = pairWithLag(inputMap, outputMap, lagDays)
  if (xs.length < minN) {
    return { pattern: p.name, matched: false, r: null, n: xs.length, threshold, status: 'insufficient_data' }
  }

  const r = corrType === 'spearman' ? spearman(xs, ys) : pearson(xs, ys)
  if (r == null) {
    return { pattern: p.name, matched: false, r: null, n: xs.length, threshold, status: 'error', error: 'r undefined (zero variance)' }
  }

  // direction check (if specified, sign must match)
  let matched = Math.abs(r) >= threshold && xs.length >= minN
  if (matched && p.direction === 'negative' && r > 0) matched = false
  if (matched && p.direction === 'positive' && r < 0) matched = false

  const winStart = dates[0]
  const winEnd = dates[dates.length - 1]

  // Insert into hermes_pattern_matches
  const { error: insErr } = await supabase.from('hermes_pattern_matches').insert({
    pattern_name: p.name,
    pattern_type: corrType,
    matched,
    correlation_r: r,
    n_samples: xs.length,
    threshold,
    window_start: winStart,
    window_end: winEnd,
    details: {
      lag_days: lagDays,
      direction: p.direction ?? null,
      input: { table: p.input.table, column: p.input.column, aggregation: p.input.aggregation },
      output: { table: p.output.table, column: p.output.column, aggregation: p.output.aggregation },
      description: p.description ?? null,
    },
  })
  if (insErr) {
    return { pattern: p.name, matched, r, n: xs.length, threshold, status: 'error', error: `insert: ${insErr.message}` }
  }

  return { pattern: p.name, matched, r, n: xs.length, threshold, status: 'ok' }
}

// ── V1 t-test runner (binary input → continuous output) ───────────────
async function runTTestPattern(p: Pattern, defaults: PatternsFile['defaults']): Promise<RunResult> {
  const minN = p.min_n ?? defaults.min_n
  const effectMin = p.effect_size_min ?? 0.3
  if (!p.input || !p.output) {
    return { pattern: p.name, matched: null, r: null, n: 0, threshold: effectMin, status: 'error', error: 'missing input/output' }
  }
  const lagDays = parseLagDays(p.lag)
  const today = new Date()
  const windowDays = Math.max(120, minN * 4 + Math.abs(lagDays))
  const dateTo = isoDate(today)
  const dateFrom = isoDate(addDays(today, -windowDays))
  const userId = defaults.user_id

  let inputMap: DailyMap, outputMap: DailyMap
  try {
    inputMap = await fetchDaily(p.input, dateFrom, dateTo, userId)
    outputMap = await fetchDaily(p.output, dateFrom, dateTo, userId)
  } catch (e: unknown) {
    return { pattern: p.name, matched: null, r: null, n: 0, threshold: effectMin, status: 'error', error: (e as Error).message }
  }

  // Split paired output values by binary input (>= 0.5 = true)
  const g1: number[] = []   // input "yes"
  const g2: number[] = []   // input "no"
  for (const [dk, x] of inputMap.entries()) {
    const d = new Date(`${dk}T00:00:00Z`)
    const lagged = isoDate(addDays(d, lagDays))
    const y = outputMap.get(lagged)
    if (y == null || !Number.isFinite(y)) continue
    if (x >= 0.5) g1.push(y); else g2.push(y)
  }
  const n = g1.length + g2.length
  if (n < minN) {
    return { pattern: p.name, matched: false, r: null, n, threshold: effectMin, status: 'insufficient_data' }
  }
  const e = welchEffect(g1, g2)
  if (!e) {
    return { pattern: p.name, matched: false, r: null, n, threshold: effectMin, status: 'error', error: 't-test undefined (zero variance)' }
  }
  let matched = Math.abs(e.d) >= effectMin
  if (matched && p.direction === 'negative' && e.d > 0) matched = false
  if (matched && p.direction === 'positive' && e.d < 0) matched = false

  const { error: insErr } = await supabase.from('hermes_pattern_matches').insert({
    pattern_name: p.name,
    pattern_type: 't_test_two_sample',
    matched,
    correlation_r: Number(e.d.toFixed(4)),  // store Cohen's d as effect-size proxy
    n_samples: n,
    threshold: effectMin,
    window_start: dateFrom,
    window_end: dateTo,
    details: {
      lag_days: lagDays,
      direction: p.direction ?? null,
      input: { table: p.input.table, column: p.input.column, aggregation: p.input.aggregation },
      output: { table: p.output.table, column: p.output.column, aggregation: p.output.aggregation },
      effect_size_cohens_d: Number(e.d.toFixed(4)),
      group_yes: { mean: Number(e.m1.toFixed(3)), n: e.n1 },
      group_no:  { mean: Number(e.m2.toFixed(3)), n: e.n2 },
      description: p.description ?? null,
    },
  })
  if (insErr) {
    return { pattern: p.name, matched, r: e.d, n, threshold: effectMin, status: 'error', error: `insert: ${insErr.message}` }
  }
  return { pattern: p.name, matched, r: e.d, n, threshold: effectMin, status: 'ok' }
}

// ── V1 stratified ANOVA runner (group_by: day_of_week or month) ────────
async function runAnovaPattern(p: Pattern, defaults: PatternsFile['defaults']): Promise<RunResult> {
  const minN = p.min_n ?? defaults.min_n
  const etaThreshold = p.threshold ?? 0.05
  if (!p.input) {
    return { pattern: p.name, matched: null, r: null, n: 0, threshold: etaThreshold, status: 'error', error: 'missing input' }
  }
  const groupBy = p.group_by ?? 'day_of_week'
  if (groupBy !== 'day_of_week' && groupBy !== 'month') {
    return { pattern: p.name, matched: null, r: null, n: 0, threshold: etaThreshold, status: 'error', error: `unsupported group_by: ${groupBy}` }
  }

  // For ANOVA we want a LONG window — Fabi has 600+ days of WHOOP
  const today = new Date()
  const windowDays = Math.max(365, minN * 3)
  const dateTo = isoDate(today)
  const dateFrom = isoDate(addDays(today, -windowDays))
  const userId = defaults.user_id

  let inputMap: DailyMap
  try {
    inputMap = await fetchDaily(p.input, dateFrom, dateTo, userId)
  } catch (e: unknown) {
    return { pattern: p.name, matched: null, r: null, n: 0, threshold: etaThreshold, status: 'error', error: (e as Error).message }
  }

  // Group by category key
  const groups = new Map<string | number, number[]>()
  for (const [dk, v] of inputMap.entries()) {
    if (!Number.isFinite(v)) continue
    const key = groupKeyForDate(dk, groupBy)
    if (key == null) continue
    if (!groups.has(key)) groups.set(key, [])
    groups.get(key)!.push(v)
  }

  const r = etaSquared(groups)
  if (!r) {
    return { pattern: p.name, matched: false, r: null, n: 0, threshold: etaThreshold, status: 'insufficient_data' }
  }
  if (r.n < minN) {
    return { pattern: p.name, matched: false, r: r.eta, n: r.n, threshold: etaThreshold, status: 'insufficient_data' }
  }
  const matched = r.eta >= etaThreshold

  const { error: insErr } = await supabase.from('hermes_pattern_matches').insert({
    pattern_name: p.name,
    pattern_type: 'stratified_anova',
    matched,
    correlation_r: Number(r.eta.toFixed(4)),  // store eta-squared as strength proxy
    n_samples: r.n,
    threshold: etaThreshold,
    window_start: dateFrom,
    window_end: dateTo,
    details: {
      group_by: groupBy,
      input: { table: p.input.table, column: p.input.column, aggregation: p.input.aggregation },
      eta_squared: Number(r.eta.toFixed(4)),
      k_groups: r.k,
      group_means: r.group_means,
      description: p.description ?? null,
    },
  })
  if (insErr) {
    return { pattern: p.name, matched, r: r.eta, n: r.n, threshold: etaThreshold, status: 'error', error: `insert: ${insErr.message}` }
  }
  return { pattern: p.name, matched, r: r.eta, n: r.n, threshold: etaThreshold, status: 'ok' }
}

// ── Patterns loader ──────────────────────────────────────────────────
// Patterns are bundled as a TS module (see ./patterns.ts) so Vercel's
// serverless bundler picks them up automatically. Canonical YAML lives
// at lucid-hermes/patterns.yaml — regenerate ./patterns.ts when editing.
function loadPatterns(): PatternsFile { return PATTERNS }

// ── Auth (shared helper — accepts HERMES_TRIGGER_SECRET, CRON_SECRET,
// vercel-cron user-agent fallback, or user JWT) ───────────────────────
const authVerifier = authClient()

// ── Handler ───────────────────────────────────────────────────────────
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (!(await hermesAuthOk(req, authVerifier))) return res.status(401).json({ error: 'Unauthorized' })

  let cfg: PatternsFile
  try { cfg = loadPatterns() } catch (e: unknown) {
    return res.status(500).json({ error: 'patterns_load_failed', message: (e as Error).message })
  }

  const requested: string[] | null = req.method === 'POST'
    ? (Array.isArray((req.body as { patterns?: string[] })?.patterns) ? (req.body as { patterns: string[] }).patterns : null)
    : null

  const toRun = requested
    ? cfg.patterns.filter(p => requested.includes(p.name))
    : cfg.patterns

  const results: RunResult[] = []
  for (const p of toRun) {
    try {
      results.push(await runPattern(p, cfg.defaults))
    } catch (e: unknown) {
      results.push({ pattern: p.name, matched: null, r: null, n: 0, threshold: p.threshold ?? cfg.defaults.threshold, status: 'error', error: (e as Error).message })
    }
  }

  const matches = results.filter(r => r.matched === true).length
  const errors = results.filter(r => r.status === 'error')
  const skipped = results.filter(r => r.status === 'skipped_unsupported_type')

  return res.status(200).json({
    runs: results.length,
    matches,
    errors: errors.map(e => ({ pattern: e.pattern, error: e.error })),
    skipped_unsupported: skipped.map(s => s.pattern),
    results,
  })
}
