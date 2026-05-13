-- v96: Backfill helper — list minute-buckets that already have realtime_health data
--
-- Used by the iOS "Manual 72h Backfill" button to dedup against existing rows
-- before uploading strap-buffered records.
--
-- Why a function: realtime_health has no unique constraint on (user_id, recorded_at).
-- Without dedup, repeated backfills would create duplicate rows and skew downstream
-- aggregations. iOS pre-fetches the set of minutes-with-data, then only uploads
-- strap records whose minute is NOT already covered.
--
-- Returns: list of unix-epoch seconds, one per minute that has ≥1 row.
-- For a 72h window with sparse coverage this is ≤4320 rows, tiny payload.

CREATE OR REPLACE FUNCTION minutes_with_realtime_data(
  p_user_id uuid,
  p_since   timestamptz,
  p_until   timestamptz
)
RETURNS TABLE(minute_epoch bigint)
LANGUAGE sql STABLE AS $$
  SELECT DISTINCT (extract(epoch FROM date_trunc('minute', recorded_at)))::bigint
  FROM realtime_health
  WHERE user_id = p_user_id
    AND recorded_at >= p_since
    AND recorded_at <  p_until
  ORDER BY 1;
$$;

COMMENT ON FUNCTION minutes_with_realtime_data IS
'Returns unix-second-epochs of minutes with at least one realtime_health row.
Used by manual 72h backfill to skip minutes that already have data.';
