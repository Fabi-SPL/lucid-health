-- Migration v86: HMM hidden state column on realtime_health + current_state
-- Replaces simple red/yellow/green readiness with discovered hidden states.
-- Python script (scripts/fit-hmm-states.py) populates these weekly via Routine.

ALTER TABLE public.realtime_health
  ADD COLUMN IF NOT EXISTS hmm_state TEXT,
  ADD COLUMN IF NOT EXISTS hmm_state_id INTEGER;

ALTER TABLE public.current_state
  ADD COLUMN IF NOT EXISTS current_hmm_state TEXT,
  ADD COLUMN IF NOT EXISTS current_hmm_state_id INTEGER;

CREATE INDEX IF NOT EXISTS idx_realtime_health_hmm_state
  ON public.realtime_health (user_id, hmm_state)
  WHERE hmm_state IS NOT NULL;

-- Update refresh_current_state trigger to propagate hmm_state from latest BLE row
CREATE OR REPLACE FUNCTION public.refresh_current_state_from_realtime()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user UUID := NEW.user_id;
  v_now TIMESTAMPTZ := NEW.recorded_at;

  v_last_15m_start TIMESTAMPTZ := v_now - INTERVAL '15 minutes';
  v_last_1h_start  TIMESTAMPTZ := v_now - INTERVAL '1 hour';
  v_last_7d_start  TIMESTAMPTZ := v_now - INTERVAL '7 days';

  v_cog_15m NUMERIC;
  v_cog_label TEXT;
  v_illness_1h NUMERIC;
  v_baseline_hrv NUMERIC;
  v_baseline_rhr INTEGER;
  v_baseline_rr NUMERIC;
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.current_state
    WHERE user_id = v_user AND updated_at > v_now - INTERVAL '5 seconds'
  ) THEN
    RETURN NEW;
  END IF;

  SELECT AVG(cognitive_capacity) INTO v_cog_15m
  FROM public.realtime_health
  WHERE user_id = v_user AND recorded_at >= v_last_15m_start
    AND cognitive_capacity IS NOT NULL AND cognitive_capacity > 0;

  SELECT cognitive_label INTO v_cog_label
  FROM public.realtime_health
  WHERE user_id = v_user AND recorded_at >= v_last_15m_start
    AND cognitive_label IS NOT NULL
  GROUP BY cognitive_label ORDER BY COUNT(*) DESC LIMIT 1;

  SELECT MAX(illness_risk) INTO v_illness_1h
  FROM public.realtime_health
  WHERE user_id = v_user AND recorded_at >= v_last_1h_start
    AND illness_risk IS NOT NULL;

  SELECT AVG(hrv_rmssd), AVG(heart_rate)::INTEGER, AVG(respiratory_rate)
  INTO v_baseline_hrv, v_baseline_rhr, v_baseline_rr
  FROM public.realtime_health
  WHERE user_id = v_user AND recorded_at >= v_last_7d_start
    AND sleep_stage IN ('deep','rem','light')
    AND hrv_rmssd IS NOT NULL AND hrv_rmssd > 0;

  INSERT INTO public.current_state (
    user_id, updated_at,
    strap_connected, last_ble_sample_at, battery_pct,
    current_hr, current_hrv_rmssd, current_sdnn, current_dfa_alpha1, current_respiratory_rate,
    current_cognitive_capacity, current_cognitive_label, current_readiness,
    current_illness_risk, current_sleep_stage,
    current_hmm_state, current_hmm_state_id,
    baseline_hrv_avg, baseline_resting_hr, baseline_respiratory_rate,
    current_activity_state
  ) VALUES (
    v_user, v_now,
    TRUE, v_now, NEW.battery_pct,
    NEW.heart_rate, NEW.hrv_rmssd, NEW.sdnn, NEW.dfa_alpha1, NEW.respiratory_rate,
    v_cog_15m::INTEGER, v_cog_label, NEW.readiness,
    v_illness_1h, NEW.sleep_stage,
    NEW.hmm_state, NEW.hmm_state_id,
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
    current_hmm_state = COALESCE(EXCLUDED.current_hmm_state, current_state.current_hmm_state),
    current_hmm_state_id = COALESCE(EXCLUDED.current_hmm_state_id, current_state.current_hmm_state_id),
    baseline_hrv_avg = COALESCE(EXCLUDED.baseline_hrv_avg, current_state.baseline_hrv_avg),
    baseline_resting_hr = COALESCE(EXCLUDED.baseline_resting_hr, current_state.baseline_resting_hr),
    baseline_respiratory_rate = COALESCE(EXCLUDED.baseline_respiratory_rate, current_state.baseline_respiratory_rate),
    current_activity_state = EXCLUDED.current_activity_state;

  RETURN NEW;
END;
$$;

COMMENT ON COLUMN public.realtime_health.hmm_state IS 'Hidden state name discovered by HMM (e.g. "Deep Flow", "Post-ride Parasympathetic"). Populated by scripts/fit-hmm-states.py.';
COMMENT ON COLUMN public.current_state.current_hmm_state IS 'Current HMM-discovered hidden state. Replaces simple red/yellow/green readiness with 8-12 personally meaningful states.';
