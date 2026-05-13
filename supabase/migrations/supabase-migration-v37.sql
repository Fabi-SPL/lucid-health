-- Migration v37: Add sleep_stage and readiness columns to realtime_health
-- iOS app now pushes these with every reading for sleep/health analysis

ALTER TABLE realtime_health ADD COLUMN IF NOT EXISTS sleep_stage TEXT;
ALTER TABLE realtime_health ADD COLUMN IF NOT EXISTS readiness TEXT;
