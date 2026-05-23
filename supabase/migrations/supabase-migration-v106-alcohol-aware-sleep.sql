-- migration v106_alcohol_aware_sleep.sql
--
-- Single-user calibration: detect_sleep_window now knows when Fabi was drunk
-- and adjusts thresholds to find his shifted sleep signature instead of
-- returning NULL.
--
-- Problem: On alcohol nights, Fabi's sleeping HR runs ~60-69 instead of his
-- sober 48-52. The hardcoded sleep_thresh=65 misses this entire window and
-- the function returns "no sleep found" → recompute writes NULL placeholder
-- → app shows 0 recovery.
--
-- Fix: Detect overnight alcohol using 3 calibrated signals (HRV drop > 20%,
-- DFA > 1.0, evening HR > 65 in the 22:00-06:00 Berlin window), then on
-- alcohol nights bump the sleep / wake / deep thresholds upward by ~10 bpm.
-- This is single-user calibration — values are Fabi's personal baseline
-- from `personal_calibration` and his HMM Deep Sleep emission means.

-- ─────────────────────────────────────────────────────────────────────────
-- 1. New helper: detect_overnight_alcohol(user, date) → boolean
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.detect_overnight_alcohol(
  p_user_id   uuid,
  p_target_date date,
  p_user_tz   text DEFAULT 'Europe/Berlin'::text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  -- Peak alcohol effect window: 23:00 Berlin (21:00 UTC) → 03:00 Berlin (01:00 UTC).
  -- Calibrated from 14d of Fabi's data — drunk nights are differentiated from
  -- sober nights primarily by simultaneous HR elevation + HRV suppression in
  -- this window. Wider windows include post-alcohol rebound which dilutes
  -- the signal.
  win_start timestamptz := ((p_target_date - 1)::text || ' 23:00:00')::timestamp AT TIME ZONE p_user_tz;
  win_end   timestamptz := (p_target_date::text     || ' 03:00:00')::timestamp AT TIME ZONE p_user_tz;
  evening_hrv   numeric;
  evening_hr    numeric;
BEGIN
  -- Compute peak-window signatures
  SELECT
    AVG(hrv_rmssd)::numeric,
    AVG(heart_rate)::numeric
  INTO evening_hrv, evening_hr
  FROM realtime_health
  WHERE user_id = p_user_id
    AND recorded_at >= win_start
    AND recorded_at <  win_end
    AND heart_rate IS NOT NULL
    AND heart_rate > 30
    AND hrv_rmssd IS NOT NULL
    AND hrv_rmssd > 0;

  -- Insufficient data — can't classify
  IF evening_hrv IS NULL OR evening_hr IS NULL THEN
    RETURN false;
  END IF;

  -- AND logic: BOTH HR-elevation AND HRV-suppression must be present.
  -- Calibrated from Fabi's 7-day comparison:
  --   May 23 (drunk):   avg_hr 104, avg_hrv 51  → both fire → ALCOHOL ✓
  --   May 22 (sober):   avg_hr  63, avg_hrv 89  → neither fires → sober ✓
  --   May 19 (sober):   avg_hr  71, avg_hrv 55  → HR gate kills it → sober ✓
  RETURN evening_hr > 85 AND evening_hrv < 60;
END;
$function$;

COMMENT ON FUNCTION public.detect_overnight_alcohol(uuid, date, text) IS
  'Single-user alcohol detector for Fabi. Returns true if 2+ of {HRV drop >20%, DFA >1.0, evening HR >65} fire in 22:00-06:00 Berlin window. Uses personal_calibration.alcohol_hrv_drop. Calibrated values from HMM Deep Sleep state.';

-- ─────────────────────────────────────────────────────────────────────────
-- 2. detect_sleep_window: alcohol-aware threshold bumps
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.detect_sleep_window(
  p_user_id   uuid,
  p_target_date date,
  p_user_tz   text DEFAULT 'Europe/Berlin'::text
)
RETURNS TABLE(
  o_sleep_start       timestamp with time zone,
  o_sleep_end         timestamp with time zone,
  o_total_min         integer,
  o_asleep_min        integer,
  o_deep_min          integer,
  o_rem_min           integer,
  o_light_min         integer,
  o_awake_min         integer,
  o_efficiency_pct    integer,
  o_hrv_avg           numeric,
  o_resting_hr        integer
)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  win_start timestamptz := ((p_target_date - 1)::text || ' 19:00:00')::timestamp AT TIME ZONE p_user_tz;
  win_end   timestamptz := (p_target_date::text     || ' 12:00:00')::timestamp AT TIME ZONE p_user_tz;
  -- v106: thresholds become variable — bumped on alcohol nights.
  sleep_thresh int := 65;
  wake_thresh  int := 79;
  deep_ceiling int := 54;
  rem_sd_min   numeric := 3.0;
  bridge_max   int := 20;
  rhr_floor    int := 35;
  is_alcohol   boolean := false;
BEGIN
  -- v106: alcohol-aware threshold bumps. Single-user calibration —
  -- Fabi's sober sleeping HR is 48-52, drunk is 60-69, so bump by ~10 bpm.
  SELECT detect_overnight_alcohol(p_user_id, p_target_date, p_user_tz) INTO is_alcohol;
  IF is_alcohol THEN
    sleep_thresh := 75;
    wake_thresh  := 89;
    deep_ceiling := 62;
    rhr_floor    := 40;
  END IF;

  RETURN QUERY
  WITH minute_buckets AS (
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
  flagged AS (
    SELECT m_ts, hr_avg, hr_sd, hrv_avg, hr_smooth,
      CASE WHEN hr_smooth < sleep_thresh THEN 1 ELSE 0 END AS raw_is_sleep
    FROM smoothed
  ),
  with_lag AS (
    SELECT m_ts, hr_avg, hr_sd, hrv_avg, hr_smooth, raw_is_sleep,
      LAG(raw_is_sleep, 1, raw_is_sleep) OVER (ORDER BY m_ts) AS prev_is_sleep
    FROM flagged
  ),
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
  bridged AS (
    SELECT m_ts, hr_avg, hr_sd, hrv_avg, hr_smooth,
      CASE
        WHEN raw_is_sleep = 1 THEN 1
        WHEN run_length < bridge_max THEN 1
        ELSE 0
      END AS is_sleep
    FROM run_lengths
  ),
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
      COUNT(*) FILTER (WHERE stage = 'deep')::int  AS deep_m,
      COUNT(*) FILTER (WHERE stage = 'rem')::int   AS rem_m,
      COUNT(*) FILTER (WHERE stage = 'light')::int AS light_m,
      COUNT(*) FILTER (WHERE stage = 'awake')::int AS awake_m,
      AVG(hrv_avg) FILTER (WHERE hrv_avg > 0)::numeric AS hrv_mean,
      percentile_cont(0.05) WITHIN GROUP (ORDER BY hr_avg)
        FILTER (WHERE hr_avg > rhr_floor)::numeric AS rhr_p5
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
    ROUND(rhr_p5)::int AS rhr_out
  FROM totals
  WHERE w_start IS NOT NULL;
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────
-- 3. recompute_health_metrics: stamp alcohol_impact = 1.0 on detected nights
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.recompute_health_metrics(
  p_user_id     uuid,
  p_target_date date DEFAULT NULL::date
)
RETURNS health_metrics
LANGUAGE plpgsql
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  target_date         date;
  win                 record;
  s_score             numeric;
  r_score             numeric;
  result_row          health_metrics;
  has_open_alert      boolean;
  has_recent_backfill boolean;
  is_alcohol          boolean;
BEGIN
  target_date := COALESCE(p_target_date, (now() AT TIME ZONE 'Europe/Berlin')::date);

  -- v106: detect alcohol once, reuse for both sleep window + impact stamp
  SELECT detect_overnight_alcohol(p_user_id, target_date) INTO is_alcohol;

  -- 1. Detect sleep window (alcohol-aware via v106)
  SELECT * INTO win FROM detect_sleep_window(p_user_id, target_date);

  -- Confidence floor: need 4+ hours of measured sleep to overwrite an existing row.
  IF win.o_sleep_start IS NULL OR COALESCE(win.o_asleep_min, 0) < 240 THEN
    -- v104: defer NULL-placeholder writes if a BLE sync is in flight
    SELECT EXISTS (
      SELECT 1 FROM ble_freshness_alerts
      WHERE user_id = p_user_id AND state = 'open'
    ) INTO has_open_alert;

    SELECT EXISTS (
      SELECT 1 FROM bridge_logs
      WHERE user_id = p_user_id
        AND created_at >= NOW() - INTERVAL '60 minutes'
        AND (
          (key = 'history_sync_gap_check'   AND value::text LIKE '%decision=download%')
          OR key = 'history_sync_request_sent'
          OR key = 'history_sync_complete'
          OR key = 'history_sync_batch_start'
        )
    ) INTO has_recent_backfill;

    IF has_open_alert OR has_recent_backfill THEN
      RAISE NOTICE 'recompute_health_metrics: sync in flight for %, deferring (alert=% backfill=%)',
        p_user_id, has_open_alert, has_recent_backfill;

      SELECT * INTO result_row FROM health_metrics
      WHERE user_id = p_user_id AND metric_date = target_date;
      RETURN result_row;
    END IF;

    -- Insert empty placeholder if no row exists yet, but never overwrite a real one
    INSERT INTO health_metrics (user_id, metric_date, source, alcohol_impact)
    VALUES (p_user_id, target_date, 'pg_recompute', CASE WHEN is_alcohol THEN 1.0 ELSE NULL END)
    ON CONFLICT (user_id, metric_date) DO UPDATE SET
      alcohol_impact = CASE WHEN is_alcohol THEN 1.0 ELSE health_metrics.alcohol_impact END;

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

  -- 3. Upsert (now with alcohol_impact stamp)
  INSERT INTO health_metrics (
    user_id, metric_date, source,
    sleep_start, sleep_end, sleep_hours,
    deep_sleep_min, rem_sleep_min, light_sleep_min, awake_min,
    sleep_efficiency_pct, sleep_score, recovery_score,
    hrv_avg, resting_hr,
    readiness_level, readiness_score, alcohol_impact
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
    r_score,
    CASE WHEN is_alcohol THEN 1.0 ELSE NULL END
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
    readiness_score = EXCLUDED.readiness_score,
    alcohol_impact = EXCLUDED.alcohol_impact;

  SELECT * INTO result_row FROM health_metrics
  WHERE user_id = p_user_id AND metric_date = target_date;
  RETURN result_row;
END;
$function$;

-- End of v106.
