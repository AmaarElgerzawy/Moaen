-- Moaen (معاين) — 0004_request_reference_and_notes.sql
-- Adds the two columns the Phase 2 client request flow needs but Phase 1 did not
-- have: a human-readable request reference, and the client's own notes on the
-- request. Apply via `supabase db push`.

-- ============================================================================
-- reference_no — the number a buyer reads out to an inspector
--
-- The primary key is a uuid, which is correct for a database and useless over the
-- phone: "three one seven dash four" is not something a person repeats back
-- accurately. A buyer who cannot quote their request reliably ends up describing
-- a car instead, and the inspector then inspects the wrong one.
--
-- So the uuid stays the key and this is the human handle. The app renders it as
-- `MN-1001`. A dedicated sequence rather than a derived value from the uuid,
-- because a derived number has to be re-derivable forever; a sequence is
-- monotonic, short, and stable.
--
-- Starts at 1000 so a reference does not read as a count of how many requests
-- the platform has ever served.
-- ============================================================================

create sequence public.inspection_reference_seq as bigint start with 1000;

-- `not null default nextval(...)` backfills existing rows: nextval is VOLATILE,
-- so Postgres evaluates the default per row rather than treating it as a
-- constant to copy. A table written this way needs no separate UPDATE backfill.
alter table public.car_inspections
  add column reference_no bigint not null
    default nextval('public.inspection_reference_seq');

alter table public.car_inspections
  add constraint inspections_reference_no_key unique (reference_no);

-- "My requests" is listed newest-first, and a client looking for one specific
-- request searches by the number they were given.
create index inspections_reference_idx on public.car_inspections (reference_no);

-- ============================================================================
-- client_notes — what the buyer wants the inspector to know
--
-- Distinct from `inspection_reports.notes`, which is the inspector's findings
-- written after the inspection. This is the buyer's brief, captured before
-- anyone has looked at the car: where the car is, when it can be seen, that the
-- seller is unreliable, that the engine has a noise. It exists because the
-- alternative is the buyer telephoning the inspector separately and relying on
-- both of them remembering.
--
-- Bounded at 1000 characters: long enough for a real brief, short enough that
-- nobody pastes an essay into a field on a phone.
-- ============================================================================

alter table public.car_inspections
  add column client_notes text
    check (client_notes is null or char_length(client_notes) <= 1000);

-- ============================================================================
-- The reference is the server's to assign, always
--
-- `reference_no` is the handle a buyer quotes to an inspector, so its integrity
-- is a security property, not a convenience. Two problems if the client can
-- choose it:
--
--  * It is mutable. The grant is table-level
--    (`grant select, insert, update on table public.car_inspections`), and
--    Postgres column privileges are *additive* — a column-level revoke does not
--    subtract from a table-level grant, so the client keeps UPDATE on this
--    column. They could renumber a request after quoting it, so the number the
--    inspector writes down no longer identifies the car.
--  * It is guessable. Sequential and small, so a client can set theirs to a
--    number another buyer already holds and either collide with it or, once
--    something trusts the number as an identifier, look like that buyer.
--
-- So the trigger overwrites on insert and restores the stored value on update.
-- A BEFORE trigger is the right instrument because it is the only place the
-- database can distinguish "the client sent this" from "the database assigned
-- this", and it cannot be bypassed by any client, including one using a
-- service-role path added later.
-- ============================================================================

create or replace function public.assign_inspection_reference()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    -- Overwrite whatever arrived, including an explicit value. A client that
    -- supplies one is not obeyed; the sequence is the only source.
    new.reference_no := nextval('public.inspection_reference_seq');
  elsif new.reference_no is distinct from old.reference_no then
    -- Someone tried to change it. Put the original back rather than raising:
    -- a client updating an unrelated field would otherwise fail outright, and
    -- the number is already correct.
    new.reference_no := old.reference_no;
  end if;
  return new;
end;
$$;

create trigger inspections_reference_guard
  before insert or update on public.car_inspections
  for each row
  execute function public.assign_inspection_reference();

-- ============================================================================
-- Grants and policies
--
-- Nothing to add. The Phase 1 grants are table-level
-- (`grant select, insert, update on table public.car_inspections to
-- authenticated`) and the policies are row-level with no column lists, so both
-- new columns are covered by what is already in place. Stating it here so a
-- future column addition does not have to re-derive the rule.
-- ============================================================================
