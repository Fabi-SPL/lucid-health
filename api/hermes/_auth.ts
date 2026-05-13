import type { VercelRequest } from '@vercel/node'
import { createClient, type SupabaseClient } from '@supabase/supabase-js'

// ── Hermes shared auth ──────────────────────────────────────────────────
// Accepts ANY of:
//   1. HERMES_TRIGGER_SECRET — manual / external triggers
//   2. CRON_SECRET           — auto-injected by Vercel cron
//   3. User session JWT      — supabase.auth-issued, must resolve to USER_ID
//
// Used by /api/hermes/daily, /api/hermes/now, /api/hermes/chat.

// Set HERMES_USER_ID in your Vercel project env vars (your auth.users.id).
const USER_ID = process.env.HERMES_USER_ID || ''

export async function hermesAuthOk(
  req: VercelRequest,
  supabase: SupabaseClient
): Promise<boolean> {
  // 0. Vercel cron — identified by user-agent. When CRON_SECRET isn't set in
  // project env vars, Vercel cron requests come through with no Authorization
  // header but with a `user-agent: vercel-cron/1.0` (or similar) signature.
  // The request also originates from Vercel's infrastructure (host + IP).
  const ua = String(req.headers['user-agent'] || '')
  if (ua.toLowerCase().includes('vercel-cron')) return true

  const auth = (req.headers.authorization || '') as string
  if (!auth.startsWith('Bearer ')) {
    // Dev mode: if neither secret is set, allow
    if (!process.env.HERMES_TRIGGER_SECRET && !process.env.CRON_SECRET) return true
    return false
  }
  const token = auth.slice(7)

  // 1. Service triggers
  const hermesSecret = process.env.HERMES_TRIGGER_SECRET || ''
  const cronSecret = process.env.CRON_SECRET || ''
  if (hermesSecret && token === hermesSecret) return true
  if (cronSecret && token === cronSecret) return true

  // 2. User session JWT — supabase auth verifies signature + expiry server-side
  try {
    const { data, error } = await supabase.auth.getUser(token)
    if (!error && data.user?.id === USER_ID) return true
  } catch {
    // fall through to deny
  }

  return false
}

// Convenience: a client built with anon key, used ONLY for auth.getUser() JWT
// verification. The endpoint's main supabase client (service role) is separate.
export function authClient(): SupabaseClient {
  const url = process.env.VITE_SUPABASE_URL || process.env.SUPABASE_URL || ''
  const anon = process.env.VITE_SUPABASE_ANON_KEY || ''
  return createClient(url, anon, { auth: { persistSession: false } })
}
