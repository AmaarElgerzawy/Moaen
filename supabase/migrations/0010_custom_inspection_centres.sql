-- Moaen (معاين) — 0010_custom_inspection_centres.sql
--
-- Lets an inspection happen somewhere that is not in `inspection_centres`.
--
-- The blocker this removes is concrete: the booking dropdown reads
-- `inspection_centres` filtered by the request's city, and a city with no seeded
-- centre leaves the inspector with nothing to pick and a booking they cannot
-- confirm. Migration 0008 seeds the twelve cities the product was specified for,
-- so the honest first response to "the dropdown is empty" is to apply 0008 —
-- it is `on conflict do nothing` and safe to re-run. This migration is what
-- happens when the answer is that the city genuinely has no approved centre, or
-- the buyer insists on somewhere specific.
--
-- ---------------------------------------------------------------------------
-- Where the custom centre lives, and why not in `inspection_centres`
-- ---------------------------------------------------------------------------
-- The obvious place would be a new row in `inspection_centres`. It is the wrong
-- place, for the reason migration 0007 gives when it withholds INSERT from that
-- table: "a centre's fee is a price the buyer is shown and must not be editable by
-- whoever is signed in." A client-writable catalogue lets anyone mint a centre
-- named whatever they like at whatever fee they like, and the next buyer to pick
-- it from the dropdown is shown that invented price. So `inspection_centres` stays
-- read-only to clients, and an unvetted centre travels on the request instead,
-- where it is only visible to the two parties to that request.
--
-- The four columns are on `car_inspections` for that reason, not on
-- `inspection_requests` — that table does not exist; this is the one.
--
-- ---------------------------------------------------------------------------
-- Proof of address
-- ---------------------------------------------------------------------------
-- `custom_centre_proof_photo_url` is the inspector's assertion that the place is a
-- real inspection shop: a shopfront, a trade licence, a photograph of the bay the
-- car will be in. The buyer does not supply one, because the buyer is expressing a
-- preference rather than vouching for a business, and a buyer-supplied "proof"
-- would be a photograph of anything.
--
-- So the column is the inspector's to write and nobody else's, which is what the
-- trigger below enforces. It is a path into the `inspection-media` bucket, not a
-- URL — that bucket is private, so a durable object path is what belongs in the
-- column, and a reader mints a signed URL at the moment it needs to display one.
--
-- ---------------------------------------------------------------------------
-- Re-runnable
-- ---------------------------------------------------------------------------
-- Every statement can be applied twice. The SQL Editor and the dashboard's query
-- panel both run a pasted script as one transaction, so one bad statement rolls
-- the whole file back and the natural next move is to paste it again.

-- ============================================================================
-- 1. Cities gain coordinates
--
-- The map has to open somewhere. Opening every picker on one hard-coded Riyadh
-- point would mean every buyer in Dammam pans the whole country to find their own
-- city, so the anchor comes from the city they already chose. `city` and
-- `location_city` are free text with no foreign key (0006 says so), so this is
-- matched by name rather than by an enforced key — which is also why a city
-- missing here is a map that opens in the wrong place, not an error.
-- ============================================================================

alter table public.cities add column if not exists latitude double precision;
alter table public.cities add column if not exists longitude double precision;

do $$
begin
  if exists (
    select 1 from pg_constraint
    where conname = 'cities_coordinate_bounds'
      and conrelid = 'public.cities'::regclass
  ) then
    alter table public.cities drop constraint cities_coordinate_bounds;
  end if;
end $$;

alter table public.cities
  add constraint cities_coordinate_bounds check (
    (latitude is null and longitude is null)
    or (latitude between -90 and 90 and longitude between -180 and 180)
  );

-- City centres, to the precision a map thumbnail needs. Matched on `name_en`,
-- which is what 0006 established as the stable key; `name_ar` is what the UI
-- shows, so matching on it would tie a coordinate to a translation.
--
-- The 29 names here are the 29 in `public.cities`. A name that is in neither list
-- is not an error — the picker simply falls back to `kFallbackCentre` — but a name
-- that was *spelled* differently here would silently get no coordinate, so the two
-- lists are worth comparing when a city's map opens in the wrong place.
update public.cities as c
set latitude = v.latitude, longitude = v.longitude
from (values
  ('Madinah',            24.5247,  39.5692),
  ('Makkah',             21.3891,  39.8579),
  ('Riyadh',             24.7136,  46.6753),
  ('Dammam',             26.4207,  50.0888),
  ('Khobar',             26.2794,  50.2083),
  ('Dhahran',            26.2361,  50.0553),
  ('Jubail',             27.0174,  49.6225),
  ('Al Ahsa',            25.3647,  49.5879),
  ('Qatif',              26.5196,  50.0104),
  ('Jeddah',             21.4858,  39.1925),
  ('Buraidah',           26.3260,  43.9750),
  ('Tabuk',              28.3838,  36.5550),
  ('Taif',               21.2703,  40.4158),
  ('Abha',               18.2465,  42.5117),
  ('Khamis Mushait',     18.3000,  42.7300),
  ('Hail',               27.5114,  41.7208),
  ('Najran',             17.4917,  44.1322),
  ('Jazan',              16.8892,  42.5706),
  ('Yanbu',              24.0895,  38.0618),
  ('Arar',               30.9753,  41.0381),
  ('Sakaka',             29.9697,  40.2064),
  ('Baha',               20.0129,  41.4673),
  ('AlUla',              26.6085,  37.9232),
  ('Qunfudhah',          19.1264,  41.0789),
  ('Ahmadi',             29.0765,  48.0839),
  ('Rabigh',             22.7986,  39.0349),
  ('Al Qalt',            28.6333,  33.6167),
  ('Wadi ad-Dawasir',    20.4667,  44.8000),
  ('Mustatam',           21.8000,  39.8000)
) as v(name_en, latitude, longitude)
where c.name_en = v.name_en;

-- ============================================================================
-- 2. The custom centre on the request
--
-- All four nullable: an inspection at an approved centre records none of them,
-- and that is the common case until a city runs out of seeded centres.
-- ============================================================================

alter table public.car_inspections add column if not exists custom_centre_name text;
alter table public.car_inspections add column if not exists custom_centre_lat double precision;
alter table public.car_inspections add column if not exists custom_centre_lng double precision;
alter table public.car_inspections add column if not exists custom_centre_proof_photo_url text;

-- The four move together or not at all.
--
-- A name with no location cannot be shown to an inspector driving to it, and a
-- location with no name is a pin the booking form would have to label with
-- coordinates. A proof photo is optional — a buyer naming a centre supplies none,
-- and the inspector may attach theirs at booking — but one without the triple is
-- meaningless, so it may only accompany a centre rather than stand in for one.
--
-- Written as named constraints dropped and re-added rather than as inline column
-- checks, because `add column if not exists` is a no-op on a column that already
-- exists and would therefore silently skip the check attached to it. Dropping by
-- name first means applying this file to a database where a previous run got part
-- way through leaves the same shape as one where it completed.
do $$
declare
  c text;
begin
  foreach c in array array[
    'car_inspections_custom_centre_shape',
    'car_inspections_custom_centre_name_length',
    'car_inspections_custom_centre_lat_range',
    'car_inspections_custom_centre_lng_range'
  ] loop
    if exists (
      select 1 from pg_constraint
      where conname = c and conrelid = 'public.car_inspections'::regclass
    ) then
      execute format('alter table public.car_inspections drop constraint %I', c);
    end if;
  end loop;
end $$;

alter table public.car_inspections
  add constraint car_inspections_custom_centre_shape check (
    (custom_centre_name is null
     and custom_centre_lat is null
     and custom_centre_lng is null
     and custom_centre_proof_photo_url is null)
    or
    (custom_centre_name is not null
     and custom_centre_lat is not null
     and custom_centre_lng is not null)
  ),
  add constraint car_inspections_custom_centre_name_length check (
    custom_centre_name is null
    or char_length(custom_centre_name) between 2 and 120
  ),
  add constraint car_inspections_custom_centre_lat_range check (
    custom_centre_lat is null or custom_centre_lat between -90 and 90
  ),
  add constraint car_inspections_custom_centre_lng_range check (
    custom_centre_lng is null or custom_centre_lng between -180 and 180
  );

-- ============================================================================
-- 3. One definition of "the caller is the buyer"
--
-- Migration 0009's rule 3 needs this to tell a buyer from an inspector, and the
-- trigger below needs the same test. Written twice, the two copies would drift
-- and one of them would end up protecting something the other no longer does.
--
-- Takes the parties as parameters rather than an inspection id on purpose: it is
-- called from a BEFORE UPDATE trigger, where reading the row back by id would
-- happen to return the pre-update values only because the write has not landed
-- yet. Passing `old.client_id` and `old.inspector_id` is correct regardless of
-- when the trigger fires, which is a property worth having in the function that
-- guards access to a buyer's data.
--
-- The third condition is the one that is easy to lose. An account that is both
-- the client and the inspector of one row is not something the flow produces —
-- 0001 forbids a self-inspection — so the distinction is free, and without it a
-- buyer who was also the inspector would be locked out of their own request.
-- ============================================================================

create or replace function public.is_buyer_row(p_client_id uuid, p_inspector_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
     and auth.uid() = p_client_id
     and auth.uid() is distinct from p_inspector_id;
$$;

revoke all on function public.is_buyer_row(uuid, uuid) from public, anon;
grant execute on function public.is_buyer_row(uuid, uuid) to authenticated;

-- 0009's rule 3, now reading that definition instead of restating it. The body is
-- otherwise unchanged, and the transition table and the two other rules are left
-- exactly as 0009 wrote them.
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
       new.client_name            is distinct from old.client_name or
       new.inspector_name         is distinct from old.inspector_name or
       new.city                   is distinct from old.city or
       new.price                  is distinct from old.price or
       new.car_make               is distinct from old.car_make or
       new.car_model              is distinct from old.car_model or
       new.car_year               is distinct from old.car_year or
       new.seller_phone           is distinct from old.seller_phone or
       new.seller_name            is distinct from old.seller_name or
       new.seller_location_address is distinct from old.seller_location_address
  ) then
    raise exception
      'commercial terms are immutable once an inspection is %', old.status
      using errcode = 'check_violation';
  end if;

  -- Rule 3: only an inspector drives an inspection forward.
  if public.is_buyer_row(old.client_id, old.inspector_id) then
    if new.status is distinct from old.status and new.status <> 'cancelled' then
      raise exception
        'only an inspector may advance an inspection'
        using errcode = 'check_violation';
    end if;

    if new.inspector_id is distinct from old.inspector_id then
      raise exception
        'a buyer cannot assign an inspector'
        using errcode = 'check_violation';
    end if;

    -- The name is part of the assignment, not part of the profile.
    if new.inspector_name is distinct from old.inspector_name then
      raise exception
        'a buyer cannot assign an inspector'
        using errcode = 'check_violation';
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

-- ============================================================================
-- 4. Who may write the custom centre
--
-- Two rules, and the first is the reason this is a trigger and not a policy. RLS
-- is row-level: it can say "the buyer may update their own request", which it
-- already does, and that is no use at all here because the buyer's legitimate
-- column and the inspector's illegitimate one live in the same row. A trigger is
-- the only thing in Postgres that can refuse one column and permit its
-- neighbour, so the buyer's UPDATE policy stays exactly as 0009 wrote it.
-- ============================================================================

create or replace function public.enforce_custom_centre()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- INSERT, first, because `old` does not exist there and rule 2 below reads it.
  --
  -- Only rule 1 has anything to say on a new row: the buyer's name and coordinate
  -- are exactly what they are supposed to file, and at insert time no inspector is
  -- committed so there is nothing to freeze. But the proof column is forgeable from
  -- the moment the row exists — the buyer's own INSERT policy lets them name any
  -- column — and a proof photo filed with the request would be read off the report
  -- as the inspector's verification of a shop nobody inspected. A rule that only
  -- guards UPDATE leaves the whole feature's one guarantee resting on the app not
  -- sending the field.
  if tg_op = 'INSERT' then
    if new.custom_centre_proof_photo_url is not null then
      raise exception
        'the centre proof photo may only be supplied by the inspector'
        using errcode = 'check_violation';
    end if;

    return new;
  end if;

  if public.is_buyer_row(old.client_id, old.inspector_id) then

    -- Rule 1: the proof is the inspector's to write, in every state.
    --
    -- Not merely "once an inspector is committed" — a buyer filing a request can
    -- set any column on it, and without this they could attach a photograph to
    -- their own inspection and have the report cite it as the inspector's
    -- verification that a shop is real. That is the one field on this request
    -- that asserts something about a third party, so it is the one field the
    -- third party's client may never write.
    if new.custom_centre_proof_photo_url
         is distinct from old.custom_centre_proof_photo_url then
      raise exception
        'the centre proof photo may only be supplied by the inspector'
        using errcode = 'check_violation';
    end if;

    -- Rule 2: the buyer's suggestion freezes once an inspector is committed.
    --
    -- The same argument as 0009's rule 2, and it is what makes the preselection in
    -- the booking box honest: the inspector accepts a job on the strength of the
    -- centre name the buyer wrote, so that name cannot then change underneath
    -- them. Left out for the inspector, unlike rule 2 there, because booking an
    -- unlisted centre at `accepted` is exactly the write that has to work here.
    if old.status <> 'pending' and (
         new.custom_centre_name is distinct from old.custom_centre_name or
         new.custom_centre_lat  is distinct from old.custom_centre_lat  or
         new.custom_centre_lng  is distinct from old.custom_centre_lng
    ) then
      raise exception
        'the requested centre is immutable once an inspection is %', old.status
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists inspections_custom_centre_guard on public.car_inspections;

create trigger inspections_custom_centre_guard
  before insert or update on public.car_inspections
  for each row execute function public.enforce_custom_centre();

-- ============================================================================
-- 5. Tell PostgREST the schema changed
--
-- As at the end of 0009: PostgREST validates every request against an in-memory
-- snapshot of the public schema, so a column that is genuinely in the table can
-- still be PGRST204 until the snapshot is reloaded. The notification is delivered
-- at commit and is a no-op where nothing is listening, so stating it is safe.
-- ============================================================================

notify pgrst, 'reload schema';