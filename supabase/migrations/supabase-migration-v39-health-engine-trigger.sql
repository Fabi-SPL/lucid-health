-- ============================================================
-- v39: Auto-trigger health engine on wake-up brain dump
-- ============================================================
-- Creates a database trigger that fires when a brain_dump with
-- 'wake-up' tag is inserted. Calls the health-engine-compute
-- edge function via pg_net.
--
-- Prerequisites:
--   - pg_net extension enabled (Supabase has this by default)
--   - health-engine-compute edge function deployed
-- ============================================================

-- Enable pg_net if not already
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- Function that calls the edge function via HTTP
CREATE OR REPLACE FUNCTION trigger_health_engine_on_wakeup()
RETURNS TRIGGER AS $$
DECLARE
  _tags jsonb;
  _supabase_url text;
  _service_key text;
BEGIN
  -- Only fire for wake-up tagged dumps
  _tags := to_jsonb(NEW.tags);
  IF NOT (_tags @> '"wake-up"'::jsonb) THEN
    RETURN NEW;
  END IF;

  -- Only fire for our user
  IF NEW.user_id != 'YOUR_USER_ID_HERE'::uuid THEN
    RETURN NEW;
  END IF;

  -- Get Supabase URL from current database
  _supabase_url := current_setting('app.settings.supabase_url', true);
  IF _supabase_url IS NULL THEN
    _supabase_url := 'YOUR_SUPABASE_URL_HERE';
  END IF;

  _service_key := current_setting('app.settings.service_role_key', true);

  -- Call edge function via pg_net (non-blocking HTTP POST)
  PERFORM extensions.http_post(
    url := _supabase_url || '/functions/v1/health-engine-compute',
    body := jsonb_build_object(
      'type', 'INSERT',
      'table', 'brain_dumps',
      'record', jsonb_build_object(
        'id', NEW.id,
        'user_id', NEW.user_id,
        'tags', NEW.tags,
        'created_at', NEW.created_at
      )
    )::text,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || COALESCE(_service_key, '')
    )::jsonb
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Don't block brain_dump inserts if trigger fails
  RAISE WARNING 'Health engine trigger failed: %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create the trigger
DROP TRIGGER IF EXISTS health_engine_wakeup_trigger ON brain_dumps;
CREATE TRIGGER health_engine_wakeup_trigger
  AFTER INSERT ON brain_dumps
  FOR EACH ROW
  EXECUTE FUNCTION trigger_health_engine_on_wakeup();

-- Update health_metrics source constraint to allow 'health_engine'
ALTER TABLE health_metrics DROP CONSTRAINT IF EXISTS health_metrics_source_check;
ALTER TABLE health_metrics ADD CONSTRAINT health_metrics_source_check
  CHECK (source IN ('whoop_backfill', 'whoop_csv', 'apple_health', 'ble_live', 'daily_shortcut', 'health_engine', 'manual'));

-- Add comment
COMMENT ON FUNCTION trigger_health_engine_on_wakeup() IS
  'Auto-triggers health engine computation when a wake-up brain dump is inserted by the BLE bridge';
