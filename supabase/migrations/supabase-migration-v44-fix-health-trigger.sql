-- ============================================================
-- v44: Fix health engine trigger — use net.http_post (pg_net)
-- ============================================================
-- Bug: v40-fix used extensions.http_post() which doesn't exist.
-- The correct Supabase function is net.http_post() from pg_net.
-- This migration fixes both the INSERT trigger and the cron job.
--
-- Run in Supabase SQL Editor.
-- ============================================================

-- Ensure pg_net is enabled (standard in Supabase)
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

-- ── 1. Fix the realtime_health INSERT trigger ──────────────────

CREATE OR REPLACE FUNCTION trigger_health_engine_on_data()
RETURNS TRIGGER AS $$
DECLARE
  _today date;
  _existing_count int;
  _last_compute timestamptz;
BEGIN
  -- Only fire for our user
  IF NEW.user_id != 'YOUR_USER_ID_HERE'::uuid THEN
    RETURN NEW;
  END IF;

  _today := (now() AT TIME ZONE 'Europe/Berlin')::date;

  -- Check if we already have a health_engine row for today
  SELECT count(*), max(created_at) INTO _existing_count, _last_compute
  FROM health_metrics
  WHERE user_id = NEW.user_id
    AND metric_date = _today
    AND source IN ('health_engine', 'daily_shortcut');

  -- If already computed in the last 30 min, skip
  IF _existing_count > 0 AND _last_compute > now() - interval '30 minutes' THEN
    RETURN NEW;
  END IF;

  -- Only trigger during waking hours (5am-11am Berlin) for morning compute
  -- OR if history data arrives (phone reconnect = sync burst)
  IF NOT (
    extract(hour from now() AT TIME ZONE 'Europe/Berlin') BETWEEN 5 AND 11
    OR NEW.source = 'whoop_ble_history'
  ) THEN
    RETURN NEW;
  END IF;

  -- Rate limit with advisory lock
  IF NOT pg_try_advisory_xact_lock(hashtext('health_engine_trigger')) THEN
    RETURN NEW;
  END IF;

  -- Call edge function via pg_net (correct function!)
  PERFORM net.http_post(
    url := 'YOUR_SUPABASE_URL_HERE/functions/v1/health-engine-compute',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || COALESCE(
        current_setting('app.settings.service_role_key', true),
        current_setting('supabase.service_role_key', true),
        ''
      )
    ),
    body := jsonb_build_object(
      'type', 'realtime_health_trigger',
      'source', NEW.source
    )
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Never block data inserts
  RAISE WARNING 'Health engine trigger failed: %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate trigger
DROP TRIGGER IF EXISTS health_engine_data_trigger ON realtime_health;
CREATE TRIGGER health_engine_data_trigger
  AFTER INSERT ON realtime_health
  FOR EACH ROW
  EXECUTE FUNCTION trigger_health_engine_on_data();

-- ── 2. Fix the pg_cron job ─────────────────────────────────────

-- Remove old broken cron job
SELECT cron.unschedule('health-engine-compute')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'health-engine-compute');

-- Create fixed cron job using net.http_post
SELECT cron.schedule(
  'health-engine-compute',
  '*/5 * * * *',
  $$
  SELECT net.http_post(
    url := 'YOUR_SUPABASE_URL_HERE/functions/v1/health-engine-compute',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
    ),
    body := '{"type": "cron_5min"}'::jsonb
  );
  $$
);

-- ── 3. Verify ──────────────────────────────────────────────────

-- After running, check:
-- SELECT * FROM cron.job WHERE jobname = 'health-engine-compute';
-- Should show a job running every 5 minutes.
--
-- To check if pg_net requests are going out:
-- SELECT * FROM net._http_response ORDER BY created DESC LIMIT 10;
--
-- NOTE: If current_setting('app.settings.service_role_key') returns null,
-- you need to set it in Supabase Dashboard → Settings → Database →
-- Database Settings → Add "app.settings.service_role_key" with your
-- service role key value. Or use the anon key for the edge function.
