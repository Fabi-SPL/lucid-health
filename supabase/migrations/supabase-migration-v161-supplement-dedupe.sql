-- v161 — Stop the same supplement landing five times in four seconds.
--
-- 2026-08-05 12:02:48.511 / .517 / .530 / .553 and 12:02:52.747 — five
-- identical "Creatine Monohydrate, 1 serving" rows. Four of them inside 42
-- milliseconds, which is not five decisions to take creatine, it is one tap
-- that fired repeatedly (retry, double-tap, or a re-render calling the RPC).
--
-- 25 g of creatine in the log when he took 5 g corrupts supplement_daily_actives
-- and any correlation that reads it. The client can be fixed later; the server
-- should not accept an obviously duplicate dose regardless of who is calling.
--
-- Behaviour: a same-user + same-name log within the window returns the EXISTING
-- id instead of inserting. Idempotent from the caller's point of view — the app
-- still gets a uuid back and shows its success state, so no client change is
-- needed to stop the corruption.
--
-- 5 minutes is chosen to be longer than any plausible retry storm and shorter
-- than a real second dose. Pass p_force := true for a deliberate second dose
-- inside the window (pre-workout on top of morning, say).

-- The new signature adds p_force, so CREATE OR REPLACE would OVERLOAD rather
-- than replace and PostgREST would then have two candidates to pick from.
-- Drop the 7-arg version explicitly first.
DROP FUNCTION IF EXISTS public.log_supplement(uuid, uuid, text, numeric, timestamptz, text, text);

CREATE OR REPLACE FUNCTION public.log_supplement(
  p_user_id    uuid,
  p_product_id uuid DEFAULT NULL::uuid,
  p_name       text DEFAULT NULL::text,
  p_servings   numeric DEFAULT 1,
  p_taken_at   timestamptz DEFAULT now(),
  p_source     text DEFAULT 'tap'::text,
  p_note       text DEFAULT NULL::text,
  p_force      boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_name text; v_actives jsonb := '{}'::jsonb; v_id uuid; v_dupe uuid;
  v_window constant interval := interval '5 minutes';
BEGIN
  IF p_product_id IS NOT NULL THEN
    SELECT name, actives INTO v_name, v_actives
      FROM supplement_products WHERE id = p_product_id AND user_id = p_user_id;
  END IF;
  v_name := COALESCE(p_name, v_name);
  IF v_name IS NULL THEN
    RAISE EXCEPTION 'log_supplement needs either a known product_id or a name';
  END IF;

  -- Same substance, same person, same few minutes → treat as the same tap.
  IF NOT p_force THEN
    SELECT id INTO v_dupe
      FROM supplement_log
     WHERE user_id = p_user_id
       AND lower(name) = lower(v_name)
       AND taken_at BETWEEN p_taken_at - v_window AND p_taken_at + v_window
     ORDER BY abs(extract(epoch FROM (taken_at - p_taken_at)))
     LIMIT 1;

    IF v_dupe IS NOT NULL THEN
      INSERT INTO bridge_logs (user_id, source, category, value, content)
      VALUES (p_user_id, 'server', 'supplement_dedupe', v_name,
              'suppressed duplicate ' || v_name || ' within ' || v_window::text);
      RETURN v_dupe;   -- caller sees success, log stays honest
    END IF;
  END IF;

  -- Freeze the dose at log time — if the bottle changes later, history stays true.
  SELECT COALESCE(jsonb_object_agg(k, round((val::numeric) * p_servings, 4)), '{}'::jsonb)
    INTO v_actives
    FROM jsonb_each_text(v_actives) AS t(k, val)
   WHERE val ~ '^[0-9]+(\.[0-9]+)?$';

  INSERT INTO supplement_log(user_id, product_id, name, servings, actives, taken_at, source, note)
  VALUES (p_user_id, p_product_id, v_name, p_servings, v_actives, p_taken_at, p_source, p_note)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$function$;
