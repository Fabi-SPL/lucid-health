-- v101: Task data model — actual duration, difficulty, started_at
--
-- Hermes pattern engine + chat interpretation both want to know:
--   how long tasks actually took (not just estimated)
--   how hard they were (not just energy_level which is rough)
--   when work started (not just when added to list)
--
-- These columns are additive + nullable. No backfill — historical tasks stay
-- NULL for these fields; new completions populate them via the iOS app.

ALTER TABLE tasks ADD COLUMN IF NOT EXISTS actual_duration_minutes integer;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS difficulty smallint;  -- 1-5 self-reported
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS started_at timestamptz;

-- Sanity bounds
ALTER TABLE tasks DROP CONSTRAINT IF EXISTS tasks_difficulty_range;
ALTER TABLE tasks ADD CONSTRAINT tasks_difficulty_range
  CHECK (difficulty IS NULL OR (difficulty >= 1 AND difficulty <= 5));

ALTER TABLE tasks DROP CONSTRAINT IF EXISTS tasks_actual_duration_nonneg;
ALTER TABLE tasks ADD CONSTRAINT tasks_actual_duration_nonneg
  CHECK (actual_duration_minutes IS NULL OR actual_duration_minutes >= 0);

-- Index for time-range queries that filter to actually-tracked completions
CREATE INDEX IF NOT EXISTS idx_tasks_user_completed_with_duration
  ON tasks (user_id, completed_at DESC)
  WHERE actual_duration_minutes IS NOT NULL;

COMMENT ON COLUMN tasks.actual_duration_minutes IS
  'Real time spent on task, populated when iOS completes via timer or manual entry. NULL = not tracked.';
COMMENT ON COLUMN tasks.difficulty IS
  'Self-reported 1-5 difficulty rating. NULL = not rated. Used by Hermes for hardness × recovery correlations.';
COMMENT ON COLUMN tasks.started_at IS
  'When work actually began (not when task was added). NULL = not tracked.';
