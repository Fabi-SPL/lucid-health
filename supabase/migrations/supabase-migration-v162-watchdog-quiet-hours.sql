-- v162 — Make the BLE watchdog worth listening to.
--
-- v157 fixed a watchdog that never spoke. It overcorrected: on 2026-08-06 it
-- fired five times (08:24, 09:47, 11:06, 12:48, 13:57) on 10-11 minute gaps
-- that every single time recovered on their own within 6-28 minutes. That is
-- normal daytime BLE behaviour — he walks away from the phone, the strap
-- reconnects. Five banners for nothing is how an alert becomes wallpaper, and
-- a watchdog you have learned to ignore is back to being no watchdog at all.
--
-- The asymmetry that matters: a 20-minute daytime gap costs a few HR samples.
-- A 20-minute gap at 03:00 is sleep-stage data that never comes back, on the
-- single biggest lever of the Aug 2026 cut. So:
--
--   night (22:00-08:00) → notify after 12 min still-open
--   day   (08:00-22:00) → notify after 30 min still-open
--
-- Episodes are still RECORDED at the caller's threshold (10 min) so the
-- diagnostic history in ble_freshness_alerts stays granular. Only the banner
-- moved. The notify decision is now made on a later cron pass rather than at
-- episode open, which is what lets a self-healing gap pass in silence.
--
-- Plus a hard cap of 3 banners/day so no failure mode can ever spam him again.

CREATE OR REPLACE FUNCTION public.ble_freshness_check(p_threshold_min integer DEFAULT 10)
RETURNS void
LANGUAGE plpgsql
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE
  r record;
  v_reason text;
  v_hour int;
  v_night boolean;
  v_notify_after int;
  v_sent_today int;
  v_cap constant int := 3;
BEGIN
  v_hour  := extract(hour FROM (now() AT TIME ZONE 'Europe/Berlin'));
  v_night := (v_hour >= 22 OR v_hour < 8);
  v_notify_after := CASE WHEN v_night THEN 12 ELSE 30 END;

  -- 1. Open a gap-episode when data goes stale. SILENT on purpose now — an
  --    episode opening is a fact worth recording, not yet worth interrupting.
  FOR r IN
    SELECT c.user_id, c.device_id, c.minutes_since_last
    FROM v_ble_sync_cursor c
    LEFT JOIN ble_freshness_alerts a
      ON a.user_id = c.user_id
     AND a.device_id IS NOT DISTINCT FROM c.device_id
     AND a.state = 'open'
    WHERE c.minutes_since_last > p_threshold_min
      AND a.id IS NULL
  LOOP
    SELECT substring(value from 'reason=([^.]*)') INTO v_reason
    FROM bridge_logs
    WHERE user_id = r.user_id AND category = 'evt_ble_disconnected'
    ORDER BY created_at DESC LIMIT 1;

    INSERT INTO ble_freshness_alerts (user_id, device_id, minutes_since_last, state, disconnect_reason)
    VALUES (r.user_id, r.device_id, r.minutes_since_last, 'open', trim(v_reason));
  END LOOP;

  -- 2. Notify only once an episode has SURVIVED the notify window. A gap that
  --    heals itself inside that window is never mentioned.
  FOR r IN
    SELECT a.id, a.user_id, a.disconnect_reason, c.minutes_since_last
    FROM ble_freshness_alerts a
    JOIN v_ble_sync_cursor c
      ON c.user_id = a.user_id
     AND a.device_id IS NOT DISTINCT FROM c.device_id
    WHERE a.state = 'open'
      AND a.notified_at IS NULL
      AND a.detected_at < now() - make_interval(mins => v_notify_after)
      AND c.minutes_since_last > p_threshold_min
  LOOP
    SELECT count(*) INTO v_sent_today
      FROM notification_queue
     WHERE user_id = r.user_id
       AND title LIKE '%Whoop%'
       AND scheduled_for >= date_trunc('day', now() AT TIME ZONE 'Europe/Berlin') AT TIME ZONE 'Europe/Berlin';

    IF v_sent_today >= v_cap THEN
      -- mark it handled anyway so it does not queue up behind the cap
      UPDATE ble_freshness_alerts SET notified_at = now() WHERE id = r.id;
      CONTINUE;
    END IF;

    INSERT INTO notification_queue (user_id, type, scheduled_for, title, body, priority)
    VALUES (
      r.user_id, 'cli', now(),
      CASE WHEN v_night THEN '🌙 Whoop stream dead — sleep is not being recorded'
           ELSE '📡 Whoop stream dead' END,
      'No biometric data for ' || round(r.minutes_since_last) || ' min.'
      || coalesce(E'\nLast disconnect: ' || r.disconnect_reason, '')
      || CASE WHEN v_night
              THEN E'\n\nEvery minute down is sleep data you do not get back. Reseat the strap and reopen LucidHealth.'
              ELSE E'\n\nReopen LucidHealth and check the strap is seated.' END,
      CASE WHEN v_night THEN 'high' ELSE 'normal' END
    );

    UPDATE ble_freshness_alerts SET notified_at = now() WHERE id = r.id;
  END LOOP;

  -- 3. One escalation if it is STILL dead 45 min after the first banner.
  FOR r IN
    SELECT a.id, a.user_id, c.minutes_since_last
    FROM ble_freshness_alerts a
    JOIN v_ble_sync_cursor c
      ON c.user_id = a.user_id
     AND a.device_id IS NOT DISTINCT FROM c.device_id
    WHERE a.state = 'open'
      AND a.notified_at IS NOT NULL
      AND a.escalated_at IS NULL
      AND a.notified_at < now() - interval '45 minutes'
      AND c.minutes_since_last > p_threshold_min
  LOOP
    INSERT INTO notification_queue (user_id, type, scheduled_for, title, body, priority)
    VALUES (
      r.user_id, 'cli', now(),
      '🚨 Whoop STILL down — ' || round(r.minutes_since_last) || ' min',
      'The stream never came back after the first alert. This needs the strap on the charger for a hard power-cycle.',
      'high'
    );
    UPDATE ble_freshness_alerts SET escalated_at = now() WHERE id = r.id;
  END LOOP;

  -- 4. Silent recovery close.
  UPDATE ble_freshness_alerts a
  SET state = 'recovered', recovered_at = NOW()
  FROM v_ble_sync_cursor c
  WHERE a.user_id = c.user_id
    AND a.device_id IS NOT DISTINCT FROM c.device_id
    AND a.state = 'open'
    AND c.minutes_since_last <= 5;
END $function$;
