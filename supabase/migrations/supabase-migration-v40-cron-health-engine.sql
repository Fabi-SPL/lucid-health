-- ============================================================
-- v40: Health engine runs every 5 minutes via pg_cron
-- ============================================================
-- Replaces the broken v39 brain_dump trigger.
-- Runs every 5 min, computes fresh scores from latest BLE data.
-- The edge function handles debouncing (skips if no new data).
--
-- Result: strain, recovery, readiness update throughout the day.
-- ============================================================

-- Enable pg_cron (Supabase has this by default on Pro plans)
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

-- Enable pg_net for HTTP calls
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- Drop the old trigger that never fires
DROP TRIGGER IF EXISTS health_engine_wakeup_trigger ON brain_dumps;
DROP TRIGGER IF EXISTS health_engine_data_trigger ON realtime_health;

-- Function that calls the edge function
CREATE OR REPLACE FUNCTION call_health_engine()
RETURNS void AS $$
DECLARE
  _supabase_url text;
  _service_key text;
BEGIN
  _supabase_url := 'YOUR_SUPABASE_URL_HERE';

  _service_key := current_setting('app.settings.service_role_key', true);
  IF _service_key IS NULL THEN
    _service_key := current_setting('supabase.service_role_key', true);
  END IF;

  PERFORM extensions.http_post(
    url := _supabase_url || '/functions/v1/health-engine-compute',
    body := '{"type": "cron_5min"}'::text,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || COALESCE(_service_key, '')
    )::jsonb
  );

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'Health engine cron failed: %', SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Schedule: every 5 minutes
SELECT cron.schedule(
  'health-engine-compute',
  '*/5 * * * *',
  $$ SELECT call_health_engine() $$
);

COMMENT ON FUNCTION call_health_engine() IS
  'Called by pg_cron every 5 min. Triggers health engine edge function to recompute strain/recovery/readiness from latest BLE data.';
