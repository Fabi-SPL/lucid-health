-- v66 — Whoop 4.0 full signal capture
-- Adds tables for IMU time-series + discrete strap events
-- so every available BLE signal ends up in Supabase.
-- Companion doc: C:/Users/ilgfa/Desktop/New Concepts/Whoop Data Audit/whoop-data-audit-2026-04-21.md

-- ============================================================
-- 1. whoop_events — discrete strap events
-- ============================================================
create table if not exists whoop_events (
    id           bigserial primary key,
    user_id      uuid not null references auth.users(id) on delete cascade,
    event_type   text not null,
    event_data   jsonb,
    raw_bytes    text,
    recorded_at  timestamptz not null default now(),
    source       text default 'whoop_ble'
);

create index if not exists whoop_events_user_date_idx on whoop_events(user_id, recorded_at desc);
create index if not exists whoop_events_type_idx on whoop_events(event_type);

alter table whoop_events enable row level security;
drop policy if exists whoop_events_owner on whoop_events;
create policy whoop_events_owner on whoop_events for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ============================================================
-- 2. whoop_imu — realtime IMU stream (accel + gyro)
-- Streaming 52 Hz is expensive → iOS decimates to ~1 Hz before push.
-- ============================================================
create table if not exists whoop_imu (
    id             bigserial primary key,
    user_id        uuid not null references auth.users(id) on delete cascade,
    recorded_at    timestamptz not null default now(),
    accel_x        smallint,
    accel_y        smallint,
    accel_z        smallint,
    gyro_x         smallint,
    gyro_y         smallint,
    gyro_z         smallint,
    accel_mag_mg   integer,
    movement_score real,
    sample_rate_hz smallint default 52
);

create index if not exists whoop_imu_user_time_idx on whoop_imu(user_id, recorded_at desc);

alter table whoop_imu enable row level security;
drop policy if exists whoop_imu_owner on whoop_imu;
create policy whoop_imu_owner on whoop_imu for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ============================================================
-- 3. realtime_health extensions
-- ============================================================
alter table realtime_health add column if not exists accel_mag_mg integer;
alter table realtime_health add column if not exists movement_score real;

-- ============================================================
-- 4. health_metrics extensions — device-state snapshots
-- ============================================================
alter table health_metrics add column if not exists firmware_version text;
alter table health_metrics add column if not exists battery_voltage_mv integer;
alter table health_metrics add column if not exists battery_cycle_count integer;
alter table health_metrics add column if not exists battery_state_of_health smallint;
alter table health_metrics add column if not exists wrist_side text check (wrist_side is null or wrist_side in ('left', 'right'));

-- ============================================================
-- 5. whoop_raw_optical — placeholder until type-43 format is decoded
-- ============================================================
create table if not exists whoop_raw_optical (
    id           bigserial primary key,
    user_id      uuid not null references auth.users(id) on delete cascade,
    recorded_at  timestamptz not null default now(),
    ppg_green1   integer,
    ppg_green2   integer,
    ppg_green3   integer,
    ppg_red      integer,
    ppg_ir       integer,
    raw_bytes    text
);

create index if not exists whoop_raw_optical_user_time_idx on whoop_raw_optical(user_id, recorded_at desc);

alter table whoop_raw_optical enable row level security;
drop policy if exists whoop_raw_optical_owner on whoop_raw_optical;
create policy whoop_raw_optical_owner on whoop_raw_optical for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Notes
comment on table whoop_events is 'Whoop 4.0 discrete strap events captured via BLE (migration v66). Companion audit doc on desktop.';
comment on table whoop_imu is 'Whoop 4.0 realtime IMU stream (migration v66). Decimated on-device from 52 Hz before push.';
comment on table whoop_raw_optical is 'Whoop 4.0 raw PPG frames via CMD 81 / type 43 (migration v66). Format pending RE sniff — raw_bytes stored for later re-parse.';
