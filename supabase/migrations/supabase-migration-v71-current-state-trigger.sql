-- Migration v71: Postgres trigger — auto-update current_state on every realtime_health insert
-- Zero iOS code change. Every BLE sample (10 sec) refreshes the current live state.
-- Rolling aggregates computed server-side from the last N hours of realtime_health.

CREATE OR REPLACE FUNCTION public.refresh_current_state_from_realtime()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user UUID := NEW.user_id;
  v_now TIMESTAMPTZ := NEW.recorded_at;

  -- Rolling windows
  v_last_15m_start TIMESTAMPTZ := v_now - INTERVAL '15 minutes';
  v_last_1h_start  TIMESTAMPTZ := v_now - INTERVAL '1 hour';
  v_last_4h_start  TIMESTAMPTZ := v_now - INTERVAL '4 hours';
  v_today_start    TIMESTAMPTZ := date_trunc('day', v_now AT TIME ZONE 'Europe/Berlin') AT TIME ZONE 'Europe/Berlin';
  v_last_7d_start  TIMESTAMPTZ := v_now - INTERVAL '7 days';

  -- Derived scalars
  v_current_hr INTEGER;
  v_current_hrv NUMERIC;
  v_current_sdnn NUMERIC;
  v_current_dfa NUMERIC;
  v_current_rr NUMERIC;
  v_cog_15m NUMERIC;
  v_cog_label TEXT;
  v_illness_1h NUMERIC;
  v_baseline_hrv NUMERIC;
  v_baseline_rhr INTEGER;
  v_baseline_rr NUMERIC;
BEGIN
  -- Rate-limit: only update if last update >5 seconds ago (avoid hammering on burst inserts)
  IF EXISTS (
    SELECT 1 FROM public.current_state
    WHERE user_id = v_user AND updated_at > v_now - INTERVAL '5 seconds'
  ) THEN
    RETURN NEW;
  END IF;

  -- Latest values (use NEW directly — cheapest)
  v_current_hr := NEW.heart_rate;
  v_current_hrv := NEW.hrv_rmssd;
  v_current_sdnn := NEW.sdnn;
  v_current_dfa := NEW.dfa_alpha1;
  v_current_rr := NEW.respiratory_rate;

  -- 15-min cognitive capacity avg
  SELECT AVG(cognitive_capacity) INTO v_cog_15m
  FROM public.realtime_health
  WHERE user_id = v_user
    AND recorded_at >= v_last_15m_start
    AND cognitive_capacity IS NOT NULL AND cognitive_capacity > 0;

  -- Most common cognitive label in last 15 min
  SELECT cognitive_label INTO v_cog_label
  FROM public.realtime_health
  WHERE user_id = v_user
    AND recorded_at >= v_last_15m_start
    AND cognitive_label IS NOT NULL
  GROUP BY cognitive_label
  ORDER BY COUNT(*) DESC
  LIMIT 1;

  -- Rolling 1h max illness_risk
  SELECT MAX(illness_risk) INTO v_illness_1h
  FROM public.realtime_health
  WHERE user_id = v_user
    AND recorded_at >= v_last_1h_start
    AND illness_risk IS NOT NULL;

  -- 7-day baseline (sleeping HRV + sleeping HR + RR) — sleep_stage IN (deep, rem, light)
  SELECT AVG(hrv_rmssd), AVG(heart_rate)::INTEGER, AVG(respiratory_rate)
  INTO v_baseline_hrv, v_baseline_rhr, v_baseline_rr
  FROM public.realtime_health
  WHERE user_id = v_user
    AND recorded_at >= v_last_7d_start
    AND sleep_stage IN ('deep','rem','light')
    AND hrv_rmssd IS NOT NULL AND hrv_rmssd > 0;

  -- Upsert
  INSERT INTO public.current_state (
    user_id, updated_at,
    strap_connected, last_ble_sample_at, battery_pct, firmware_version,
    current_hr, current_hrv_rmssd, current_sdnn, current_dfa_alpha1, current_respiratory_rate,
    current_cognitive_capacity, current_cognitive_label, current_readiness,
    current_illness_risk, current_sleep_stage,
    baseline_hrv_avg, baseline_resting_hr, baseline_respiratory_rate,
    current_activity_state
  ) VALUES (
    v_user, v_now,
    TRUE, v_now, NEW.battery_pct, NULL,  -- firmware_version comes from a different source
    v_current_hr, v_current_hrv, v_current_sdnn, v_current_dfa, v_current_rr,
    v_cog_15m::INTEGER, v_cog_label, NEW.readiness,
    v_illness_1h, NEW.sleep_stage,
    v_baseline_hrv, v_baseline_rhr, v_baseline_rr,
    CASE
      WHEN NEW.sleep_stage IN ('deep','rem','light') THEN 'sleeping'
      WHEN NEW.heart_rate > 110 THEN 'active'
      ELSE 'resting'
    END
  )
  ON CONFLICT (user_id) DO UPDATE SET
    updated_at = EXCLUDED.updated_at,
    strap_connected = TRUE,
    last_ble_sample_at = EXCLUDED.last_ble_sample_at,
    battery_pct = EXCLUDED.battery_pct,
    current_hr = EXCLUDED.current_hr,
    current_hrv_rmssd = EXCLUDED.current_hrv_rmssd,
    current_sdnn = COALESCE(EXCLUDED.current_sdnn, current_state.current_sdnn),
    current_dfa_alpha1 = COALESCE(EXCLUDED.current_dfa_alpha1, current_state.current_dfa_alpha1),
    current_respiratory_rate = COALESCE(EXCLUDED.current_respiratory_rate, current_state.current_respiratory_rate),
    current_cognitive_capacity = COALESCE(EXCLUDED.current_cognitive_capacity, current_state.current_cognitive_capacity),
    current_cognitive_label = COALESCE(EXCLUDED.current_cognitive_label, current_state.current_cognitive_label),
    current_readiness = COALESCE(EXCLUDED.current_readiness, current_state.current_readiness),
    current_illness_risk = COALESCE(EXCLUDED.current_illness_risk, current_state.current_illness_risk),
    current_sleep_stage = EXCLUDED.current_sleep_stage,
    baseline_hrv_avg = COALESCE(EXCLUDED.baseline_hrv_avg, current_state.baseline_hrv_avg),
    baseline_resting_hr = COALESCE(EXCLUDED.baseline_resting_hr, current_state.baseline_resting_hr),
    baseline_respiratory_rate = COALESCE(EXCLUDED.baseline_respiratory_rate, current_state.baseline_respiratory_rate),
    current_activity_state = EXCLUDED.current_activity_state;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_refresh_current_state ON public.realtime_health;
CREATE TRIGGER trg_refresh_current_state
  AFTER INSERT ON public.realtime_health
  FOR EACH ROW
  EXECUTE FUNCTION public.refresh_current_state_from_realtime();

COMMENT ON FUNCTION public.refresh_current_state_from_realtime IS
  'Auto-upserts public.current_state on every realtime_health INSERT. Rate-limited to one update per 5 seconds. Computes rolling 15-min cognitive avg, 1h max illness_risk, 7d sleeping baselines. Zero iOS code change required for live updates.';
