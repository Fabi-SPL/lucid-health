-- v102 — Personal-percentile recovery formula
-- Replaces the v100 sigmoid/z-score formula.
--
-- WHY: v100 weights summed to 90% (HRV 40 + RHR 25 + Sleep 25 = 90, leaving
-- 10% for a never-implemented strain_modifier). Max possible score was 90,
-- which is why Fabi never saw recovery >89 in 60+ days of data.
-- Additionally, sigmoid(z=0) = 0.5 forced baseline-HRV days into a narrow
-- 50-60 band, suppressing the felt dynamic range.
--
-- WHAT v102 does:
--   recovery = hrv_pct_30d  * 0.50    -- percentile rank of today's HRV vs last 30d
--            + rhr_pct_inv  * 0.20    -- inverted RHR percentile (lower RHR = better)
--            + sleep_score  * 0.30    -- existing sleep score
--   weights sum to 100, range is 0-100, every score reflects YOUR distribution.
--
-- FALLBACKS:
--   - <7 days of history: degrade to the v100 sigmoid (preserves cold-start UX)
--   - HRV missing: re-normalizes weights so signal isn't silently dropped
--   - RHR missing: same

CREATE OR REPLACE FUNCTION public.compute_recovery_score(
  p_user_id uuid,
  p_hrv_avg numeric,
  p_resting_hr integer,
  p_sleep_score numeric
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
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

    RETURN ROUND(LEAST(100, GREATEST(0,
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

  -- Combine with auto-renormalizing weights
  IF hrv_pct IS NOT NULL THEN
    weighted_sum := weighted_sum + hrv_pct * 0.50;
    total_weight := total_weight + 0.50;
  END IF;
  IF rhr_pct_inv IS NOT NULL THEN
    weighted_sum := weighted_sum + rhr_pct_inv * 0.20;
    total_weight := total_weight + 0.20;
  END IF;
  weighted_sum := weighted_sum + s_score * 0.30;
  total_weight := total_weight + 0.30;

  IF total_weight = 0 THEN
    RETURN 50;
  END IF;

  RETURN ROUND(LEAST(100, GREATEST(0, weighted_sum / total_weight)));
END;
$function$;

COMMENT ON FUNCTION public.compute_recovery_score IS
'v102 (2026-05-13). Personal-percentile recovery score. HRV percentile (50%) + RHR percentile inverted (20%) + sleep score (30%). Falls back to z-score sigmoid if <7 days history. Replaces v100 which had broken weight summing (max 90) and sigmoid compression near baseline.';
