-- Migration v70: personal_calibration — evolving algorithm constants
-- One row per user, UPDATEd nightly by Claude Code Routine when fits improve.
-- Read by iOS on app launch (replaces UserDefaults-only storage).
-- Audit trail: every change logged to knowledge_entries with source_type='calibration_update'.

CREATE TABLE IF NOT EXISTS public.personal_calibration (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  version INTEGER NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  calibrated_at TIMESTAMPTZ,                    -- when this set of constants was fitted
  data_points INTEGER DEFAULT 0,                -- size of dataset used for fit

  -- Sleep detection (from v68 work)
  sleep_threshold NUMERIC(5,1) DEFAULT 58,      -- sleeping HR cutoff
  wake_threshold NUMERIC(5,1) DEFAULT 81,       -- awake HR cutoff
  deep_hr_ceiling NUMERIC(5,1) DEFAULT 54,      -- deep sleep max HR
  deep_sd_max NUMERIC(4,1) DEFAULT 3.0,
  rem_sd_min NUMERIC(4,1) DEFAULT 3.0,

  -- Recovery weights (0-1, sum ≈ 1.0)
  recovery_hrv_weight NUMERIC(3,2) DEFAULT 0.65,
  recovery_rhr_weight NUMERIC(3,2) DEFAULT 0.10,
  recovery_sleep_weight NUMERIC(3,2) DEFAULT 0.10,
  recovery_rr_weight NUMERIC(3,2) DEFAULT 0.15,

  -- Respiratory rate baseline
  rr_baseline NUMERIC(5,2) DEFAULT 17.23,
  rr_sd NUMERIC(4,3) DEFAULT 1.155,

  -- Cognitive capacity weights
  cognitive_hrv_weight NUMERIC(3,2) DEFAULT 0.30,
  cognitive_sdnn_weight NUMERIC(3,2) DEFAULT 0.30,
  cognitive_sleep_weight NUMERIC(3,2) DEFAULT 0.25,
  cognitive_dfa_weight NUMERIC(3,2) DEFAULT 0.15,

  -- Training load thresholds
  acwr_high_threshold NUMERIC(3,2) DEFAULT 1.3,
  acwr_low_threshold NUMERIC(3,2) DEFAULT 0.8,
  monotony_cutoff NUMERIC(4,2) DEFAULT 2.87,

  -- Activity detector thresholds
  sauna_hr INTEGER DEFAULT 103,
  alcohol_hr_deviation INTEGER DEFAULT 8,
  alcohol_hrv_drop NUMERIC(3,2) DEFAULT 0.23,

  -- Illness detection
  illness_z_threshold NUMERIC(3,1) DEFAULT 2.0,
  illness_baseline_window INTEGER DEFAULT 14,
  illness_min_signals INTEGER DEFAULT 2,

  -- Smart alarm
  smart_alarm_rmssd_rise_pct NUMERIC(4,2) DEFAULT 0.20,

  -- Free-form extension (any new constant without schema change)
  extras JSONB DEFAULT '{}'::jsonb,

  -- Audit
  change_reason TEXT,
  changed_fields TEXT[]
);

-- RLS
ALTER TABLE public.personal_calibration ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "personal_calibration_owner" ON public.personal_calibration;
CREATE POLICY "personal_calibration_owner" ON public.personal_calibration
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- Trigger: bump updated_at on any change
CREATE OR REPLACE FUNCTION public.touch_personal_calibration()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  NEW.version = COALESCE(OLD.version, 0) + 1;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_touch_personal_calibration ON public.personal_calibration;
CREATE TRIGGER trg_touch_personal_calibration
  BEFORE UPDATE ON public.personal_calibration
  FOR EACH ROW EXECUTE FUNCTION public.touch_personal_calibration();

-- Realtime (iOS app subscribes for live calibration updates)
ALTER PUBLICATION supabase_realtime ADD TABLE public.personal_calibration;

-- Seed Fabi's row with current fitted values (from calibration/results/*_v1.json)
INSERT INTO public.personal_calibration (
  user_id,
  calibrated_at,
  data_points,
  sleep_threshold, wake_threshold, deep_hr_ceiling,
  recovery_hrv_weight, recovery_rhr_weight, recovery_sleep_weight, recovery_rr_weight,
  rr_baseline, rr_sd,
  acwr_high_threshold, monotony_cutoff,
  sauna_hr, alcohol_hrv_drop
) VALUES (
  'YOUR_USER_ID_HERE',
  '2026-04-21T13:54:04Z',
  477,
  58, 81, 54,
  0.65, 0.10, 0.10, 0.15,
  17.23, 1.155,
  1.3, 2.87,
  103, 0.23
) ON CONFLICT (user_id) DO NOTHING;

COMMENT ON TABLE public.personal_calibration IS
  'Per-user algorithm constants. iOS reads on launch. Nightly Routine re-fits and UPDATEs when new data improves fit significantly. Every change → knowledge_entries audit row.';
