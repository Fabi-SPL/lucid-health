-- v103 — Felt-range recovery
-- Refines the v102 personal-percentile formula. Replaces v102.
--
-- WHY v102 still felt "stuck 55-61" for a stable body:
--   v102 = hrv_pct*0.50 + rhr_pct_inv*0.20 + sleep_score*0.30
--   The sleep term was the ABSOLUTE sleep score. For someone who almost
--   always sleeps well (sleep_score pinned 90-100), that 0.30 weight was a
--   near-constant ~+28 floor — a third of the score never moved. Combined
--   with low day-to-day HRV/RHR variance, the output clamped to a narrow
--   mid-band. v102 fixed v100's "max 90" bug but not the felt range.
--
-- WHAT v103 changes (personal-percentile path only; >=7d history):
--   1. The frozen 30% wasn't bad because sleep was HIGH — it was bad because
--      it was a near-constant eating 30% of the weight with ~zero variance,
--      starving the signals that actually move. So: keep sleep ABSOLUTE
--      (a consistently good sleeper keeps the credit) but drop its weight to
--      0.15 — enough that a genuinely bad night still drags, small enough
--      that day-to-day swing comes from HRV/RHR.
--   2. Reweight onto what varies: HRV 0.55 · RHR 0.30 · sleep 0.15 (sum 1.0).
--      HRV/RHR are personal percentiles (span 0-100 by construction).
--   3. Contrast stretch around the midpoint: 50 + (raw-50) * STRETCH_K,
--      clamped 0-100. STRETCH_K = 1.4 (tunable). Gives a stable physiology
--      a felt dynamic range without inventing signal.
--
-- EMPIRICAL NOTE: sleep-as-personal-percentile was tested first on 30d of
-- real data — it spread the scores but recentered the mean from 53 -> 48
-- (penalising a consistently-good sleeper's normal night to "median").
-- Rejected in favour of the weighted-absolute + stretch above.
--
-- UNCHANGED from v102:
--   - Cold-start (<7d history) z-score sigmoid fallback (never hit by a
--     long-history user; kept verbatim for new-user UX).
--   - HRV/RHR NULL auto-renormalization.
--   - Signature, STABLE, SECURITY INVOKER, search_path pin.

CREATE OR REPLACE FUNCTION public.compute_recovery_score(
  p_user_id uuid,
  p_hrv_avg numeric,
  p_resting_hr integer,
  p_sleep_score numeric
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SET search_path = public, extensions, pg_temp
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
  stretch_k numeric := 1.4;   -- contrast factor; tune here, nowhere else
BEGIN
  SELECT COUNT(*) INTO history_days
  FROM health_metrics
  WHERE user_id = p_user_id
    AND hrv_avg IS NOT NULL AND hrv_avg > 0
    AND metric_date >= CURRENT_DATE - 30
    AND metric_date < CURRENT_DATE;

  -- Cold-start path: <7 days of usable history (UNCHANGED from v102)
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

  -- Sleep stays absolute — a consistently good sleeper keeps the credit.
  -- It's the low-weight stabiliser, not the swing driver.
  s_score := COALESCE(p_sleep_score, 50);

  -- Combine with auto-renormalizing weights (HRV 0.55 · RHR 0.30 · sleep 0.15)
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

  raw := weighted_sum / total_weight;   -- 0..100 percentile composite

  -- Contrast stretch around the midpoint so a stable body still gets a felt
  -- dynamic range. k=1.4: raw 65 -> 71, raw 80 -> 92, raw 45 -> 43,
  -- raw 25 -> 15. Clamped to 0-100.
  RETURN ROUND(LEAST(100, GREATEST(0, 50 + (raw - 50) * stretch_k)));
END;
$function$;

COMMENT ON FUNCTION public.compute_recovery_score IS
'v103 (2026-05-17). Felt-range recovery. HRV percentile (55%) + RHR inverted percentile (30%) vs own last-30d + absolute sleep (15%, low-weight stabiliser), then a midpoint contrast stretch (k=1.4) clamped 0-100. Replaces v102 whose absolute sleep term ate 30% of the weight with ~zero variance, starving the felt range for a stable physiology. Sleep-as-percentile was tested and rejected (recentered mean 53->48). Cold-start (<7d) z-score sigmoid fallback unchanged.';
