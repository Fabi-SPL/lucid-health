-- ============================================================
-- v40: Fix auto-trigger — use realtime_health instead of brain_dumps
-- ============================================================
-- Problem: The v39 trigger listened for 'wake-up' tagged brain_dumps,
-- but the iOS bridge never posts those. It posts data directly to
-- realtime_health.
--
-- New approach: Trigger when a burst of whoop_ble_history data arrives.
-- This happens when the phone reconnects in the morning and syncs
-- overnight data. If history arrives and we haven't computed today,
-- fire the edge function.
--
-- Also adds a simple cron-like check: any realtime_health insert
-- after 5am local time, if no health_metrics row exists for today,
-- triggers a compute. Debounced by the edge function (30 min window).
-- ============================================================

-- Drop the old trigger that never fires
DROP TRIGGER IF EXISTS health_engine_wakeup_trigger ON brain_dumps;

-- New function: triggers on realtime_health inserts
CREATE OR REPLACE FUNCTION trigger_health_engine_on_data()
RETURNS TRIGGER AS $$
DECLARE
  _today date;
  _existing_count int;
  _last_compute timestamptz;
  _supabase_url text;
BEGIN
  -- Only fire for our user
  IF NEW.user_id != 'YOUR_USER_ID_HERE'::uuid THEN
    RETURN NEW;
  END IF;

  _today := (now() AT TIME ZONE 'Europe/Berlin')::date;

  -- Check if we already have a health_engine row for today
  SELECT count(*), max(updated_at) INTO _existing_count, _last_compute
  FROM health_metrics
  WHERE user_id = NEW.user_id
    AND metric_date = _today
    AND source IN ('health_engine', 'daily_shortcut');

  -- If already computed in the last 30 min, skip
  IF _existing_count > 0 AND _last_compute > now() - interval '30 minutes' THEN
    RETURN NEW;
  END IF;

  -- Only trigger during waking hours (5am-11am Berlin time) for morning compute
  -- OR if history data arrives (phone reconnect = sync burst)
  IF NOT (
    extract(hour from now() AT TIME ZONE 'Europe/Berlin') BETWEEN 5 AND 11
    OR NEW.source = 'whoop_ble_history'
  ) THEN
    RETURN NEW;
  END IF;

  -- Rate limit: only fire once per batch of inserts
  -- Use advisory lock to prevent concurrent triggers
  IF NOT pg_try_advisory_xact_lock(hashtext('health_engine_trigger')) THEN
    RETURN NEW;
  END IF;

  -- Get Supabase URL
  _supabase_url := current_setting('app.settings.supabase_url', true);
  IF _supabase_url IS NULL THEN
    _supabase_url := 'YOUR_SUPABASE_URL_HERE';
  END IF;

  -- Call edge function via pg_net
  PERFORM extensions.http_post(
    url := _supabase_url || '/functions/v1/health-engine-compute',
    body := jsonb_build_object(
      'type', 'realtime_health_trigger',
      'source', NEW.source,
      'recorded_at', NEW.recorded_at
    )::text,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || COALESCE(
        current_setting('app.settings.service_role_key', true),
        current_setting('supabase.service_role_key', true),
        ''
      )
    )::jsonb
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Never block data inserts
  RAISE WARNING 'Health engine trigger failed: %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create the new trigger on realtime_health
-- Only fires on INSERT (new readings), not UPDATE
DROP TRIGGER IF EXISTS health_engine_data_trigger ON realtime_health;
CREATE TRIGGER health_engine_data_trigger
  AFTER INSERT ON realtime_health
  FOR EACH ROW
  EXECUTE FUNCTION trigger_health_engine_on_data();

-- Keep the brain_dumps trigger too (belt and suspenders)
-- In case a future iOS version does post wake-up tags
CREATE OR REPLACE FUNCTION trigger_health_engine_on_wakeup()
RETURNS TRIGGER AS $$
DECLARE
  _tags jsonb;
  _supabase_url text;
BEGIN
  _tags := to_jsonb(NEW.tags);
  IF NOT (_tags @> '"wake-up"'::jsonb) THEN
    RETURN NEW;
  END IF;

  IF NEW.user_id != 'YOUR_USER_ID_HERE'::uuid THEN
    RETURN NEW;
  END IF;

  _supabase_url := current_setting('app.settings.supabase_url', true);
  IF _supabase_url IS NULL THEN
    _supabase_url := 'YOUR_SUPABASE_URL_HERE';
  END IF;

  PERFORM extensions.http_post(
    url := _supabase_url || '/functions/v1/health-engine-compute',
    body := jsonb_build_object(
      'type', 'INSERT',
      'table', 'brain_dumps',
      'record', jsonb_build_object('id', NEW.id, 'user_id', NEW.user_id, 'tags', NEW.tags)
    )::text,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || COALESCE(
        current_setting('app.settings.service_role_key', true),
        ''
      )
    )::jsonb
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'Health engine trigger failed: %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS health_engine_wakeup_trigger ON brain_dumps;
CREATE TRIGGER health_engine_wakeup_trigger
  AFTER INSERT ON brain_dumps
  FOR EACH ROW
  EXECUTE FUNCTION trigger_health_engine_on_wakeup();

COMMENT ON FUNCTION trigger_health_engine_on_data() IS
  'Auto-triggers health engine when BLE data arrives during morning hours (5-11am Berlin) or when history sync happens. Debounced by 30-min window.';
