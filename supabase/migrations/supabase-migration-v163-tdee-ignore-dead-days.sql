-- v163 — Stop reading "the strap was off" as "you did nothing."
--
-- cut_status projects today's active burn from the trailing 7-day average.
-- That average included days with NO biometric data at all, which
-- body_daily_calories reports as active_kcal = 0. Aug 1 and Aug 2 2026 were
-- both BLE outages, and they dragged the 7-day mean from 467 down to 333.
-- Result: today's target came out 1486 instead of ~1620, so a day that was
-- actually on plan reads as 130 kcal over.
--
-- Missing data is not evidence of rest. Average only the days that actually
-- recorded something, and fall back to the raw mean if every day is dead
-- (better a low estimate than a division by nothing).
--
-- Everything else about the function is unchanged.

CREATE OR REPLACE FUNCTION public.cut_status(
  p_user_id uuid,
  p_date date DEFAULT ((now() AT TIME ZONE 'Europe/Berlin'::text))::date
)
RETURNS TABLE (
  tdee int, bmr int, active_kcal int,
  deficit_target int, target_intake int,
  consumed int, remaining int,
  protein_g numeric, protein_target int,
  n_meals int, last_meal_at timestamptz,
  headline text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  c record; p record; f record; v_active int; v_live int;
BEGIN
  SELECT * INTO c FROM body_daily_calories(p_user_id, p_date);
  SELECT COALESCE(cut_deficit_kcal, 0) AS def, COALESCE(protein_target_g, 0) AS prot
    INTO p FROM user_body_profile WHERE user_id = p_user_id;

  -- body_daily_calories only knows strain accrued SO FAR. Using it raw mid-morning
  -- yields a near-BMR TDEE and an absurdly low target. Project the rest of the day
  -- from the trailing 7-day active average, ratcheting up if today already beat it.
  --
  -- v163: days with zero active_kcal are almost always days the strap was not
  -- recording, not days he lay still for 24h. Exclude them from the mean.
  IF p_date = (now() AT TIME ZONE 'Europe/Berlin')::date THEN
    SELECT count(*) FILTER (WHERE x.active_kcal > 0),
           GREATEST(
             c.active_kcal,
             COALESCE(round(avg(x.active_kcal) FILTER (WHERE x.active_kcal > 0)), 0)
           )
      INTO v_live, v_active
      FROM generate_series(p_date - 7, p_date - 1, '1 day') d
      CROSS JOIN LATERAL body_daily_calories(p_user_id, d::date) x;

    -- Every one of the last 7 days was dead. Nothing to project from; keep
    -- whatever today has actually accrued rather than inventing a number.
    IF v_live = 0 THEN
      v_active := c.active_kcal;
    END IF;
  ELSE
    v_active := c.active_kcal;
  END IF;

  -- kcal lives on the entry, protein lives inside items — summing both across one
  -- lateral join fans the entry total out once per item (215 kcal became 645).
  SELECT COALESCE((SELECT sum(total_kcal) FROM food_entries
                    WHERE user_id = p_user_id
                      AND (captured_at AT TIME ZONE 'Europe/Berlin')::date = p_date), 0)::int AS kcal,
         COALESCE((SELECT sum((i->>'protein_g')::numeric)
                     FROM food_entries fe, jsonb_array_elements(fe.items) i
                    WHERE fe.user_id = p_user_id
                      AND (fe.captured_at AT TIME ZONE 'Europe/Berlin')::date = p_date), 0) AS prot,
         COALESCE((SELECT count(*) FROM food_entries
                    WHERE user_id = p_user_id
                      AND (captured_at AT TIME ZONE 'Europe/Berlin')::date = p_date), 0)::int AS n,
         (SELECT max(captured_at) FROM food_entries
           WHERE user_id = p_user_id
             AND (captured_at AT TIME ZONE 'Europe/Berlin')::date = p_date) AS last_at
    INTO f;

  bmr := c.bmr;
  active_kcal := v_active;
  tdee := c.bmr + v_active;
  deficit_target := p.def;
  target_intake  := GREATEST(tdee - p.def, 1200);   -- never coach below 1200
  consumed       := f.kcal;
  remaining      := target_intake - f.kcal;
  protein_g      := round(f.prot, 1);
  protein_target := p.prot;
  n_meals        := f.n;
  last_meal_at   := f.last_at;

  headline := CASE
    WHEN n_meals = 0            THEN 'Nothing logged yet'
    WHEN remaining < -300       THEN 'Over by ' || abs(remaining) || ' — tomorrow resets it'
    WHEN remaining < 0          THEN 'Just over, ' || abs(remaining) || ' — that is noise'
    WHEN remaining < 250        THEN remaining || ' left — basically done'
    ELSE                             remaining || ' left today'
  END;

  RETURN NEXT;
END $function$;

GRANT EXECUTE ON FUNCTION public.cut_status(uuid, date) TO authenticated;
