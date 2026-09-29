-- Moaen (معاين) — 0007_inspection_detail.sql
-- The data the approved design's screens need, added to the tables that already
-- exist. Columns and tables only: no policy is relaxed, and no existing column is
-- dropped or retyped, so migration 0002's RLS and 0001's state machine keep
-- working exactly as written.
--
-- Grouped by the screen that needs them, because that is how the design
-- specified them and it is the only way to tell which of these are load-bearing
-- versus speculative.
--
--   Screen 1  buyer home        seller_name, appointment_at, center_fee,
--                               client_approved_at
--   Screen 2  create request    plate_number, listing_url, seller_name
--   Screen 4  inspector task    appointment_at, center_fee
--   Screen 5  report entry      obd_clean, obd_notes, repair_estimate,
--                               condition_score, center_invoice_no
--   Screen 6  A4 report         vin, odometer_km, quality_score, result_summary,
--                               certified_at, report_parts, report_sections
--
-- Every column is nullable. That is a deliberate choice for a table that already
-- holds rows: a NOT NULL column without a default cannot be added to a populated
-- table at all, and adding one *with* a default would invent data for the
-- existing inspection. Nullability is therefore the only honest option here, and
-- the screens read null as "not recorded yet" — which is the truth.

-- ============================================================================
-- car_inspections — the identity and the booking
-- ============================================================================

-- The design's "اسم البائع / مالك السيارة", shown to the inspector in the
-- contact box. `seller_phone` already existed; the name did not.
alter table public.car_inspections add column seller_name text;

-- The design's optional plate ("رقم اللوحة (اختياري)") and listing link. Both
-- are optional in the design, so both are optional here.
alter table public.car_inspections add column plate_number text;
alter table public.car_inspections add column listing_url text;

-- Read off the vehicle at the centre and printed on the A4 report. Nullable
-- because a report can be issued for a car whose VIN nobody recorded, and a
-- blank field is better than a fabricated one.
alter table public.car_inspections add column vin text;
alter table public.car_inspections add column odometer_km integer;

-- The booking the inspector makes during the 48-hour coordination window, and the
-- two things the buyer's home displays about it.
--
-- `center_fee` is the approved centre's own price, which is why the invoice can
-- show a real 300 rather than the create screen's "determined later". It is set
-- from `inspection_centres.fee` when the booking is made, not typed by hand.
alter table public.car_inspections add column appointment_at timestamptz;
alter table public.car_inspections add column center_fee numeric(12, 2);

-- The buyer's "الموافقة على العرض وتأكيد الطلب". Recorded rather than inferred,
-- because the invoice the buyer approved is a fact about the transaction and not
-- something the UI can reconstruct.
alter table public.car_inspections add column client_approved_at timestamptz;

-- The design's create form has no address input: the city is the scope, and a
-- neighbourhood only ever appears as free text on a card. Relaxing the column is
-- therefore matching the schema to the product rather than the other way round.
--
-- A SET NOT NULL-to-null relaxation cannot lose data, so this is safe to run
-- against the existing row. The application treats it as optional from here on.
alter table public.car_inspections
  alter column seller_location_address drop not null;

-- Freeze the seller's name with the rest of the commercial terms. Without this it
-- would stay editable after an inspector has committed to the job, which is
-- exactly the hole migration 0001's rule 2 closed for the phone number.
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
       new.seller_name            is distinct from old.seller_name or
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

-- ============================================================================
-- inspection_centres — the approved centres an inspector can book
-- ============================================================================
--
-- A table rather than a hard-coded list, because the centre's *fee* is part of
-- the buyer's invoice. A dropdown of literals cannot produce the 300 that the
-- invoice shows; the value has to come from the same row the name does.
--
-- One city per centre. The design books a centre within the request's city, and a
-- centre in another city is a different appointment, not a different choice.
create table public.inspection_centres (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(name) between 2 and 120),
  city       text not null check (char_length(city) between 2 and 80),
  fee        numeric(12, 2) not null check (fee >= 0),
  created_at timestamptz not null default now(),
  unique (name, city)
);

-- The inspector's centre dropdown: always filtered by the inspector's own city.
create index inspection_centres_city_idx on public.inspection_centres (city);

alter table public.inspection_centres enable row level security;

-- Readable by any signed-in user, not only participants: an inspector chooses a
-- centre before the request has an inspector, so there is no participant to test
-- against yet. This is the second and last table readable without being a party
-- to something — see PROJECT_MAP.md security design §7.
create policy inspection_centres_select_authenticated
  on public.inspection_centres
  for select
  to authenticated
  using (true);

-- No client INSERT/UPDATE/DELETE policy. Centres are seeded by migration and
-- administered by the service role, because a centre's fee is a price the buyer
-- is shown and must not be editable by whoever is signed in.

grant select on public.inspection_centres to authenticated;

-- ============================================================================
-- inspection_reports — the findings behind the A4 report
-- ============================================================================

-- Screen 5's OBD card: a clean scan or recorded codes, plus the note under it.
alter table public.inspection_reports add column obd_clean boolean;
alter table public.inspection_reports add column obd_notes text;

-- The money the buyer is about to spend, and the headline the report is graded
-- on. Both are the inspector's judgement, not derived values — the same reason
-- `overall_rating` is supplied rather than computed.
alter table public.inspection_reports add column repair_estimate numeric(12, 2);
alter table public.inspection_reports add column condition_score smallint
  check (condition_score between 0 and 100);
alter table public.inspection_reports add column quality_score smallint
  check (quality_score between 0 and 100);

-- The centre's own invoice, which the report cites and the buyer may need for a
-- claim.
alter table public.inspection_reports add column center_invoice_no text;

-- The banner paragraph, and the moment the report becomes a citable document.
alter table public.inspection_reports add column result_summary text;
alter table public.inspection_reports add column certified_at timestamptz;

-- ============================================================================
-- inspection_report_parts — the car blueprint
-- ============================================================================
--
-- The A4 report's top-view diagram labels six regions of the car, each with an
-- English key, an Arabic label and a colour-coded verdict. A row per region
-- rather than six columns, because the diagram's chips are iterated and a
-- row-per-region table is the only shape that survives a seventh region.
--
-- `tone` is what the report paints the verdict badge, and it is constrained here
-- rather than in Dart so a client cannot invent a colour the report has no swatch
-- for.
create type public.report_part_tone as enum ('good', 'warn', 'poor');

create table public.inspection_report_parts (
  id            uuid primary key default gen_random_uuid(),
  report_id     uuid not null references public.inspection_reports (id) on delete cascade,
  ordinal       smallint not null check (ordinal between 0 and 20),
  part_key      text not null check (char_length(part_key) between 1 and 40),
  label_en      text not null check (char_length(label_en) between 1 and 40),
  label_ar      text not null check (char_length(label_ar) between 1 and 40),
  verdict       text not null check (char_length(verdict) between 1 and 60),
  tone          public.report_part_tone not null default 'good',
  created_at    timestamptz not null default now(),
  unique (report_id, part_key)
);

-- The report reads its chips in diagram order.
create index report_parts_report_idx
  on public.inspection_report_parts (report_id, ordinal);

alter table public.inspection_report_parts enable row level security;

create policy report_parts_select_participant
  on public.inspection_report_parts
  for select
  to authenticated
  using (public.is_report_participant(report_id));

create policy report_parts_insert_assigned_inspector
  on public.inspection_report_parts
  for insert
  to authenticated
  with check (public.is_inspection_inspector(
    (select inspection_id from public.inspection_reports where id = report_id)
  ));

-- An assigned inspector may correct a part they filed, and may remove one. There
-- is no participant DELETE: the buyer must not be able to rewrite the findings.
create policy report_parts_update_assigned_inspector
  on public.inspection_report_parts
  for update
  to authenticated
  using (public.is_inspection_inspector(
    (select inspection_id from public.inspection_reports where id = report_id)
  ))
  with check (public.is_inspection_inspector(
    (select inspection_id from public.inspection_reports where id = report_id)
  ));

create policy report_parts_delete_assigned_inspector
  on public.inspection_report_parts
  for delete
  to authenticated
  using (public.is_inspection_inspector(
    (select inspection_id from public.inspection_reports where id = report_id)
  ));

grant select, insert, update, delete
  on public.inspection_report_parts to authenticated;

-- Postgres requires USAGE on an enum type before a client may store one of its
-- values. Without this the insert policy passes and the write still fails, with
-- an error that points at the type rather than at the grant.
grant usage on type public.report_part_tone to authenticated;

-- ============================================================================
-- inspection_report_sections — the efficiency table
-- ============================================================================
--
-- The A4 report's four-row table: a sector, a percentage with a progress bar, and
-- the inspector's note. `efficiency` is a whole percentage because that is what a
-- bar can honestly render; a 0–5 score shown as a bar would imply a precision the
-- number does not have.
create table public.inspection_report_sections (
  id         uuid primary key default gen_random_uuid(),
  report_id  uuid not null references public.inspection_reports (id) on delete cascade,
  ordinal    smallint not null check (ordinal between 0 and 20),
  label      text not null check (char_length(label) between 1 and 80),
  efficiency smallint not null check (efficiency between 0 and 100),
  notes      text not null check (char_length(notes) between 1 and 400),
  created_at timestamptz not null default now(),
  unique (report_id, ordinal)
);

create index report_sections_report_idx
  on public.inspection_report_sections (report_id, ordinal);

alter table public.inspection_report_sections enable row level security;

create policy report_sections_select_participant
  on public.inspection_report_sections
  for select
  to authenticated
  using (public.is_report_participant(report_id));

create policy report_sections_insert_assigned_inspector
  on public.inspection_report_sections
  for insert
  to authenticated
  with check (public.is_inspection_inspector(
    (select inspection_id from public.inspection_reports where id = report_id)
  ));

create policy report_sections_update_assigned_inspector
  on public.inspection_report_sections
  for update
  to authenticated
  using (public.is_inspection_inspector(
    (select inspection_id from public.inspection_reports where id = report_id)
  ))
  with check (public.is_inspection_inspector(
    (select inspection_id from public.inspection_reports where id = report_id)
  ));

create policy report_sections_delete_assigned_inspector
  on public.inspection_report_sections
  for delete
  to authenticated
  using (public.is_inspection_inspector(
    (select inspection_id from public.inspection_reports where id = report_id)
  ));

grant select, insert, update, delete
  on public.inspection_report_sections to authenticated;
