# Lucid Health

**One person's body-state engine.** An iOS app, a set of serverless endpoints, and a Bluetooth bridge that reads a Whoop 4.0 strap directly over its private GATT protocol. Heart rate, RR intervals, HRV and sleep land in Postgres. A nightly job then runs t-tests, ANOVA and effect-size correlation across months of that data to work out which patterns actually hold up and which are noise.

> Personal engine, not a product. The recovery formula, the pattern thresholds and the interpreter's voice are all tuned to a single body over months of readings. Fork it, point it at your own Supabase and Apple ID, and expect to retune everything. It is not supported.

---

## What's inside

```
ios/                         SwiftUI iOS 26+ app, thin client
api/hermes/                  Vercel serverless TS endpoints
  ├── daily.ts               Nightly correlation engine (pg_cron triggered)
  ├── now.ts                 On-demand "what's my body doing right now"
  ├── chat.ts                Conversational interpreter (Gemini 2.5 Flash)
  ├── patterns.ts            Pattern CRUD
  └── _auth.ts               Shared auth (secret / cron / user JWT)
supabase/migrations/         Schema + server-side health algorithms (Postgres)
scripts/                     Python Whoop BLE bridge (bleak)
.github/workflows/build.yml  iOS build + AltStore source update + IPA upload
public/altstore-source.json  AltStore subscription source (template)
```

## How it actually works

```
┌─────────────────────────────────────────────────────────────┐
│  Whoop 4.0 strap (BLE peripheral, private GATT protocol)    │
└──────────────────────┬──────────────────────────────────────┘
                       │ BLE GATT notifications (HR, RR, type47 packets)
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  iOS app, BLEManager.swift                                  │
│  Listens for HR/RR notifications, computes HRV (RMSSD,      │
│  SDNN, pNN50, Poincaré), upserts to realtime_health table   │
│  every 10s. No algorithm code on device.                    │
└──────────────────────┬──────────────────────────────────────┘
                       │ Supabase REST (anon key, JWT auth)
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  Supabase (Postgres + pg_cron + Vercel edge functions)      │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ pg_recompute(uuid, date), server-side scoring        │   │
│  │   recovery_score, strain_score, sleep_score,         │   │
│  │   readiness_score, cognitive_capacity, illness_risk  │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ Hermes correlation engine (api/hermes/daily.ts)      │   │
│  │   Runs nightly. Pearson r, t-test (Welch's d),       │   │
│  │   ANOVA (η²), seasonal stratification.               │   │
│  │   Writes to hermes_pattern_matches.                  │   │
│  └──────────────────────────────────────────────────────┘   │
└──────────────────────┬──────────────────────────────────────┘
                       │ iOS reads computed values + pattern matches
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  HermesCard on TodayView, what your body's doing right now  │
└─────────────────────────────────────────────────────────────┘
```

The design constraint worth naming: no scoring logic runs on the phone. The app is a sensor client and a renderer. Every score, every correlation and every pattern match is computed in Postgres or in a serverless function, so the algorithm can change without shipping a new build through a sideload channel that takes hours to propagate.

## Setup (if you actually want to run this)

### 1. Your own Supabase

Self-host (Coolify/Hetzner) or Supabase Cloud, either works.

```bash
# 1. Run migrations in order (find/replace YOUR_USER_ID_HERE and YOUR_SUPABASE_URL_HERE first)
psql $DATABASE_URL -f supabase/migrations/supabase-migration-v29.sql
psql $DATABASE_URL -f supabase/migrations/supabase-migration-v37.sql
# ... etc up to v101

# 2. Create your user via Supabase Auth (email + password)
# 3. Note your auth.users.id, that's HERMES_USER_ID below
```

### 2. Deploy Hermes API to Vercel

```bash
vercel deploy api/hermes/
```

Vercel env vars required:
- `HERMES_USER_ID` your auth.users.id
- `HERMES_TRIGGER_SECRET` random string, used for manual /now and /daily triggers
- `VITE_SUPABASE_URL` `https://your-project.supabase.co`
- `VITE_SUPABASE_ANON_KEY` Supabase anon key
- `SUPABASE_SERVICE_ROLE_KEY` Supabase service role key (server only)
- `GOOGLE_AI_API_KEY` Gemini API key (free tier at https://aistudio.google.com)

Vercel cron auto-runs `/api/hermes/daily` once per day at 06:00 UTC.

### 3. Build iOS app via GitHub Actions

Fork this repo, then set:

**Repo secrets** (Settings → Secrets → Actions):
- `EE_TASKS_EMAIL` Supabase auth email
- `EE_TASKS_PASSWORD` Supabase auth password
- `SUPABASE_ANON_KEY` anon key (gets baked into the iOS binary)
- `SUPABASE_SERVICE_KEY` service key (used by workflow to upload IPA to your storage)
- `HERMES_USER_ID` your auth.users.id
- `GOOGLE_AI_API_KEY` for on-device Gemini calls

**Repo variables** (Settings → Variables → Actions):
- `SUPABASE_URL` `https://your-project.supabase.co`
- `SUPABASE_STORAGE_PUBLIC_BASE` `https://your-project.supabase.co/storage/v1/object/public/ipa-builds`
- `SUPABASE_STORAGE_WRITE_BASE` `https://your-project.supabase.co/storage/v1/object/ipa-builds`

Push to `main` and GHA builds an unsigned IPA on a `macos-15` runner (free for public repos), uploads it to your Supabase storage bucket, then updates `altstore-source.json`.

### 4. Sideload via AltStore PAL

Add `https://your-project.supabase.co/storage/v1/object/public/ipa-builds/altstore-source.json` as a source in AltStore PAL. Install Lucid Health. Done.

### 5. (Optional) The Whoop BLE bridge

The Python scripts in `scripts/` are diagnostic. They were used while working out the strap's BLE protocol. The real bridge runs inside the iOS app now, see `BLEManager.swift`.

```bash
pip install bleak
python scripts/whoop-scan-test.py    # find your strap
python scripts/whoop-connect-test.py # subscribe to HR notifications
```

The protocol work has since been pulled out into a standalone, tested Swift package: [whoop-ble-swift](https://github.com/Fabi-SPL/whoop-ble-swift). If you only want the framing, checksums and sensor decoders, start there instead.

## The voice

Hermes, the body-state interpreter, is deliberately not a wellness app. The system prompt and UI copy are tuned away from generic positivity toward observation-first, hypothesis-driven language. If you fork it, you will want to rewrite the prompt in your own register. Search `HERMES_SYSTEM_PROMPT` in `api/hermes/now.ts` and `api/hermes/chat.ts`.

## What's intentionally missing

- **No commercial features.** No multi-user auth, no billing, no onboarding, no marketplace.
- **No App Store distribution.** Sideload only, via AltStore PAL on EU iOS or AltStore Classic elsewhere.
- **Not supported.** No roadmap, no issue triage. Fork it and own it.
- **No automated test suite.** Correctness was checked against months of recorded readings from one body rather than against fixtures. That is workable for a personal tool and would not pass in production, which is why the reusable half of the BLE layer was extracted into [whoop-ble-swift](https://github.com/Fabi-SPL/whoop-ble-swift) and given a real test suite.
- **Personal thresholds baked in.** The recovery formula, the pattern thresholds and the voice samples all reflect one person's data. Forking means retuning.

## Stack

- **iOS:** Swift 6, SwiftUI, iOS 26+ minimum (Live Activities, frequent updates, WidgetKit)
- **Server:** Vercel serverless TypeScript, Supabase Postgres, pgvector, pg_cron, Gemini 2.5 Flash
- **BLE:** CoreBluetooth on iOS, bleak in Python for diagnostics
- **Sideload:** AltStore PAL or AltStore Classic, no Apple Developer Program enrollment required

## License

MIT, see [LICENSE](./LICENSE). No warranty, no medical advice, not a medical device. If your body is doing something weird, see a doctor.
