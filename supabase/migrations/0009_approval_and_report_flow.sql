-- Moaen (معاين) — 0009_approval_and_report_flow.sql
--
-- The three things the design's report-and-approval flow needs that migrations
-- 0001 and 0002 did not allow. They are one migration because two of them are
-- changes to `enforce_inspection_transition`, and splitting them would mean
-- three near-identical copies of that function in the history instead of two.
--
-- Nothing here drops or retypes a column. Every relaxation is SET NOT NULL
-- dropped or a column added, so none of the three can lose data, and all three
-- are safe to run against the existing rows.
--
--   1. The buyer's "الموافقة على العرض وتأكيد الطلب" is a write the client
--      could not previously make.
--   2. The inspector's board shows the requester's name, which the inspector is
--      not allowed to read from `public.users`.
--   3. The seven 1-5 rating columns from migration 0001 are NOT NULL, and the
--      design's findings form collects none of them — so a report could not be
--      created at all.

-- ============================================================================
-- 1. The buyer's approval
-- ============================================================================
--
-- 0002's `inspections_update_client_while_pending` lets a client update their
-- own request only while `status = 'pending'`. Approval happens *after* an
-- inspector has accepted and booked a centre — that is the whole point of it:
-- there is no centre and no total to approve before then. So the policy has to
-- widen, and widening it alone would hand a buyer two powers they must not have.

drop policy if exists inspections_update_client_while_pending
  on public.car_inspections;

-- Also dropping the policy this file creates, so a re-run after a partial
-- application replaces it instead of failing on "policy already exists". Every
-- statement below is written to be re-runnable, because the SQL Editor and the
-- dashboard's query panel both run a pasted script as one transaction: one bad
-- statement rolls the whole file back, and the natural next move is to paste it
-- again. A file that can only ever be applied once is a file that cannot be
-- recovered from.
drop policy if exists inspections_update_client
  on public.car_inspections;

-- `cancelled` is deliberately absent from the USING list: it is terminal, so
-- there is nothing left for the buyer to write. `completed` is absent because
-- the inspector owns that transition.
create policy inspections_update_client
  on public.car_inspections
  for update
  to authenticated
  using (
    client_id = auth.uid()
    and status in ('pending', 'accepted', 'in_progress')
  )
  with check (client_id = auth.uid());

-- ============================================================================
-- 2. The requester's name, frozen on the request
-- ============================================================================
--
-- The design's market card reads "طالب الفحص: سعود". The buyer's name lives in
-- `public.users`, and 0002's `users_select_self_or_admin` lets an inspector
-- read only their own row — so the name is not reachable from the board.
--
-- Widening that policy is the wrong fix: RLS is row-level, so it would hand
-- every inspector read access to every buyer's email and phone as well. There
-- is no column-level RLS in Postgres, and a security-barrier view does not
-- help because the underlying table still has to be readable by its owner.
--
-- So the name is copied onto the request at creation and frozen there, the same
-- way `seller_phone` and `seller_name` already are. This is also the more
-- honest record: it is the name the two parties transacted under, not whatever
-- the buyer has since renamed their account to.
--
-- Nullable, like every column 0007 added: the existing request predates this
-- column, and inventing a name for it would be fabricating a record.
alter table public.car_inspections add column if not exists client_name text;

-- The same problem, the other way round, and the reason the A4 report cannot
-- simply read the inspector's name off `public.users` either. The report is a
-- citable document: it names the field inspector who stood behind the verdict,
-- and the buyer who is handed the report is exactly the reader that RLS keeps
-- away from that row. The same `users_select_self_or_admin` policy applies to
-- the buyer, and the same argument against widening it holds — it would expose
-- every buyer's email and phone to every inspector.
--
-- So the inspector's name is frozen at the moment they claim the job, which is
-- the moment their `auth.uid()` becomes the job's `inspector_id` anyway, and by
-- the only party who is allowed to write it: rule 1 below binds the claim to
-- `auth.uid()`, and rule 3 rejects the name from anyone who is the client.
--
-- Nullable for the same reason as `client_name`: the existing request predates
-- the column, and its inspector — if it ever had one — is not recoverable.
alter table public.car_inspections add column if not exists inspector_name text;

-- ============================================================================
-- 3. The superseded 1-5 ratings
-- ============================================================================
--
-- Migration 0001's `inspection_reports` required seven separate 1-5 ratings
-- (`engine_condition` … `overall_rating`) before a row could exist. The design
-- replaces that form entirely: Screen 5 collects OBD findings, a body verdict,
-- two mechanical verdicts and an estimate, and 0007 added the tables the A4
-- report actually renders — `inspection_report_parts` and
-- `inspection_report_sections` — plus `condition_score` and `quality_score` in
-- place of `overall_rating`.
--
-- None of the seven is written by any screen, and all seven are NOT NULL, so
-- today a report cannot be created without inventing seven numbers the user
-- never entered. Relaxing them is the alternative to fabricating a finding on
-- every certified document, which is plainly the worse of the two.
--
-- No application code reads them and none will. They are left in place rather
-- than dropped so the columns and their existing data survive if the old rating
-- form is ever wanted back; a dropped column cannot be restored.
alter table public.inspection_reports
  alter column engine_condition       drop not null,
  alter column chassis_condition       drop not null,
  alter column paint_body_condition    drop not null,
  alter column transmission_condition drop not null,
  alter column electrical_condition    drop not null,
  alter column interior_condition     drop not null,
  alter column overall_rating          drop not null;

-- The same reasoning applies to one column in migration 0007. The A4 report's
-- efficiency table has a note per sector, but the design's report-entry screen
-- collects narrative text for two of its four sectors only, and every row is
-- declared `notes text not null check (char_length(notes) between 1 and 400)`.
-- For the other two sectors the only way to satisfy that check is to invent a
-- sentence of inspection prose — on a certified document, attributed to a named
-- inspector. Nullable says the truth instead: this sector has a score and no
-- note.
--
-- `efficiency` stays NOT NULL. Every sector does have a score, because the
-- sectors are chosen by the form's own verdict controls; a row with no score
-- would be a sector nobody measured, which is a different thing.
alter table public.inspection_report_sections
  alter column notes drop not null;

-- ============================================================================
-- 4. The trigger: freeze the requester's name, and stop a buyer advancing
--    their own inspection
-- ============================================================================
--
-- Two holes the wider client policy in section 1 would otherwise open, plus one
-- that already existed:
--
--   * `pending -> accepted` is a legal transition, and rule 1 binds the
--     accepting inspector to `auth.uid()`. A buyer updating their own pending
--     row could accept their own request and become their own inspector. This
--     already existed under 0002's policy; it is closed here because the wider
--     policy reaches more states, and because "only an inspector may advance an
--     inspection" is easier to reason about than "only while pending".
--   * `accepted -> in_progress` and `in_progress -> completed` are legal too, so
--     a buyer could report their own inspection as finished.
--
-- Cancelling is left alone: it is the buyer's own action, it is bounded by the
-- transition table, and 0002's policy comment already states it is their only
-- write.
--
-- A buyer is identified as "the client, and not also the inspector". An account
-- that is the client and the inspector of the same row is not something the
-- flow produces — 0001 forbids a self-inspection — so the distinction costs
-- nothing and avoids locking an inspector out of a job they are also paying
-- for.

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
  -- `client_name` joins them in section 2's terms: the inspector was shown it
  -- when they claimed the job, so it cannot change underneath them either.
  -- `inspector_name` joins them for the mirror reason: the buyer is shown it on
  -- the certified report, so a claimed job cannot be re-attributed later.
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

  -- Rule 3: only an inspector drives an inspection forward. See the header.
  if auth.uid() is not null
     and auth.uid() = old.client_id
     and auth.uid() is distinct from old.inspector_id
  then
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

    -- The name is part of the assignment, not part of the profile: a buyer who
    -- could write it could re-attribute a certified report to a name of their
    -- choosing, which is the one thing a document attributed to a person must
    -- not be. Rule 2 already forbids it once a job is claimed; this covers the
    -- pending row, where a buyer is otherwise free to write any column.
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
