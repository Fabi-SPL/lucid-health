-- v69 — Whoop Realtime Raw Payload Extraction
--
-- Every type-40 (REALTIME_DATA) packet from the strap carries ~92 bytes of data.
-- We currently only extract HR + RR intervals — bytes [33:52] (data0, 19 bytes)
-- and bytes [55:85] (data1, 30 bytes) remain undecoded. Community RE consensus:
-- these fields contain SpO2, respiration rate, and additional signals.
--
-- This table captures the full payload for offline correlation analysis, so we
-- can diff bytes across known states (rest vs exercise, awake vs asleep) and
-- reverse-engineer the layout from our own data.
--
-- Decimated on-device: every 6th HR packet (~1 row per minute at 10s HR rate).

create table if not exists public.whoop_realtime_raw (
    id              bigserial primary key,
    user_id         uuid references auth.users(id) on delete cascade,
    recorded_at     timestamptz not null default now(),
    -- Parsed fields (for easy analysis)
    hr              int,                -- heart rate in BPM (same as realtime_health.heart_rate)
    rr_count        int,                -- number of RR intervals in this packet
    rr_intervals_ms int[],              -- individual RR intervals in milliseconds
    -- Raw undecoded fields (the goldmine)
    data0_hex       text,               -- 19 bytes at packet.data[26..44] — likely SpO2 + resp
    data1_hex       text,               -- 30 bytes at packet.data[48..77] — likely more signals
    full_hex        text,               -- full packet.data for safety
    -- Context (for correlation)
    activity_state  text,               -- "resting" | "active" | "sleeping" | null
    external_hr     int                 -- optional HR reference from HealthKit / manual log
);

create index if not exists idx_wrr_user_time
    on public.whoop_realtime_raw (user_id, recorded_at desc);
create index if not exists idx_wrr_activity
    on public.whoop_realtime_raw (user_id, activity_state, recorded_at desc);

alter table public.whoop_realtime_raw enable row level security;

drop policy if exists "wrr_owner_all" on public.whoop_realtime_raw;
create policy "wrr_owner_all" on public.whoop_realtime_raw
    for all to authenticated
    using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Byte-variance view — show which byte offsets in data0 / data1 change across samples.
-- High variance = dynamic signal (candidate for SpO2/resp). Low variance = padding or constant.
create or replace view public.whoop_realtime_raw_variance as
with expanded as (
    select
        id,
        user_id,
        recorded_at,
        hr,
        -- One row per byte position in data0, tagged with offset
        generate_series(0, 18) as data0_offset,
        get_byte(decode(data0_hex, 'hex'), generate_series(0, 18)) as data0_byte
    from public.whoop_realtime_raw
    where data0_hex is not null and length(data0_hex) >= 38
)
select
    user_id,
    'data0' as field,
    data0_offset as byte_offset,
    count(*)      as sample_count,
    min(data0_byte)        as min_val,
    max(data0_byte)        as max_val,
    max(data0_byte) - min(data0_byte) as range_val,
    count(distinct data0_byte)        as distinct_vals
from expanded
group by user_id, data0_offset
order by range_val desc;

comment on table public.whoop_realtime_raw is
    'Full type-40 HR packet capture for RE — includes undecoded data0/data1 fields. Decimated ~1/min.';
comment on view public.whoop_realtime_raw_variance is
    'Per-byte variance of data0 across samples — high variance = candidate for a real signal.';
