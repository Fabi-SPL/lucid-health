-- v70 — Whoop type-47 decoded float capture
--
-- Today's harvest revealed packet type 47 (93-byte "decode_5c" full sensor frame)
-- arriving in bursts after BLE reconnect. Byte-variance analysis confirmed 60 bytes
-- of dynamic signal data at offsets [26..85] — likely 15 × IEEE-754 floats carrying
-- accelerometer / gyro / PPG channel readings.
--
-- This migration extends whoop_realtime_raw so the same table holds both type-40
-- (abbreviated HR packets, 17 bytes) and type-47 (full sensor packets, 93 bytes).
-- Adds columns for packet_type discrimination + decoded float array.

alter table public.whoop_realtime_raw
    add column if not exists packet_type     int,
    add column if not exists seq             int,
    add column if not exists counter         int,
    add column if not exists timestamp_unix  bigint,
    add column if not exists timestamp_frac  bigint,
    add column if not exists parsed_floats   jsonb;

create index if not exists idx_wrr_packet_type
    on public.whoop_realtime_raw (user_id, packet_type, recorded_at desc);

-- Variance view for the decoded floats — reveals which of the 15 channels are
-- dynamic (real signal) vs constant (padding / reserved).
create or replace view public.whoop_type47_float_variance as
with expanded as (
    select
        user_id,
        jsonb_array_elements(parsed_floats)::text::float as val,
        (row_number() over (partition by id order by id) - 1)::int as channel_idx
    from public.whoop_realtime_raw
    where packet_type = 47 and parsed_floats is not null
)
select
    user_id,
    channel_idx,
    count(*)                       as sample_count,
    min(val)                       as min_val,
    max(val)                       as max_val,
    avg(val)                       as avg_val,
    stddev(val)                    as stddev_val
from expanded
group by user_id, channel_idx
order by stddev_val desc nulls last;

comment on view public.whoop_type47_float_variance is
    'Per-channel statistics of decoded type-47 floats. High stddev = real signal, low stddev = constant/padding.';
