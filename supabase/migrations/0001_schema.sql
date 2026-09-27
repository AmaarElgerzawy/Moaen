-- Moaen (معاين) — 0001_schema.sql
-- Remote car-inspection marketplace: types, tables, indexes, invariants.
-- Target: Supabase Postgres. Apply via `supabase db push`.

-- ============================================================================
-- Enumerated types
-- ============================================================================

create type public.user_role as enum ('client', 'inspector', 'admin');

create type public.inspection_status as enum (
  'pending',
  'accepted',
  'in_progress',
  'completed',
  'cancelled'
);

create type public.payment_status as enum ('escrow', 'released', 'refunded');

create type public.media_type as enum ('image', 'video');

-- ============================================================================
-- users — 1:1 with auth.users
--
-- `email` is a deliberate denormalisation of auth.users.email so that admin
-- listings and joins do not have to reach into the auth schema.
--
-- `location_city` is the inspector's service city. One value per inspector in
-- Phase 1; see PROJECT_MAP.md assumption A2.
-- ============================================================================

create table public.users (
  id            uuid primary key references auth.users (id) on delete cascade,
  full_name     text not null check (char_length(full_name) between 2 and 120),
  email         text not null,
  phone         text,
  role          public.user_role not null default 'client',
  avatar_url    text,
  location_city text,
  rating        numeric(3, 2) not null default 0 check (rating between 0 and 5),
  created_at    timestamptz not null default now()
);

-- Case-insensitive uniqueness without depending on the citext extension.
create unique index users_email_key on public.users (lower(email));

-- Serves the inspector job board: filter by role, then by city.
create index users_role_city_idx on public.users (role, location_city);

-- ============================================================================
-- car_inspections — aggregate root of the marketplace
--
-- Deletion policy: RESTRICT on both parties. A user who has taken part in an
-- inspection cannot be deleted, so inspection and payment history survives.
-- See PROJECT_MAP.md [ARCHITECTURE].
-- ============================================================================

create table public.car_inspections (
  id                      uuid primary key default gen_random_uuid(),
  client_id               uuid not null references public.users (id) on delete restrict,
  inspector_id            uuid references public.users (id) on delete restrict,
  car_make                text not null check (char_length(car_make) between 1 and 60),
  car_model               text not null check (char_length(car_model) between 1 and 60),
  car_year                smallint not null check (car_year between 1950 and 2100),
  seller_phone            text not null check (char_length(seller_phone) between 5 and 30),
  seller_location_address text not null check (char_length(seller_location_address) between 3 and 400),
  city                    text not null check (char_length(city) between 2 and 80),
  inspection_center_name  text,
  status                  public.inspection_status not null default 'pending',
  price                   numeric(12, 2) not null check (price >= 0),
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),

  -- An inspection is a transaction between two distinct people.
  constraint inspections_distinct_parties check (client_id is distinct from inspector_id),

  -- Once an inspector is on the hook, one must be assigned.
  constraint inspections_inspector_assigned
    check (status in ('pending', 'cancelled') or inspector_id is not null)
);

-- Job board: pending requests for one city, newest first.
create index inspections_board_idx
  on public.car_inspections (city, created_at desc)
  where status = 'pending';

-- "My requests" list for a client.
create index inspections_client_idx
  on public.car_inspections (client_id, created_at desc);

-- "My jobs" list for an inspector.
create index inspections_inspector_idx
  on public.car_inspections (inspector_id, status)
  where inspector_id is not null;

-- ============================================================================
-- inspection_reports — exactly one per inspection
--
-- The six component scores and the overall rating are all on a 1..5 scale and
-- are supplied by the inspector; overall_rating is not derived, because the
-- inspector's holistic judgement may legitimately differ from the mean.
-- ============================================================================

create table public.inspection_reports (
  id                     uuid primary key default gen_random_uuid(),
  inspection_id          uuid not null unique references public.car_inspections (id) on delete cascade,
  engine_condition       smallint not null check (engine_condition between 1 and 5),
  chassis_condition      smallint not null check (chassis_condition between 1 and 5),
  paint_body_condition   smallint not null check (paint_body_condition between 1 and 5),
  transmission_condition smallint not null check (transmission_condition between 1 and 5),
  electrical_condition   smallint not null check (electrical_condition between 1 and 5),
  interior_condition     smallint not null check (interior_condition between 1 and 5),
  overall_rating         smallint not null check (overall_rating between 1 and 5),
  notes                  text,
  pdf_report_url         text,
  completed_at           timestamptz,
  created_at             timestamptz not null default now()
);

-- ============================================================================
-- report_media — attachments belonging to a report
-- ============================================================================

create table public.report_media (
  id          uuid primary key default gen_random_uuid(),
  report_id   uuid not null references public.inspection_reports (id) on delete cascade,
  media_url   text not null,
  media_type  public.media_type not null default 'image',
  description text,
  created_at  timestamptz not null default now()
);

create index report_media_report_idx on public.report_media (report_id);

-- ============================================================================
-- payments — one escrow record per inspection
--
-- RESTRICT on the inspection: a financial record must never be destroyed by a
-- cascade from the marketplace side. See migration 0002 for the write policy:
-- rows may only be written by a service-role function, never by a client.
-- ============================================================================

create table public.payments (
  id             uuid primary key default gen_random_uuid(),
  inspection_id  uuid not null unique references public.car_inspections (id) on delete restrict,
  amount         numeric(12, 2) not null check (amount > 0),
  status         public.payment_status not null default 'escrow',
  payment_method text not null check (char_length(payment_method) between 2 and 40),
  transaction_id text not null unique,
  created_at     timestamptz not null default now()
);

create index payments_status_idx on public.payments (status);

-- ============================================================================
-- Invariant: inspection state machine
--
-- Implemented in the database rather than in client code so that no API caller
-- can skip a state. Security invoker: it needs no elevated rights.
--
--   pending -> accepted -> in_progress -> completed
--      \          \            \
--       +----------+------------+--> cancelled
--
-- Two further rules:
--   1. The accepting inspector is forced to be the caller, so an inspector
--      cannot claim a job on another inspector's behalf.
--   2. Commercial terms (client, city, price, vehicle identity) are frozen
--      after the request leaves `pending`.
-- ============================================================================

create or replace function public.enforce_inspection_transition()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status is distinct from old.status then
    if not (
      (old.status = 'pending'    and new.status in ('accepted', 'cancelled')) or
      (old.status = 'accepted'   and new.status in ('in_progress', 'cancelled')) or
      (old.status = 'in_progress' and new.status in ('completed', 'cancelled'))
    ) then
      raise exception
        'illegal inspection status transition: % -> %', old.status, new.status
        using errcode = 'check_violation';
    end if;

    -- Rule 1: an acceptance always binds the job to the accepting inspector.
    if old.status = 'pending' and new.status = 'accepted' and auth.uid() is not null then
      new.inspector_id := auth.uid();
    end if;
  end if;

  -- Rule 2: commercial terms are immutable once an inspector is committed.
  if old.status <> 'pending' and (
       new.client_id              is distinct from old.client_id or
       new.city                   is distinct from old.city or
       new.price                  is distinct from old.price or
       new.car_make               is distinct from old.car_make or
       new.car_model              is distinct from old.car_model or
       new.car_year               is distinct from old.car_year or
       new.seller_phone           is distinct from old.seller_phone or
       new.seller_location_address is distinct from old.seller_location_address
  ) then
    raise exception
      'commercial terms are immutable once an inspection is %', old.status
      using errcode = 'check_violation';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create trigger inspections_transition_guard
  before update on public.car_inspections
  for each row execute function public.enforce_inspection_transition();

-- ============================================================================
-- Invariant: users.role may never be changed by the user who owns the row.
--
-- Without this, a client could elevate themselves to `admin` through the very
-- same UPDATE policy that lets them fix their phone number. Only the
-- service role (admin tooling) may change a role.
-- ============================================================================

create or replace function public.protect_user_role()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.role is distinct from old.role then
    if current_user <> 'service_role' and coalesce(auth.uid() is not null, false) then
      raise exception 'users.role may only be changed by an administrator'
        using errcode = 'insufficient_privilege';
    end if;
  end if;
  return new;
end;
$$;

create trigger users_role_guard
  before update on public.users
  for each row execute function public.protect_user_role();
