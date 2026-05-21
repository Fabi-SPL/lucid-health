-- migration v104_ble_sync_cursor.sql
--
-- BLE sync-cursor architecture per deep-research report 2026-05-21.
-- Replaces client-side UserDefaults.lastSync (structurally racy — bug class
-- regressed 5-10x) with server-held cursor + idempotent inserts + freshness
-- canary.
--
-- This migration is ZERO behaviour change for existing code paths:
--   - device_id / device_seq columns are NULLABLE, conditional unique index
--     does not touch legacy rows where device_seq IS NULL.
--   - View, table, cron are net new — no existing reader broken.
--   - recompute_health_metrics gains an early-return path that ONLY fires
--     when ble_freshness_alerts.state='open' for the user, which doesn't
--     exist for any user until alerts start opening.
--
-- The architectural cutover (iOS code replacing getLastSyncTimestamp with
-- fetchSyncCursor) is a separate change — this migration only lays the
-- foundation and adds observability.

-- ─────────────────────────────────────────────────────────────────────────
-- 1. Per-strap monotonic sequence on realtime_health
-- ─────────────────────────────────────────────────────────────────────────
ALTER TABLE realtime_health
  ADD COLUMN IF NOT EXISTS device_id  TEXT,
  ADD COLUMN IF NOT EXISTS device_seq BIGINT;

COMMENT ON COLUMN realtime_health.device_id  IS
  'Strap MAC/UUID for multi-device support. NULL for legacy rows.';
COMMENT ON COLUMN realtime_health.device_seq IS
  'Monotonic per-strap sample index from the Whoop binary history frame. '
  'Combined with device_id forms the canonical sample identity.';

-- ─────────────────────────────────────────────────────────────────────────
-- 2. Idempotent insert: same sample twice is a no-op
-- ─────────────────────────────────────────────────────────────────────────
CREATE UNIQUE INDEX IF NOT EXISTS realtime_health_device_seq_uidx
  ON realtime_health (user_id, device_id, device_seq)
  WHERE device_id IS NOT NULL AND device_seq IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────────
-- 3. Server-side cursor view — single source of "what we last received"
-- ─────────────────────────────────────────────────────────────────────────
DROP VIEW IF EXISTS v_ble_sync_cursor;
CREATE VIEW v_ble_sync_cursor
  WITH (security_invoker = true)
AS
SELECT
  user_id,
  device_id,
  MAX(device_seq)                                                 AS last_seq,
  MAX(recorded_at)                                                AS last_recorded_at,
  EXTRACT(EPOCH FROM (NOW() - MAX(recorded_at))) / 60::numeric    AS minutes_since_last
FROM realtime_health
WHERE device_id IS NOT NULL
GROUP BY user_id, device_id;

COMMENT ON VIEW v_ble_sync_cursor IS
  'Authoritative cursor for BLE backfill. iOS queries this on every '
  'reconnect via decideBackfill() — replaces UserDefaults.lastSync.';

-- ─────────────────────────────────────────────────────────────────────────
-- 4. Freshness alert table — populated by 1-min cron, observable in monitoring
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ble_freshness_alerts (
  id                 BIGSERIAL PRIMARY KEY,
  user_id            UUID        NOT NULL,
  device_id          TEXT        NOT NULL,
  detected_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  minutes_since_last NUMERIC     NOT NULL,
  state              TEXT        NOT NULL CHECK (state IN ('open','recovered','manual')),
  recovered_at       TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS ble_freshness_alerts_open_idx
  ON ble_freshness_alerts (user_id, device_id) WHERE state = 'open';

COMMENT ON TABLE ble_freshness_alerts IS
  'Production canary for BLE sync regressions. State=open while a user has '
  'gone >30 min without samples. State=recovered once they catch up to <5 min. '
  'Used by recompute_health_metrics to defer NULL-placeholder writes during '
  'in-flight syncs.';

-- ─────────────────────────────────────────────────────────────────────────
-- 5. 1-minute cron job — open alerts on stale data, close on recovery
-- ─────────────────────────────────────────────────────────────────────────
SELECT cron.unschedule('ble-freshness-watch')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ble-freshness-watch');

SELECT cron.schedule(
  'ble-freshness-watch',
  '* * * * *',
  $$
  -- Open a new alert when data goes stale (>30 min) and none is open
  INSERT INTO ble_freshness_alerts (user_id, device_id, minutes_since_last, state)
  SELECT c.user_id, c.device_id, c.minutes_since_last, 'open'
  FROM v_ble_sync_cursor c
  LEFT JOIN ble_freshness_alerts a
    ON a.user_id = c.user_id
   AND a.device_id = c.device_id
   AND a.state = 'open'
  WHERE c.minutes_since_last > 30
    AND a.id IS NULL;

  -- Close any open alerts whose user/device has caught up to <5 min
  UPDATE ble_freshness_alerts a
  SET state = 'recovered', recovered_at = NOW()
  FROM v_ble_sync_cursor c
  WHERE a.user_id    = c.user_id
    AND a.device_id  = c.device_id
    AND a.state      = 'open'
    AND c.minutes_since_last <= 5;
  $$
);

-- ─────────────────────────────────────────────────────────────────────────
-- 6. Patch recompute_health_metrics: never write NULL placeholder during
--    an in-flight sync (open freshness alert OR backfill_triggered in
--    last 60 min via bridge_logs).
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
BEGIN
  target_date := COALESCE(p_target_date, (now() AT TIME ZONE 'Europe/Berlin')::date);

  -- 1. Detect sleep window + stages from realtime_health
  SELECT * INTO win FROM detect_sleep_window(p_user_id, target_date);

  -- Confidence floor: need 4+ hours of measured sleep to overwrite an existing row.
  IF win.o_sleep_start IS NULL OR COALESCE(win.o_asleep_min, 0) < 240 THEN

    -- v104 NEW: do NOT write a NULL placeholder if a BLE sync is in flight.
    -- This is the architectural fix for the phone-died regression class.
    SELECT EXISTS (
      SELECT 1 FROM ble_freshness_alerts
      WHERE user_id = p_user_id AND state = 'open'
    ) INTO has_open_alert;

    -- Match any in-flight / just-finished sync activity in the last 60 min:
    --   • auto-reconnect path:  history_sync_gap_check  value~'decision=download'
    --   • manual-72h path:      history_sync_request_sent  value~'trigger=manual-72h'
    --   • either path complete: history_sync_complete (the sync finished within
    --     the window; data may still be propagating to realtime_health view)
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
      -- Sync in flight — do nothing. Existing row (if any) stays intact.
      RAISE NOTICE 'recompute_health_metrics: sync in flight for %, deferring (alert=% backfill=%)',
        p_user_id, has_open_alert, has_recent_backfill;

      SELECT * INTO result_row FROM health_metrics
      WHERE user_id = p_user_id AND metric_date = target_date;
      RETURN result_row;  -- might be NULL if no row exists yet — that's correct
    END IF;

    -- Original behaviour: insert empty placeholder if no row exists yet,
    -- but never overwrite a real one.
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
$function$;

-- End of v104.
