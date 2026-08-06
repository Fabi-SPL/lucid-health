-- v158 — Get Gemini working again. The vault has been undecryptable for months.
--
-- 2026-08-06: analyze_food_text() and analyze_food_photo() were both throwing
--   pgsodium_derive_helper: pgsodium_derive: no server secret key defined
-- because vault.decrypted_secrets calls pgsodium, and `select count(*) from
-- pg_extension where extname='pgsodium'` returns 0. The extension is gone, so
-- the encrypted gemini_api_key blob written 2026-06-10 can never be read again.
--
-- Every Gemini path in the app has been silently falling back ever since:
--   - typed food entries stored grams:0 / nova_class:0 / no protein at all
--     (the Bratwurst entry on Aug 4, the chicken+rice entry on Aug 5)
--   - daily_insights ran 774/775 on the template fallback
-- The app never surfaced any of it, because the client swallows the RPC error
-- and quietly uses its dumb local estimator.
--
-- Fix: stop depending on pgsodium. Single-user self-hosted DB, so a private
-- schema the API roles cannot see is enough. The secret VALUE is not in this
-- file and must never be — this repo is public. Insert it out-of-band:
--   select private.set_secret('gemini_api_key','<key>');

CREATE SCHEMA IF NOT EXISTS private;

REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS private.app_secrets (
  name        text PRIMARY KEY,
  value       text NOT NULL,
  updated_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE private.app_secrets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.app_secrets FROM PUBLIC, anon, authenticated;

-- Writer. SECURITY DEFINER so it works without granting anyone table access.
CREATE OR REPLACE FUNCTION private.set_secret(p_name text, p_value text)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'private','pg_temp'
AS $function$
  INSERT INTO private.app_secrets (name, value, updated_at)
  VALUES (p_name, p_value, now())
  ON CONFLICT (name) DO UPDATE SET value = excluded.value, updated_at = now();
$function$;

REVOKE ALL ON FUNCTION private.set_secret(text, text) FROM PUBLIC, anon, authenticated;

-- Reader. Prefers the new store, falls back to the vault so this is reversible
-- if pgsodium is ever reinstalled.
CREATE OR REPLACE FUNCTION private.get_secret(p_name text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'private','vault','extensions','pg_temp'
AS $function$
DECLARE v text;
BEGIN
  SELECT value INTO v FROM private.app_secrets WHERE name = p_name;
  IF v IS NOT NULL THEN RETURN v; END IF;
  BEGIN
    SELECT decrypted_secret INTO v FROM vault.decrypted_secrets WHERE name = p_name LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v := NULL;  -- vault unreadable (no pgsodium); treat as absent
  END;
  RETURN v;
END $function$;

REVOKE ALL ON FUNCTION private.get_secret(text) FROM PUBLIC, anon, authenticated;

-- Rewired proxy. Same signature, same behaviour, readable key source.
-- Also logs failures to bridge_logs — the old version raised into the void and
-- the client hid it, which is why a months-long outage went unnoticed.
CREATE OR REPLACE FUNCTION public._gemini_generate(p_body jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','private','extensions'
SET statement_timeout TO '60s'
AS $function$
DECLARE v_key text; v_url text; v_status int; v_content text;
BEGIN
  v_key := private.get_secret('gemini_api_key');
  IF v_key IS NULL OR v_key = '' THEN
    INSERT INTO bridge_logs (user_id, source, category, value, content)
    VALUES (auth.uid(), 'server', 'gemini_error', 'no_key',
            'gemini_api_key missing from private.app_secrets and vault');
    RAISE EXCEPTION 'gemini_api_key unavailable';
  END IF;

  v_url := 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=' || v_key;
  PERFORM extensions.http_set_curlopt('CURLOPT_TIMEOUT','55');
  SELECT status, content INTO v_status, v_content
  FROM extensions.http_post(v_url, p_body::text, 'application/json');

  IF v_status >= 300 THEN
    -- never log v_url, it carries the key
    INSERT INTO bridge_logs (user_id, source, category, value, content)
    VALUES (auth.uid(), 'server', 'gemini_error', 'http_' || v_status,
            'http ' || v_status || ' : ' || left(coalesce(v_content,''), 300));
    RAISE EXCEPTION 'gemini http % : %', v_status, left(coalesce(v_content,''),400);
  END IF;

  RETURN v_content::jsonb;
END $function$;
