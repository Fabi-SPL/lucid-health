-- migration v105_rhr_percentile.sql
--
-- Robust resting-HR calculation. Replaces MIN(hr_avg) with 5th percentile
-- of hr_avg over the detected sleep window.
--
-- Problem: A single off-wrist or contact-loss minute during the sleep window
-- could drive hr_avg for that minute well below the real sleeping HR (saw 38
-- on 2026-05-22 — strap clearly loose around wake-up), polluting RHR and
-- inflating the recovery score to 100 against subjective "feel tired".
--
-- Fix:
--   1. Discard minute buckets where hr_avg <= 35 (biologically implausible
--      for Fabi — baseline ~50, never <40 in genuine sleep readings).
--   2. Use percentile_cont(0.05) instead of MIN — robust to a few outliers,
--      still captures the bottom-of-sleep HR (matches Whoop's "lowest
--      sustained sleeping HR" definition).
--
-- Everything else in detect_sleep_window is byte-identical to the v104-era
-- function. Same input, same output columns, same search_path pin.

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
  sleep_thresh int := 65;
  wake_thresh  int := 79;
  deep_ceiling int := 54;
  rem_sd_min   numeric := 3.0;
  bridge_max   int := 20;
  rhr_floor    int := 35;   -- v105: biologically-plausible floor for Fabi
BEGIN
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
      -- v105: 5th-percentile of plausible minute-avgs over sleep window
      -- (was: MIN(hr_avg) — vulnerable to single off-wrist minute).
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

-- End of v105.
