// ── Hermes V0 — pattern definitions ────────────────────────────────────
// Auto-bundled into the Vercel function. Canonical source-of-truth lives at
// `lucid-hermes/patterns.yaml` — when you edit that, regenerate this file
// (or just re-export the parsed structure) so the deploy picks it up.

export interface PatternIO {
  table: string
  column: string
  aggregation: string
  filter?: string
  transform?: string
  output_date_col?: string
  window?: string
}

export interface Pattern {
  name: string
  description?: string
  type?: string
  input?: PatternIO
  output?: PatternIO
  lag?: string
  correlation_type?: string
  threshold?: number
  min_n?: number
  direction?: string
  group_by?: string | null
  // auto_discover-only fields
  schedule?: string
  lags?: string[]
  correction?: string
  surface_top_n?: number
  exclude_already_registered?: boolean
  require_directional_consistency?: boolean
  deliver?: string
  // stratified_anova-only fields
  test?: string
  // t_test-only fields
  effect_size_min?: number
}

export interface PatternsFile {
  version?: string
  defaults: {
    user_id: string
    min_n: number
    threshold: number
    correlation_type: string
    alpha?: number
    exclude_soft_days?: boolean
    rolling_baseline_days?: number
  }
  patterns: Pattern[]
}

export const PATTERNS: PatternsFile = {
  version: '0.1.0',
  defaults: {
    user_id: process.env.HERMES_USER_ID || '',
    min_n: 14,
    threshold: 0.4,
    correlation_type: 'pearson',
    alpha: 0.05,
    exclude_soft_days: false,
    rolling_baseline_days: 60,
  },
  patterns: [
    {
      name: 'Morning HRV → next-day mood intensity',
      description: 'Higher overnight HRV predicts more positive mood the following day. Foundational autonomic-affect link; replicates the Plews/Buchheit literature on personal use.',
      input: {
        table: 'realtime_health',
        column: 'hrv_rmssd',
        aggregation: 'morning_window_avg',
        filter: 'sleep_stage IS NOT NULL OR hrv_rmssd > 0',
      },
      output: {
        table: 'emotional_snapshots',
        column: 'intensity',
        aggregation: 'daily_avg',
        transform: "CASE WHEN valence='negative' THEN -intensity ELSE intensity END",
      },
      lag: '0d',
      correlation_type: 'spearman',
      threshold: 0.35,
      min_n: 30,
      group_by: null,
    },
    {
      name: 'Sleep hours → next-day task completion count',
      description: 'Tests Walker-style sleep-deprivation prediction with personal data: less sleep predicts fewer completed tasks the next day.',
      input: {
        table: 'health_metrics',
        column: 'sleep_hours',
        aggregation: 'daily_first',
      },
      output: {
        table: 'tasks',
        column: 'id',
        aggregation: 'daily_count',
        filter: 'completed_at IS NOT NULL',
        output_date_col: 'completed_at',
      },
      lag: '0d',
      correlation_type: 'spearman',
      threshold: 0.3,
      min_n: 30,
      group_by: null,
    },
    {
      name: 'Sleep efficiency % → next-day mood valence',
      description: 'Sleep quality matters more than quantity for mood — efficient sleep should predict more positive emotional snapshots.',
      input: {
        table: 'health_metrics',
        column: 'sleep_efficiency_pct',
        aggregation: 'daily_first',
      },
      output: {
        table: 'emotional_snapshots',
        column: 'valence',
        aggregation: 'daily_positive_share',
      },
      lag: '0d',
      correlation_type: 'pearson',
      threshold: 0.35,
      min_n: 30,
    },
    {
      name: 'Strain score → HRV 2 days later',
      description: 'Acute training strain tends to suppress HRV with a 24–48h lag. Tests if Fabi\'s recovery follows this pattern.',
      input: {
        table: 'health_metrics',
        column: 'strain_score',
        aggregation: 'daily_first',
      },
      output: {
        table: 'health_metrics',
        column: 'hrv_avg',
        aggregation: 'daily_first',
      },
      lag: '2d',
      correlation_type: 'pearson',
      threshold: 0.3,
      min_n: 60,
      direction: 'negative',
    },
    {
      name: 'Day-of-week HRV stratification',
      description: 'Some people show \'Monday blues\' or \'Sunday social-recovery\' patterns in HRV. Tests if any weekday is reliably above/below personal baseline.',
      input: {
        table: 'health_metrics',
        column: 'hrv_avg',
        aggregation: 'daily_first',
      },
      output: {
        table: 'health_metrics',
        column: 'hrv_avg',
        aggregation: 'daily_first',
      },
      lag: '0d',
      type: 'stratified_anova',
      group_by: 'day_of_week',
      threshold: 0.05,
      min_n: 100,
      test: 'anova_with_tukey',
    },
    {
      name: 'Seasonal HRV pattern (monthly)',
      description: 'Light/temperature seasonality can shift autonomic baseline. With 22mo of data we have ~2 instances of each month — surface any month with HRV >0.5SD off rolling baseline.',
      input: {
        table: 'health_metrics',
        column: 'hrv_avg',
        aggregation: 'daily_first',
      },
      output: {
        table: 'health_metrics',
        column: 'hrv_avg',
        aggregation: 'daily_first',
      },
      lag: '0d',
      type: 'stratified_anova',
      group_by: 'month',
      threshold: 0.05,
      min_n: 200,
      test: 'anova_with_tukey',
    },
    {
      name: 'Brain dump frequency → next-day mood',
      description: 'High brain-dump volume often signals mental load or rumination — tests if the day after a high-dump day shows lower mood intensity.',
      input: {
        table: 'brain_dumps',
        column: 'id',
        aggregation: 'daily_count',
      },
      output: {
        table: 'emotional_snapshots',
        column: 'intensity',
        aggregation: 'daily_avg',
        transform: "CASE WHEN valence='negative' THEN -intensity ELSE intensity END",
      },
      lag: '1d',
      correlation_type: 'spearman',
      threshold: 0.3,
      min_n: 30,
      direction: 'negative',
    },
    {
      name: "Yesterday's HRV → today's task completion",
      description: 'Mirror of pattern #2 from the daily-rollup side; uses health_metrics.hrv_avg (22mo coverage) instead of realtime stream. Higher HRV → better executive function → more done.',
      input: {
        table: 'health_metrics',
        column: 'hrv_avg',
        aggregation: 'daily_first',
      },
      output: {
        table: 'tasks',
        column: 'id',
        aggregation: 'daily_count',
        filter: 'completed_at IS NOT NULL',
        output_date_col: 'completed_at',
      },
      lag: '0d',
      correlation_type: 'spearman',
      threshold: 0.3,
      min_n: 30,
    },
    {
      name: 'Daytime cognitive capacity → evening mood',
      description: "LucidBridge's cognitive_capacity is computed minute-by-minute. Tests if the daytime average predicts that evening's mood snapshot.",
      input: {
        table: 'realtime_health',
        column: 'cognitive_capacity',
        aggregation: 'window_avg',
        window: '08:00..18:00',
      },
      output: {
        table: 'emotional_snapshots',
        column: 'intensity',
        aggregation: 'evening_avg',
        transform: "CASE WHEN valence='negative' THEN -intensity ELSE intensity END",
      },
      lag: '0d',
      correlation_type: 'spearman',
      threshold: 0.3,
      min_n: 21,
    },
    {
      name: 'Caffeine intake → sleep efficiency tonight',
      description: "Did Fabi's caffeine days reduce sleep efficiency? Uses health_journal Y/N and health_metrics rollup.",
      input: {
        table: 'health_journal',
        column: 'answered_yes',
        aggregation: 'daily_first',
        filter: "question = 'Consumed caffeine?'",
      },
      output: {
        table: 'health_metrics',
        column: 'sleep_efficiency_pct',
        aggregation: 'daily_first',
      },
      lag: '0d',
      type: 't_test_two_sample',
      threshold: 0.05,
      effect_size_min: 0.3,
      min_n: 100,
      direction: 'negative',
    },
    {
      name: 'Alcohol intake → next-day HRV suppression',
      description: 'Alcohol is a well-documented HRV suppressant. Tests effect size on Fabi\'s WHOOP data.',
      input: {
        table: 'health_journal',
        column: 'answered_yes',
        aggregation: 'daily_first',
        filter: "question = 'Have any alcoholic drinks?'",
      },
      output: {
        table: 'health_metrics',
        column: 'hrv_avg',
        aggregation: 'daily_first',
      },
      lag: '1d',
      type: 't_test_two_sample',
      threshold: 0.05,
      effect_size_min: 0.4,
      min_n: 100,
      direction: 'negative',
    },
    {
      name: 'ADHD medication day → task completion volume',
      description: "Tests the obvious-but-worth-confirming hypothesis that medicated days produce more completed tasks. If the effect is small, that's data; if large, that's calibration.",
      input: {
        table: 'health_journal',
        column: 'answered_yes',
        aggregation: 'daily_first',
        filter: "question = 'Took AD(H)D medication?'",
      },
      output: {
        table: 'tasks',
        column: 'id',
        aggregation: 'daily_count',
        filter: 'completed_at IS NOT NULL',
        output_date_col: 'completed_at',
      },
      lag: '0d',
      type: 't_test_two_sample',
      threshold: 0.05,
      effect_size_min: 0.3,
      min_n: 60,
    },
    {
      name: 'Auto-discover (weekly brute force)',
      type: 'auto_discover',
      description: 'Compute pairwise correlations on all numeric daily aggregates from health_metrics + realtime_health (daily-resampled) + tasks (daily count) + brain_dumps (daily count) + emotional_snapshots (daily intensity*valence_sign) + health_journal Y/N variables. Sweep across lags [0d, 1d, 2d, 7d]. Surface top 5 with |r| > 0.5 and n >= 30 weekly. Apply Bonferroni correction across the full sweep before flagging significance.',
      schedule: 'weekly',
      threshold: 0.5,
      min_n: 30,
      lags: ['0d', '1d', '2d', '7d'],
      correction: 'bonferroni',
      surface_top_n: 5,
      exclude_already_registered: true,
      require_directional_consistency: true,
      deliver: 'insert_into_detected_patterns_table',
    },
  ],
}
