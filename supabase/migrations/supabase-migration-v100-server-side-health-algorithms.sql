-- v100: Server-side health algorithms — port HRV/recovery/sleep score from Swift to Postgres
--
-- Eliminates the iOS↔server distributed-state class of bugs (upsert race,
-- cache override, freshness flag). iOS becomes a thin bridge: streams
-- realtime_health rows, reads health_metrics, never writes
-- recovery_score / sleep_score / stage breakdowns.
--
-- Single entry point: recompute_health_metrics(user_id, target_date)
-- - Called by iOS "I'm awake" button via PostgREST RPC
-- - Called by pg_cron at 05:00 UTC daily for "yesterday"
-- - Idempotent — ON CONFLICT DO UPDATE, can be re-run any number of times
--
-- Design choices (from research 2026-05-10):
-- - Sleep window detected from HR (smoothed P5 minute) — robust to iOS
--   sleep_stage gaps, matches the Whoop-style approach
-- - Stage classification HR-only — REM detected via HR variability, deep via
--   sustained low HR + low SD, awake via HR > floored wake threshold
-- - Recovery: sigmoid(z-score) on HRV (40%) + RHR (25%) + sleep score (25%)
--   + strain modifier (placeholder 0% for now)
-- - Sleep score: duration (35%) + efficiency (25%) + stage balance (20%) +
--   consistency (20%, placeholder 50)
-- - Calibration constants embedded for Fabi (single user). Future: per-user
--   user_calibration table.

-- ─── Cleanup: drop dead trigger pointing at abandoned cloud Supabase ────────
-- The pre-existing health_engine_data_trigger POSTs to vqvnokerqumgpimtsrdj
-- (the abandoned hosted instance) which is dead. Has been firing on every
-- realtime_health insert and silently failing. Removing it eliminates the
-- distributed-state writer; pg_cron + RPC are the new authoritative writers.

DROP TRIGGER IF EXISTS health_engine_data_trigger ON realtime_health;

-- ─── Extend source CHECK to allow 'pg_recompute' ────────────────────────────

ALTER TABLE health_metrics DROP CONSTRAINT IF EXISTS health_metrics_source_check;
ALTER TABLE health_metrics ADD CONSTRAINT health_metrics_source_check
  CHECK (source = ANY (ARRAY[
    'whoop_backfill'::text, 'whoop_csv'::text, 'apple_health'::text,
    'ble_live'::text, 'daily_shortcut'::text, 'health_engine'::text,
    'manual'::text, 'pg_recompute'::text
  ]));

-- ─── Helper: sigmoid ─────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION sigmoid(z numeric)
RETURNS numeric LANGUAGE sql IMMUTABLE AS $$
  SELECT 1.0 / (1.0 + exp(-z))
$$;

-- ─── Sleep window detection from realtime_health HR data ────────────────────

-- Drop first because we changed OUT parameter names (Postgres rejects OR REPLACE on type changes)
DROP FUNCTION IF EXISTS detect_sleep_window(uuid, date, text);

CREATE OR REPLACE FUNCTION detect_sleep_window(
  p_user_id    uuid,
  p_target_date date,
  p_user_tz    text DEFAULT 'Europe/Berlin'
)
RETURNS TABLE(
  o_sleep_start    timestamptz,
  o_sleep_end      timestamptz,
  o_total_min      int,
  o_asleep_min     int,
  o_deep_min       int,
  o_rem_min        int,
  o_light_min      int,
  o_awake_min      int,
  o_efficiency_pct int,
  o_hrv_avg        numeric,
  o_resting_hr     int
)
LANGUAGE plpgsql STABLE AS $$
DECLARE
  -- Window: 19:00 prev day → 12:00 target day in user's TZ
  win_start timestamptz := ((p_target_date - 1)::text || ' 19:00:00')::timestamp AT TIME ZONE p_user_tz;
  win_end   timestamptz := (p_target_date::text     || ' 12:00:00')::timestamp AT TIME ZONE p_user_tz;
  -- Calibration (Fabi)
  sleep_thresh int := 65;
  wake_thresh  int := 79;   -- baselineRHR(54) + 25 floor (matches v98 SleepEngine)
  deep_ceiling int := 54;
  rem_sd_min   numeric := 3.0;
  bridge_max   int := 20;   -- gaps shorter than this are bridged into the sleep island
BEGIN
  RETURN QUERY
  WITH minute_buckets AS (
    -- Per-minute averages of HR, smoothed via 5-min rolling
    SELECT
      date_trunc('minute', recorded_at) AS m_ts,
      AVG(heart_rate)::numeric AS hr_avg,
      stddev_samp(heart_rate)::numeric AS hr_sd,
      AVG(hrv_rmssd)::numeric AS hrv_avg
    FROM realtime_health
    WHERE user_id = p_user_id
      AND recorded_at >= win_start
      AND recorded_at <  win_end
      AND heart_rate IS NOT NULL
      AND heart_rate > 30
    GROUP BY date_trunc('minute', recorded_at)
  ),
  smoothed AS (
    SELECT m_ts, hr_avg, COALESCE(hr_sd, 0) AS hr_sd, hrv_avg,
      AVG(hr_avg) OVER (ORDER BY m_ts ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) AS hr_smooth
    FROM minute_buckets
  ),
  -- Step 1 — flag minutes where smoothed HR is below sleep threshold
  flagged AS (
    SELECT m_ts, hr_avg, hr_sd, hrv_avg, hr_smooth,
      CASE WHEN hr_smooth < sleep_thresh THEN 1 ELSE 0 END AS raw_is_sleep
    FROM smoothed
  ),
  -- Step 2a — get the prev row's value (LAG must live in its own CTE — Postgres bans nested window funcs)
  with_lag AS (
    SELECT m_ts, hr_avg, hr_sd, hrv_avg, hr_smooth, raw_is_sleep,
      LAG(raw_is_sleep, 1, raw_is_sleep) OVER (ORDER BY m_ts) AS prev_is_sleep
    FROM flagged
  ),
  -- Step 2b — assign run IDs to consecutive same-state runs (Whoop-style gaps-and-islands)
  runs AS (
    SELECT m_ts, hr_avg, hr_sd, hrv_avg, hr_smooth, raw_is_sleep,
      SUM(CASE WHEN raw_is_sleep != prev_is_sleep THEN 1 ELSE 0 END)
        OVER (ORDER BY m_ts) AS run_id
    FROM with_lag
  ),
  run_lengths AS (
    SELECT m_ts, hr_avg, hr_sd, hrv_avg, hr_smooth, raw_is_sleep, run_id,
      COUNT(*) OVER (PARTITION BY run_id) AS run_length
    FROM runs
  ),
  -- Step 3 — bridge: short awake-runs (< bridge_max minutes) inside the sleep block stay as sleep
  bridged AS (
    SELECT m_ts, hr_avg, hr_sd, hrv_avg, hr_smooth,
      CASE
        WHEN raw_is_sleep = 1 THEN 1
        WHEN run_length < bridge_max THEN 1   -- short blip, still asleep
        ELSE 0
      END AS is_sleep
    FROM run_lengths
  ),
  -- Step 4 — re-assign island IDs on bridged signal
  islands AS (
    SELECT m_ts, hr_avg, hr_sd, hrv_avg, hr_smooth, is_sleep,
      SUM(CASE WHEN is_sleep = 0 THEN 1 ELSE 0 END)
        OVER (ORDER BY m_ts) AS gap_id
    FROM bridged
  ),
  sleep_islands AS (
    SELECT m_ts, hr_avg, hr_sd, hrv_avg, hr_smooth,
      gap_id - 1 AS island_id
    FROM islands
    WHERE is_sleep = 1
  ),
  longest_island AS (
    SELECT island_id
    FROM sleep_islands
    GROUP BY island_id
    ORDER BY COUNT(*) DESC
    LIMIT 1
  ),
  sleep_minutes AS (
    SELECT s.m_ts, s.hr_avg, s.hr_sd, s.hrv_avg, s.hr_smooth
    FROM sleep_islands s
    JOIN longest_island li ON s.island_id = li.island_id
  ),
  classified AS (
    SELECT m_ts, hr_avg, hr_sd, hrv_avg, hr_smooth,
      CASE
        WHEN hr_smooth > wake_thresh THEN 'awake'
        WHEN hr_smooth < deep_ceiling AND hr_sd < 3 THEN 'deep'
        WHEN hr_sd > rem_sd_min THEN 'rem'
        ELSE 'light'
      END AS stage
    FROM sleep_minutes
  ),
  totals AS (
    SELECT
      MIN(m_ts) AS w_start,
      MAX(m_ts) + interval '1 minute' AS w_end,
      COUNT(*) FILTER (WHERE stage = 'deep')::int AS deep_m,
      COUNT(*) FILTER (WHERE stage = 'rem')::int  AS rem_m,
      COUNT(*) FILTER (WHERE stage = 'light')::int AS light_m,
      COUNT(*) FILTER (WHERE stage = 'awake')::int AS awake_m,
      AVG(hrv_avg) FILTER (WHERE hrv_avg > 0)::numeric AS hrv_mean,
      MIN(hr_avg)::int AS min_hr
    FROM classified
  )
  SELECT
    w_start,
    w_end,
    EXTRACT(epoch FROM (w_end - w_start))::int / 60 AS total_min,
    (deep_m + rem_m + light_m) AS asleep_min,
    deep_m, rem_m, light_m, awake_m,
    CASE WHEN (deep_m + rem_m + light_m + awake_m) > 0
         THEN ROUND(((deep_m + rem_m + light_m)::numeric / (deep_m + rem_m + light_m + awake_m)) * 100)::int
         ELSE 0 END AS eff_pct,
    ROUND(hrv_mean, 1) AS hrv_avg_out,
    min_hr
  FROM totals
  WHERE w_start IS NOT NULL;
END;
$$;

-- ─── Sleep score (0-100) ─────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION compute_sleep_score(
  p_total_minutes  int,
  p_asleep_minutes int,
  p_deep_min       int,
  p_rem_min        int,
  p_efficiency_pct int
)
RETURNS numeric LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  -- Calibration weights (matches PersonalCalibration defaults)
  w_duration   numeric := 0.35;
  w_efficiency numeric := 0.25;
  w_stage      numeric := 0.20;
  w_consistency numeric := 0.20;
  duration_hours numeric;
  duration_score numeric;
  efficiency_score numeric;
  deep_pct numeric;
  rem_pct numeric;
  deep_score numeric;
  rem_score numeric;
  stage_score numeric;
  consistency_score numeric := 50;  -- placeholder (no bedtime history yet in PG)
  total_score numeric;
BEGIN
  IF p_asleep_minutes IS NULL OR p_asleep_minutes = 0 THEN RETURN 0; END IF;

  duration_hours := p_asleep_minutes / 60.0;

  -- 1. Duration tier
  IF duration_hours BETWEEN 7 AND 9 THEN
    duration_score := 100;
  ELSIF duration_hours >= 6 THEN
    duration_score := 70 + (duration_hours - 6) * 30;
  ELSIF duration_hours >= 5 THEN
    duration_score := 40 + (duration_hours - 5) * 30;
  ELSE
    duration_score := GREATEST(duration_hours / 5.0 * 40, 0);
  END IF;

  -- 2. Efficiency tier
  IF p_efficiency_pct >= 90 THEN
    efficiency_score := 100;
  ELSIF p_efficiency_pct >= 80 THEN
    efficiency_score := 70 + (p_efficiency_pct - 80) * 3;
  ELSE
    efficiency_score := GREATEST(p_efficiency_pct / 80.0 * 70, 0);
  END IF;

  -- 3. Stage balance: deep target 18-30%, REM target 20-32%
  deep_pct := (p_deep_min::numeric / p_asleep_minutes) * 100;
  rem_pct  := (p_rem_min::numeric  / p_asleep_minutes) * 100;
  deep_score := CASE WHEN deep_pct BETWEEN 18 AND 30 THEN 100
                     ELSE GREATEST(0, 100 - ABS(deep_pct - 23) * 5) END;
  rem_score  := CASE WHEN rem_pct  BETWEEN 20 AND 32 THEN 100
                     ELSE GREATEST(0, 100 - ABS(rem_pct - 26) * 5) END;
  stage_score := (deep_score + rem_score) / 2.0;

  total_score := duration_score   * w_duration
               + efficiency_score * w_efficiency
               + stage_score      * w_stage
               + consistency_score * w_consistency;

  RETURN ROUND(LEAST(100, GREATEST(0, total_score)));
END;
$$;

-- ─── Recovery score (0-100, Whoop-style) ─────────────────────────────────────

CREATE OR REPLACE FUNCTION compute_recovery_score(
  p_user_id    uuid,
  p_hrv_avg    numeric,
  p_resting_hr int,
  p_sleep_score numeric
)
RETURNS numeric LANGUAGE plpgsql STABLE AS $$
DECLARE
  -- Calibration (Fabi). Future: lift to user_calibration table.
  baseline_hrv numeric := 64.4;
  hrv_sd       numeric := 12.0;     -- ~0.18 * baseline; will refine when we have 30d on-server
  median_rhr   numeric := 58;
  rhr_sd       numeric;
  hrv_z        numeric;
  rhr_z        numeric;
  hrv_component numeric;
  rhr_component numeric;
  sleep_component numeric;
  strain_modifier numeric := 0;     -- placeholder; will add when strain history is migrated
BEGIN
  -- Compute on-the-fly baseline from last 30 days of health_metrics if available
  SELECT AVG(hrv_avg), GREATEST(stddev_samp(hrv_avg), 5)
  INTO baseline_hrv, hrv_sd
  FROM (
    SELECT hrv_avg FROM health_metrics
    WHERE user_id = p_user_id
      AND hrv_avg IS NOT NULL AND hrv_avg > 0
      AND metric_date >= CURRENT_DATE - 30
    ORDER BY metric_date DESC
    LIMIT 30
  ) t;

  -- Fall back to Fabi defaults if no history
  IF baseline_hrv IS NULL THEN
    baseline_hrv := 64.4;
    hrv_sd := 12.0;
  END IF;

  -- RHR SD from p5/p95
  rhr_sd := GREATEST((71 - 52) / 4.0, 3);  -- ≈4.75

  -- HRV component (40%) — sigmoid of z-score
  IF p_hrv_avg IS NOT NULL AND p_hrv_avg > 0 THEN
    hrv_z := (p_hrv_avg - baseline_hrv) / hrv_sd;
    hrv_component := sigmoid(hrv_z) * 100 * 0.40;
  ELSE
    hrv_component := 50 * 0.40;  -- neutral if missing
  END IF;

  -- RHR component (25%) — lower RHR is better, hence (median - rhr)
  IF p_resting_hr IS NOT NULL AND p_resting_hr > 0 THEN
    rhr_z := (median_rhr - p_resting_hr) / rhr_sd;
    rhr_component := sigmoid(rhr_z) * 100 * 0.25;
  ELSE
    rhr_component := 50 * 0.25;
  END IF;

  -- Sleep component (25%)
  sleep_component := COALESCE(p_sleep_score, 50) * 0.25;

  RETURN ROUND(LEAST(100, GREATEST(0,
    hrv_component + rhr_component + sleep_component + strain_modifier
  )));
END;
$$;

-- ─── Single iOS-callable RPC ─────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION recompute_health_metrics(
  p_user_id uuid,
  p_target_date date DEFAULT NULL
)
RETURNS health_metrics LANGUAGE plpgsql AS $$
DECLARE
  target_date date;
  win record;
  s_score numeric;
  r_score numeric;
  result_row health_metrics;
BEGIN
  target_date := COALESCE(p_target_date, (now() AT TIME ZONE 'Europe/Berlin')::date);

  -- 1. Detect sleep window + stages from realtime_health
  SELECT * INTO win FROM detect_sleep_window(p_user_id, target_date);

  -- Confidence floor: need 4+ hours of measured sleep to overwrite an existing row.
  -- Below that, our recompute is likely a phone-died gap (or off-wrist) and the
  -- existing row (from whoop_csv / apple_health backfill) is probably more accurate.
  IF win.o_sleep_start IS NULL OR COALESCE(win.o_asleep_min, 0) < 240 THEN
    -- Insert empty placeholder if no row exists yet, but never overwrite a real one
    INSERT INTO health_metrics (user_id, metric_date, source)
    VALUES (p_user_id, target_date, 'pg_recompute')
    ON CONFLICT (user_id, metric_date) DO NOTHING;

    SELECT * INTO result_row FROM health_metrics
    WHERE user_id = p_user_id AND metric_date = target_date;
    RETURN result_row;
  END IF;

  -- 2. Compute scores
  s_score := compute_sleep_score(
    win.o_total_min, win.o_asleep_min, win.o_deep_min, win.o_rem_min, win.o_efficiency_pct
  );
  r_score := compute_recovery_score(
    p_user_id, win.o_hrv_avg, win.o_resting_hr, s_score
  );

  -- 3. Upsert
  INSERT INTO health_metrics (
    user_id, metric_date, source,
    sleep_start, sleep_end, sleep_hours,
    deep_sleep_min, rem_sleep_min, light_sleep_min, awake_min,
    sleep_efficiency_pct, sleep_score, recovery_score,
    hrv_avg, resting_hr,
    readiness_level, readiness_score
  )
  VALUES (
    p_user_id, target_date, 'pg_recompute',
    win.o_sleep_start, win.o_sleep_end,
    ROUND(win.o_asleep_min / 60.0, 1),
    win.o_deep_min, win.o_rem_min, win.o_light_min, win.o_awake_min,
    win.o_efficiency_pct, s_score, r_score,
    win.o_hrv_avg, win.o_resting_hr,
    CASE WHEN r_score >= 67 THEN 'green'
         WHEN r_score >= 34 THEN 'yellow'
         ELSE 'red' END,
    r_score
  )
  ON CONFLICT (user_id, metric_date) DO UPDATE SET
    source = 'pg_recompute',
    sleep_start = EXCLUDED.sleep_start,
    sleep_end = EXCLUDED.sleep_end,
    sleep_hours = EXCLUDED.sleep_hours,
    deep_sleep_min = EXCLUDED.deep_sleep_min,
    rem_sleep_min = EXCLUDED.rem_sleep_min,
    light_sleep_min = EXCLUDED.light_sleep_min,
    awake_min = EXCLUDED.awake_min,
    sleep_efficiency_pct = EXCLUDED.sleep_efficiency_pct,
    sleep_score = EXCLUDED.sleep_score,
    recovery_score = EXCLUDED.recovery_score,
    hrv_avg = EXCLUDED.hrv_avg,
    resting_hr = EXCLUDED.resting_hr,
    readiness_level = EXCLUDED.readiness_level,
    readiness_score = EXCLUDED.readiness_score;

  SELECT * INTO result_row FROM health_metrics
  WHERE user_id = p_user_id AND metric_date = target_date;
  RETURN result_row;
END;
$$;

-- ─── Schedule pg_cron daily at 05:00 UTC (≈07:00 Berlin in summer) ───────────

-- Ensure pg_cron extension is loaded (no-op if already)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Unschedule any existing job with same name (idempotent migration)
SELECT cron.unschedule(jobid)
FROM cron.job WHERE jobname = 'daily-health-metrics-recompute';

-- Schedule for Fabi (single-user). When we add more users, this becomes a loop
-- over a `users_for_pg_cron` view or per-user schedule rows.
SELECT cron.schedule(
  'daily-health-metrics-recompute',
  '0 5 * * *',
  $cron$
    SELECT recompute_health_metrics(
      'YOUR_USER_ID_HERE'::uuid,
      ((now() AT TIME ZONE 'Europe/Berlin')::date - 1)
    );
  $cron$
);

-- ─── Comments ────────────────────────────────────────────────────────────────

COMMENT ON FUNCTION recompute_health_metrics IS
  'Idempotent server-side recompute of daily health metrics from realtime_health.
   Called by iOS "I''m awake" button (PostgREST RPC) and by pg_cron at 05:00 UTC daily.
   Eliminates iOS-vs-server distributed-state bugs by being the single writer to
   health_metrics for sleep/recovery columns.';

COMMENT ON FUNCTION detect_sleep_window IS
  'HR-only sleep window detection. Returns NULL row if no window found
   (insufficient data, off-wrist night). Window: 19:00 prev → 12:00 target in user TZ.';
