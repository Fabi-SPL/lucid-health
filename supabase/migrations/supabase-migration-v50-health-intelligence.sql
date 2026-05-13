-- ============================================================
-- v50: Health Intelligence v2 — new HRV metrics + computed scores
-- Adds SDNN, pNN50, DFA α1, cognitive capacity, illness sentinel,
-- and training load intelligence to both realtime and daily tables.
-- ============================================================

-- ── 1. Realtime readings: new HRV metrics ──────────────────
ALTER TABLE realtime_health
  ADD COLUMN IF NOT EXISTS sdnn NUMERIC,
  ADD COLUMN IF NOT EXISTS pnn50 NUMERIC,
  ADD COLUMN IF NOT EXISTS dfa_alpha1 NUMERIC,
  ADD COLUMN IF NOT EXISTS cognitive_capacity NUMERIC,
  ADD COLUMN IF NOT EXISTS cognitive_label TEXT,
  ADD COLUMN IF NOT EXISTS illness_risk SMALLINT DEFAULT 0;

COMMENT ON COLUMN realtime_health.sdnn IS 'Standard Deviation of NN intervals (ms) — overall autonomic function';
COMMENT ON COLUMN realtime_health.pnn50 IS 'Percentage of successive RR intervals >50ms apart (%) — parasympathetic';
COMMENT ON COLUMN realtime_health.dfa_alpha1 IS 'Detrended Fluctuation Analysis α1 — fractal correlation (1.0=healthy)';
COMMENT ON COLUMN realtime_health.cognitive_capacity IS 'Cognitive Capacity v2 score (0-100)';
COMMENT ON COLUMN realtime_health.cognitive_label IS 'Full / Reduced / Low';
COMMENT ON COLUMN realtime_health.illness_risk IS '0-3 illness sentinel signals flagged';

-- ── 2. Daily health_metrics: intelligence columns ──────────
ALTER TABLE health_metrics
  ADD COLUMN IF NOT EXISTS sdnn_avg NUMERIC,
  ADD COLUMN IF NOT EXISTS pnn50_avg NUMERIC,
  ADD COLUMN IF NOT EXISTS dfa_alpha1_avg NUMERIC,
  ADD COLUMN IF NOT EXISTS cognitive_capacity_score NUMERIC,
  ADD COLUMN IF NOT EXISTS cognitive_label TEXT,
  ADD COLUMN IF NOT EXISTS illness_risk SMALLINT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS illness_alert TEXT,
  ADD COLUMN IF NOT EXISTS training_monotony NUMERIC,
  ADD COLUMN IF NOT EXISTS training_strain NUMERIC,
  ADD COLUMN IF NOT EXISTS acwr NUMERIC,
  ADD COLUMN IF NOT EXISTS body_battery NUMERIC;

COMMENT ON COLUMN health_metrics.sdnn_avg IS 'Daily average SDNN (ms)';
COMMENT ON COLUMN health_metrics.pnn50_avg IS 'Daily average pNN50 (%)';
COMMENT ON COLUMN health_metrics.dfa_alpha1_avg IS 'Daily average DFA α1';
COMMENT ON COLUMN health_metrics.cognitive_capacity_score IS 'Morning cognitive capacity (0-100)';
COMMENT ON COLUMN health_metrics.cognitive_label IS 'Full / Reduced / Low';
COMMENT ON COLUMN health_metrics.illness_risk IS '0-3 z-score signals flagged';
COMMENT ON COLUMN health_metrics.illness_alert IS 'Illness sentinel message if triggered';
COMMENT ON COLUMN health_metrics.training_monotony IS 'Foster training monotony (mean/SD, >2.0=risk)';
COMMENT ON COLUMN health_metrics.training_strain IS 'Foster training strain (sum × monotony)';
COMMENT ON COLUMN health_metrics.acwr IS 'Acute:Chronic Workload Ratio (0.8-1.3=optimal)';
COMMENT ON COLUMN health_metrics.body_battery IS 'Body battery at end of day (0-100)';
