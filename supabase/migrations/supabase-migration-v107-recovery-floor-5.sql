-- migration v107_recovery_floor_5.sql
--
-- Soft floor recovery score at 5 instead of 0.
--
-- Problem: On the worst nights (alcohol, illness, deep burnout) v103's
-- contrast stretch crushes the raw score below 0, clamps to 0. The literal
-- "0" reads as "the app is broken" rather than "your body is wrecked" —
-- Fabi flagged this UX issue on the 2026-05-23 drunk night.
--
-- Fix: Replace the GREATEST(0, ...) clamp in both compute_recovery_score
-- paths with GREATEST(5, ...). Math unchanged for everything above 5.
-- The score range becomes 5-100 instead of 0-100. NULL (no data) cases
-- are unaffected because recompute_health_metrics writes NULL directly
-- without calling compute_recovery_score.
--
-- 5 reads as "rock bottom but functional"; 0 reads as a bug.

CREATE OR REPLACE FUNCTION public.compute_recovery_score(
  p_user_id uuid,
  p_hrv_avg numeric,
  p_resting_hr integer,
  p_sleep_score numeric
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  history_days int;
  hrv_pct numeric;
  rhr_pct_inv numeric;
  s_score numeric;
  baseline_hrv numeric := 64.4;
  hrv_sd       numeric := 12.0;
  median_rhr   numeric := 58;
  rhr_sd       numeric := 4.75;
  hrv_z numeric;
  rhr_z numeric;
  hrv_component numeric;
  rhr_component numeric;
  sleep_component numeric;
  total_weight numeric := 0;
  weighted_sum numeric := 0;
  raw numeric;
  stretch_k numeric := 1.4;
  score_floor numeric := 5;   -- v107: never display literal 0 for a real score
BEGIN
  SELECT COUNT(*) INTO history_days
  FROM health_metrics
  WHERE user_id = p_user_id
    AND hrv_avg IS NOT NULL AND hrv_avg > 0
    AND metric_date >= CURRENT_DATE - 30
    AND metric_date < CURRENT_DATE;

  -- Cold-start path: <7 days of usable history
  IF history_days < 7 THEN
    IF p_hrv_avg IS NOT NULL AND p_hrv_avg > 0 THEN
      hrv_z := (p_hrv_avg - baseline_hrv) / hrv_sd;
      hrv_component := sigmoid(hrv_z) * 100;
    ELSE
      hrv_component := 50;
    END IF;

    IF p_resting_hr IS NOT NULL AND p_resting_hr > 0 THEN
      rhr_z := (median_rhr - p_resting_hr) / rhr_sd;
      rhr_component := sigmoid(rhr_z) * 100;
    ELSE
      rhr_component := 50;
    END IF;

    sleep_component := COALESCE(p_sleep_score, 50);

    -- v107: floor at 5 (was 0)
    RETURN ROUND(LEAST(100, GREATEST(score_floor,
      hrv_component * 0.50 + rhr_component * 0.20 + sleep_component * 0.30
    )));
  END IF;

  -- Personal-percentile path (>=7 days history)
  IF p_hrv_avg IS NOT NULL AND p_hrv_avg > 0 THEN
    SELECT 100.0 * (
      COUNT(*) FILTER (WHERE hrv_avg < p_hrv_avg)::numeric +
      0.5 * COUNT(*) FILTER (WHERE hrv_avg = p_hrv_avg)::numeric
    ) / NULLIF(COUNT(*) FILTER (WHERE hrv_avg > 0), 0)
    INTO hrv_pct
    FROM health_metrics
    WHERE user_id = p_user_id
      AND hrv_avg IS NOT NULL AND hrv_avg > 0
      AND metric_date >= CURRENT_DATE - 30
      AND metric_date < CURRENT_DATE;
  ELSE
    hrv_pct := NULL;
  END IF;

  IF p_resting_hr IS NOT NULL AND p_resting_hr > 0 THEN
    SELECT 100.0 * (
      COUNT(*) FILTER (WHERE resting_hr > p_resting_hr)::numeric +
      0.5 * COUNT(*) FILTER (WHERE resting_hr = p_resting_hr)::numeric
    ) / NULLIF(COUNT(*) FILTER (WHERE resting_hr > 0), 0)
    INTO rhr_pct_inv
    FROM health_metrics
    WHERE user_id = p_user_id
      AND resting_hr IS NOT NULL AND resting_hr > 0
      AND metric_date >= CURRENT_DATE - 30
      AND metric_date < CURRENT_DATE;
  ELSE
    rhr_pct_inv := NULL;
  END IF;

  s_score := COALESCE(p_sleep_score, 50);

  IF hrv_pct IS NOT NULL THEN
    weighted_sum := weighted_sum + hrv_pct * 0.55;
    total_weight := total_weight + 0.55;
  END IF;
  IF rhr_pct_inv IS NOT NULL THEN
    weighted_sum := weighted_sum + rhr_pct_inv * 0.30;
    total_weight := total_weight + 0.30;
  END IF;
  weighted_sum := weighted_sum + s_score * 0.15;
  total_weight := total_weight + 0.15;

  IF total_weight = 0 THEN
    RETURN 50;
  END IF;

  raw := weighted_sum / total_weight;

  -- v107: floor at 5 (was 0)
  RETURN ROUND(LEAST(100, GREATEST(score_floor, 50 + (raw - 50) * stretch_k)));
END;
$function$;

-- End of v107.
