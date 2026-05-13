-- ============================================================
-- Migration v76 — Biometric + Circadian Retrieval Gating
-- Apply as supabase_admin. Extends v58 health-gated recall.
-- ============================================================
-- Per1 gene gates hippocampal memory consolidation based on circadian
-- phase. Fabi has 634 days of health_metrics + get_current_focus() already
-- returning focus state. Wire as a multiplicative confidence gate on
-- retrieval — boost when brain-state is "sharp," dampen when "fogged."
--
-- Gate formula:
--   gate = 1.0 (default)
--   + 0.2 if morning (6-12h local) AND HRV > baseline AND recovery > 70
--   + 0.1 if focus_mode = 'work' or 'deep-focus'
--   - 0.2 if late-night (past 23h) AND recovery < 50
--   - 0.1 if high strain (>14) in last 24h
--   clamp to [0.6, 1.3]
--
-- Returned as factor — TS layer multiplies similarity by this to surface
-- appropriate memories. Commercial systems cannot: no health data, no
-- circadian awareness, no per-user physiology.
-- ============================================================

CREATE OR REPLACE FUNCTION get_retrieval_gate(
  p_user_id UUID DEFAULT auth.uid()
)
RETURNS TABLE (
  gate_factor REAL,
  hour_local  INT,
  hrv_relative REAL,
  recovery_score REAL,
  focus_mode TEXT,
  reasoning TEXT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
DECLARE
  hour_l INT;
  hrv_today REAL;
  hrv_baseline REAL;
  hrv_rel REAL;
  recov REAL;
  strain_24h REAL;
  focus TEXT;
  gate REAL := 1.0;
  reasons TEXT := '';
BEGIN
  -- Hour in Fabi's local TZ (Germany = Europe/Berlin)
  hour_l := EXTRACT(HOUR FROM NOW() AT TIME ZONE 'Europe/Berlin')::INT;

  -- Today's health metrics
  SELECT hm.hrv_avg, hm.recovery_score, COALESCE(hm.strain_score, 0)
  INTO hrv_today, recov, strain_24h
  FROM health_metrics hm
  WHERE hm.user_id = p_user_id
    AND hm.date = CURRENT_DATE
  LIMIT 1;

  -- 30-day rolling HRV baseline for relative comparison
  SELECT AVG(hrv_avg) INTO hrv_baseline
  FROM health_metrics
  WHERE user_id = p_user_id
    AND date > CURRENT_DATE - INTERVAL '30 days'
    AND hrv_avg IS NOT NULL AND hrv_avg > 0;

  hrv_rel := CASE WHEN hrv_baseline > 0 THEN hrv_today / hrv_baseline ELSE 1.0 END;

  -- Current focus mode (from v27)
  BEGIN
    SELECT fe.focus_name INTO focus
    FROM focus_events fe
    WHERE fe.user_id = p_user_id
    ORDER BY fe.changed_at DESC
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN focus := NULL;
  END;

  -- ── Compute gate factor ───────────────────────────────────
  -- Morning peak + good recovery
  IF hour_l BETWEEN 6 AND 12 AND COALESCE(recov, 0) > 70 AND COALESCE(hrv_rel, 0) > 1.0 THEN
    gate := gate + 0.2;
    reasons := reasons || 'morning-peak;';
  END IF;

  -- Deep-focus mode
  IF focus IN ('work', 'deep-focus', 'Deep Work') THEN
    gate := gate + 0.1;
    reasons := reasons || 'focus-mode;';
  END IF;

  -- Late night fatigue
  IF (hour_l >= 23 OR hour_l < 5) AND COALESCE(recov, 100) < 50 THEN
    gate := gate - 0.2;
    reasons := reasons || 'late-fatigue;';
  END IF;

  -- High recent strain
  IF COALESCE(strain_24h, 0) > 14 THEN
    gate := gate - 0.1;
    reasons := reasons || 'high-strain;';
  END IF;

  -- Clamp
  gate := GREATEST(0.6, LEAST(1.3, gate));

  RETURN QUERY SELECT gate::REAL, hour_l, hrv_rel::REAL, recov::REAL, focus, reasons;
END;
$$;

GRANT EXECUTE ON FUNCTION get_retrieval_gate(UUID) TO authenticated;

COMMENT ON FUNCTION get_retrieval_gate(UUID) IS
  'v76: Biometric + circadian multiplicative gate on retrieval. Combines hour-of-day, HRV relative to baseline, recovery score, focus mode, and 24h strain into [0.6, 1.3] factor. Applied TS-side to similarity scores. Extends v58 health-gated recall.';
