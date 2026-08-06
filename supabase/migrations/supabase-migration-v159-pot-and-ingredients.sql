-- v159 — The pot. Weigh once at the stove, then eat fractions of a known total.
--
-- 2026-08-06, Fabi describing how he actually cooks: "I cooked half a kilo of
-- chicken breast and one cup of rice, mixed it together, ate roundabout 50%
-- last night and roundabout 50% today."
--
-- That is not a logging problem, it is the most accurate method available.
-- Once a dish is stirred you CANNOT weigh it back into components, but you do
-- not need to: the ratio is uniform, so a fraction of a weighed total beats an
-- absolute gram guess every time. One weighing event covers 2-4 meals.
--
-- It also kills the question that was bothering him — which brand of noodles,
-- which cheese, which ham. You weigh grams of an ingredient, not a package of
-- a brand. Chicken breast is 100-113 kcal/100 g across every German brand;
-- that 3% spread is noise next to the 28% portion guess it replaces.
--
-- Two pieces:
--   food_ingredients — ONE canonical row per thing Fabi actually eats. Not a
--     food database. His numbers, decided once, never re-estimated. This is a
--     single-user app; hardcoding is the feature.
--   food_batches — a cooked pot with computed totals and a remaining fraction.
--
-- Portions are stored as RAW/DRY weight where that is how you weigh it
-- (chicken before the pan, rice before the water). Calories and protein are
-- conserved through cooking; water is not. Weighing raw is both easier and
-- more accurate than guessing at a cooked weight.

-- ---------------------------------------------------------------- ingredients

CREATE TABLE IF NOT EXISTS public.food_ingredients (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  key           text NOT NULL,
  name          text NOT NULL,
  name_local    text,
  kcal_100      numeric NOT NULL,
  protein_100   numeric NOT NULL DEFAULT 0,
  fat_100       numeric NOT NULL DEFAULT 0,
  carbs_100     numeric NOT NULL DEFAULT 0,
  alcohol_100   numeric NOT NULL DEFAULT 0,
  nova_class    smallint NOT NULL DEFAULT 1,
  mind_tags     text[] NOT NULL DEFAULT '{}',
  default_grams numeric,
  unit_hint     text,
  weight_basis  text NOT NULL DEFAULT 'raw',   -- raw | dry | ready | liquid
  times_used    integer NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, key)
);

ALTER TABLE public.food_ingredients ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS food_ingredients_own ON public.food_ingredients;
CREATE POLICY food_ingredients_own ON public.food_ingredients
  FOR ALL USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS food_ingredients_user_used_idx
  ON public.food_ingredients (user_id, times_used DESC);

-- --------------------------------------------------------------------- pot

CREATE TABLE IF NOT EXISTS public.food_batches (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name           text NOT NULL,
  emoji          text,
  cooked_at      timestamptz NOT NULL DEFAULT now(),
  items          jsonb NOT NULL,            -- [{key,name,grams,kcal,protein_g,fat_g,carbs_g,nova_class,mind_tags}]
  total_kcal     numeric NOT NULL DEFAULT 0,
  total_protein  numeric NOT NULL DEFAULT 0,
  total_fat      numeric NOT NULL DEFAULT 0,
  total_carbs    numeric NOT NULL DEFAULT 0,
  nova_avg       numeric,
  remaining      numeric NOT NULL DEFAULT 1.0,   -- 1.0 = full pot, 0 = eaten
  status         text NOT NULL DEFAULT 'open',   -- open | finished | discarded
  created_at     timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.food_batches ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS food_batches_own ON public.food_batches;
CREATE POLICY food_batches_own ON public.food_batches
  FOR ALL USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS food_batches_open_idx
  ON public.food_batches (user_id, status, cooked_at DESC);

-- Link servings back to the pot they came from, so "how much is left" and
-- "what did this meal actually contain" stay answerable after the fact.
ALTER TABLE public.food_entries
  ADD COLUMN IF NOT EXISTS batch_id       uuid REFERENCES public.food_batches(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS batch_fraction numeric;

-- ------------------------------------------------------------------- create

-- p_items: [{"key":"chicken_breast","grams":500}, {"key":"rice_white","grams":185}]
CREATE OR REPLACE FUNCTION public.food_batch_create(
  p_name   text,
  p_items  jsonb,
  p_emoji  text DEFAULT NULL,
  p_cooked_at timestamptz DEFAULT now()
)
RETURNS public.food_batches
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_items jsonb := '[]'::jsonb;
  v_kcal numeric := 0; v_pro numeric := 0; v_fat numeric := 0; v_carb numeric := 0;
  v_nova_num numeric := 0; v_nova_den numeric := 0;
  r record; g numeric; ing record;
  v_row public.food_batches;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'no auth.uid()'; END IF;

  FOR r IN SELECT * FROM jsonb_array_elements(p_items) e(v) LOOP
    g := (r.v->>'grams')::numeric;
    SELECT * INTO ing FROM food_ingredients
     WHERE user_id = v_uid AND key = (r.v->>'key');
    IF NOT FOUND THEN
      RAISE EXCEPTION 'unknown ingredient key: %', (r.v->>'key');
    END IF;

    v_items := v_items || jsonb_build_object(
      'key',        ing.key,
      'name',       ing.name,
      'name_local', ing.name_local,
      'grams',      g,
      'kcal',       round(ing.kcal_100    * g / 100, 1),
      'protein_g',  round(ing.protein_100 * g / 100, 1),
      'fat_g',      round(ing.fat_100     * g / 100, 1),
      'carbs_g',    round(ing.carbs_100   * g / 100, 1),
      'alcohol_g',  round(ing.alcohol_100 * g / 100, 1),
      'nova_class', ing.nova_class,
      'mind_tags',  to_jsonb(ing.mind_tags),
      'is_alcohol', ing.alcohol_100 > 0
    );

    v_kcal := v_kcal + ing.kcal_100    * g / 100;
    v_pro  := v_pro  + ing.protein_100 * g / 100;
    v_fat  := v_fat  + ing.fat_100     * g / 100;
    v_carb := v_carb + ing.carbs_100   * g / 100;
    -- weight NOVA by calories, not by grams: 10 g of oil should not count the
    -- same as 500 g of chicken
    v_nova_num := v_nova_num + ing.nova_class * (ing.kcal_100 * g / 100);
    v_nova_den := v_nova_den + (ing.kcal_100 * g / 100);

    UPDATE food_ingredients SET times_used = times_used + 1 WHERE id = ing.id;
  END LOOP;

  INSERT INTO food_batches (user_id, name, emoji, cooked_at, items,
                            total_kcal, total_protein, total_fat, total_carbs, nova_avg)
  VALUES (v_uid, p_name, p_emoji, p_cooked_at, v_items,
          round(v_kcal), round(v_pro,1), round(v_fat,1), round(v_carb,1),
          CASE WHEN v_nova_den > 0 THEN round(v_nova_num / v_nova_den, 2) END)
  RETURNING * INTO v_row;

  RETURN v_row;
END $function$;

-- -------------------------------------------------------------------- serve

-- Eat a fraction of the pot. 0.5 = half. Writes a normal food_entries row so
-- every existing surface (cut_status, correlations, the Food tab) sees it
-- without knowing batches exist.
CREATE OR REPLACE FUNCTION public.food_batch_serve(
  p_batch_id   uuid,
  p_fraction   numeric,
  p_captured_at timestamptz DEFAULT now()
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  b public.food_batches;
  v_items jsonb;
  v_entry uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'no auth.uid()'; END IF;
  IF p_fraction IS NULL OR p_fraction <= 0 THEN RAISE EXCEPTION 'fraction must be > 0'; END IF;

  SELECT * INTO b FROM food_batches WHERE id = p_batch_id AND user_id = v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'batch not found'; END IF;

  SELECT jsonb_agg(
           it || jsonb_build_object(
             'grams',     round((it->>'grams')::numeric     * p_fraction, 1),
             'kcal',      round((it->>'kcal')::numeric      * p_fraction, 1),
             'protein_g', round((it->>'protein_g')::numeric * p_fraction, 1),
             'fat_g',     round((it->>'fat_g')::numeric     * p_fraction, 1),
             'carbs_g',   round((it->>'carbs_g')::numeric   * p_fraction, 1),
             'alcohol_g', round(coalesce((it->>'alcohol_g')::numeric,0) * p_fraction, 1)
           ))
    INTO v_items
    FROM jsonb_array_elements(b.items) x(it);

  INSERT INTO food_entries (user_id, captured_at, items, total_kcal, nova_avg,
                            caption, source, confidence, portion_size,
                            batch_id, batch_fraction)
  VALUES (v_uid, p_captured_at, v_items,
          round(b.total_kcal * p_fraction), b.nova_avg,
          b.name || ' — ' || round(p_fraction * 100) || '% of the pot',
          'batch', 'weighed_batch', 'normal',
          b.id, p_fraction)
  RETURNING id INTO v_entry;

  UPDATE food_batches
     SET remaining = greatest(0, remaining - p_fraction),
         status = CASE WHEN greatest(0, remaining - p_fraction) <= 0.02
                       THEN 'finished' ELSE status END
   WHERE id = b.id;

  RETURN v_entry;
END $function$;

-- Whatever is left in the pot, in one call — for a "finish it" button.
CREATE OR REPLACE FUNCTION public.food_batch_finish(p_batch_id uuid, p_captured_at timestamptz DEFAULT now())
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_rem numeric;
BEGIN
  SELECT remaining INTO v_rem FROM food_batches WHERE id = p_batch_id AND user_id = auth.uid();
  IF v_rem IS NULL OR v_rem <= 0 THEN RAISE EXCEPTION 'nothing left in this pot'; END IF;
  RETURN public.food_batch_serve(p_batch_id, v_rem, p_captured_at);
END $function$;

-- Open pots, for the logging screen.
CREATE OR REPLACE FUNCTION public.food_batches_open(p_user_id uuid DEFAULT NULL)
RETURNS TABLE (
  id uuid, name text, emoji text, cooked_at timestamptz,
  remaining numeric, total_kcal numeric, total_protein numeric,
  left_kcal numeric, left_protein numeric, items jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
  SELECT b.id, b.name, b.emoji, b.cooked_at, b.remaining,
         b.total_kcal, b.total_protein,
         round(b.total_kcal    * b.remaining) AS left_kcal,
         round(b.total_protein * b.remaining, 1) AS left_protein,
         b.items
  FROM food_batches b
  WHERE b.user_id = coalesce(p_user_id, auth.uid())
    AND b.status = 'open'
    AND b.remaining > 0.02
  ORDER BY b.cooked_at DESC;
$function$;

GRANT EXECUTE ON FUNCTION public.food_batch_create(text, jsonb, text, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.food_batch_serve(uuid, numeric, timestamptz)      TO authenticated;
GRANT EXECUTE ON FUNCTION public.food_batch_finish(uuid, timestamptz)              TO authenticated;
GRANT EXECUTE ON FUNCTION public.food_batches_open(uuid)                           TO authenticated;
