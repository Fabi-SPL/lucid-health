-- Migration v41: Add altitude column to realtime_health for ski trip elevation tracking
-- Applied: 2026-03-25

ALTER TABLE realtime_health
  ADD COLUMN IF NOT EXISTS altitude NUMERIC;

COMMENT ON COLUMN realtime_health.altitude IS 'GPS altitude in meters above sea level (from iPhone CoreLocation)';
