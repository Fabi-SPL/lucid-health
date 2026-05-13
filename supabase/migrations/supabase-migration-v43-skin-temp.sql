-- Migration v43: Add skin_temp column to realtime_health
-- For Whoop BLE Event 17 (TEMPERATURE_LEVEL) data
-- Applied: 2026-03-26

ALTER TABLE realtime_health
  ADD COLUMN IF NOT EXISTS skin_temp NUMERIC;

COMMENT ON COLUMN realtime_health.skin_temp IS 'Skin temperature in Celsius from Whoop MAX6631MTT sensor (Event 17)';
