-- v164 — Catch the same meal logged twice.
--
-- 2026-08-06 has chicken+rice at 14:29 (favorite tap, 660 kcal) and again at
-- 14:50 (pot serving, 672 kcal). One meal, counted twice, 660 kcal of phantom
-- intake on a day with a 1620 target. That is 40% of a day's budget invented
-- by a double tap.
--
-- Same shape as the v161 supplement guard, with one deliberate difference:
-- supplements are identical-by-name so we can silently return the existing id.
-- Meals are not — two genuinely different 600 kcal meals 20 minutes apart is
-- rare but real (a snack chased by lunch). So this does NOT block the insert.
-- It records the suspicion on the row and lets the surfaces decide.
--
-- What counts as suspicious: same user, within 30 minutes, and total_kcal
-- within 15% of each other. Tight enough that a coffee never shadows a meal.

ALTER TABLE public.food_entries
  ADD COLUMN IF NOT EXISTS possible_dup_of uuid REFERENCES public.food_entries(id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION public.food_entry_dup_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_prev uuid;
  v_prev_kcal int;
BEGIN
  -- Nothing to compare against, and drinks/supplements are legitimately
  -- repeated (three espressos in a morning is not a double-log).
  IF NEW.total_kcal IS NULL OR NEW.total_kcal < 150 THEN
    RETURN NEW;
  END IF;

  SELECT e.id, e.total_kcal
    INTO v_prev, v_prev_kcal
    FROM food_entries e
   WHERE e.user_id = NEW.user_id
     AND e.id IS DISTINCT FROM NEW.id
     AND e.captured_at BETWEEN NEW.captured_at - interval '30 minutes'
                           AND NEW.captured_at + interval '30 minutes'
     AND e.total_kcal IS NOT NULL
     AND abs(e.total_kcal - NEW.total_kcal) <= greatest(60, NEW.total_kcal * 0.15)
   ORDER BY abs(extract(epoch FROM (e.captured_at - NEW.captured_at)))
   LIMIT 1;

  IF v_prev IS NOT NULL THEN
    NEW.possible_dup_of := v_prev;
    INSERT INTO bridge_logs (user_id, source, category, value, content)
    VALUES (NEW.user_id, 'server', 'meal_dup_suspect', v_prev::text,
            'possible double-log: ' || NEW.total_kcal || ' kcal near an existing '
            || v_prev_kcal || ' kcal entry within 30 min');
  END IF;

  RETURN NEW;
END $function$;

DROP TRIGGER IF EXISTS food_entry_dup_guard_trg ON public.food_entries;
CREATE TRIGGER food_entry_dup_guard_trg
  BEFORE INSERT ON public.food_entries
  FOR EACH ROW EXECUTE FUNCTION public.food_entry_dup_guard();

-- Read-side helper so a surface can ask "did I double-log today?" without
-- shipping an app build to hold the logic.
CREATE OR REPLACE FUNCTION public.food_dup_suspects(p_user_id uuid DEFAULT NULL, p_date date DEFAULT NULL)
RETURNS TABLE (
  id uuid, captured_at timestamptz, caption text, total_kcal int,
  dup_of uuid, dup_caption text, dup_kcal int
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
  SELECT e.id, e.captured_at, e.caption, e.total_kcal,
         p.id, p.caption, p.total_kcal
    FROM food_entries e
    JOIN food_entries p ON p.id = e.possible_dup_of
   WHERE e.user_id = coalesce(p_user_id, auth.uid())
     AND (e.captured_at AT TIME ZONE 'Europe/Berlin')::date
         = coalesce(p_date, (now() AT TIME ZONE 'Europe/Berlin')::date)
   ORDER BY e.captured_at DESC;
$function$;

GRANT EXECUTE ON FUNCTION public.food_dup_suspects(uuid, date) TO authenticated;
