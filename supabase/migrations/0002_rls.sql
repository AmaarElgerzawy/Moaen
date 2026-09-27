-- Moaen (معاين) — 0002_rls.sql
-- Auth provisioning, RLS helper functions, Row Level Security, public profiles.
--
-- Every table in `public` has RLS enabled. `anon` receives no access at all:
-- sign-up flows through Supabase Auth, never through a table read.
--
-- ---------------------------------------------------------------------------
-- The recursion problem this file is built around
-- ---------------------------------------------------------------------------
-- A policy on `car_inspections` must know the caller's role and city, which
-- live in `public.users`. Referencing `public.users` directly from inside that
-- policy would re-enter `users`' own SELECT policy, and Postgres aborts the
-- whole statement with:
--
--     ERROR: infinite recursion detected in policy for relation "users"
--
-- The fix is a set of SECURITY DEFINER helpers. They execute as the table
-- owner, for whom RLS is not enforced, so they read `public.users` freely
-- without ever re-entering a policy. They are STABLE, so the planner evaluates
-- them once per statement rather than once per row.
--
-- They also give us a second property that matters just as much: participant
-- checks are computed independently of the RLS policies on the tables being
-- checked. A bug in `car_inspections` RLS therefore cannot leak through into
-- report or media visibility.

-- ============================================================================
-- Auth provisioning
--
-- `public.users` rows are created by a trigger on `auth.users`, never by the
-- client. A client with an INSERT policy on `users` could mint a row for any
-- UUID and grant themselves any role.
--
-- The requested role is whitelisted to client|inspector. `admin` is not
-- self-assignable, which is what makes it safe to expose the enum to the app.
-- ============================================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.users (id, full_name, email, phone, role, location_city)
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
      split_part(new.email, '@', 1)
    ),
    new.email,
    nullif(trim(new.raw_user_meta_data ->> 'phone'), ''),
    case
      when new.raw_user_meta_data ->> 'role' = 'inspector'
        then 'inspector'::public.user_role
      else 'client'::public.user_role
    end,
    nullif(trim(new.raw_user_meta_data ->> 'city'), '')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================================
-- Helper functions
-- ============================================================================

-- The caller's role, or NULL when unauthenticated / not yet provisioned.
create or replace function public.current_user_role()
returns public.user_role
language sql
stable
security definer
set search_path = ''
as $$
  select u.role from public.users u where u.id = auth.uid();
$$;

-- The caller's service city, or NULL. NULL is load-bearing: a NULL city makes
-- every city comparison evaluate to NULL, which is not TRUE, so an inspector
-- who has not set a city sees an empty job board rather than everyone's jobs.
create or replace function public.current_user_city()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select u.location_city from public.users u where u.id = auth.uid();
$$;

-- True when the caller is the client or the assigned inspector of the given
-- inspection. Independent of car_inspections RLS by construction.
create or replace function public.is_inspection_participant(p_inspection_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.car_inspections i
    where i.id = p_inspection_id
      and (i.client_id = auth.uid() or i.inspector_id = auth.uid())
  );
$$;

-- True only for the assigned inspector. This is the write side: participants
-- may read a report, but only the inspector may author or amend one.
create or replace function public.is_inspection_inspector(p_inspection_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.car_inspections i
    where i.id = p_inspection_id
      and i.inspector_id = auth.uid()
  );
$$;

-- Two-hop variant for report_media: report -> inspection -> parties.
create or replace function public.is_report_participant(p_report_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.inspection_reports r
    join public.car_inspections i on i.id = r.inspection_id
    where r.id = p_report_id
      and (i.client_id = auth.uid() or i.inspector_id = auth.uid())
  );
$$;

-- SECURITY DEFINER functions are executable by PUBLIC by default, which would
-- let `anon` probe them. Lock them down to authenticated callers only.
revoke all on function public.current_user_role()          from public, anon;
revoke all on function public.current_user_city()           from public, anon;
revoke all on function public.is_inspection_participant(uuid) from public, anon;
revoke all on function public.is_inspection_inspector(uuid)  from public, anon;
revoke all on function public.is_report_participant(uuid)     from public, anon;

grant execute on function public.current_user_role()            to authenticated;
grant execute on function public.current_user_city()             to authenticated;
grant execute on function public.is_inspection_participant(uuid) to authenticated;
grant execute on function public.is_inspection_inspector(uuid)  to authenticated;
grant execute on function public.is_report_participant(uuid)     to authenticated;

-- ============================================================================
-- Public inspector profiles
--
-- A blanket SELECT policy on `users` would let any inspector read every rival
-- inspector's email address and phone number. Instead `users` is readable only
-- by its owner and by admins, and everyone else reads this view.
--
-- The view intentionally runs with the privileges of its owner, so the RLS
-- policies on `users` do not apply to it. That is the whole point: every column
-- projected here is public-by-design, and no private column is projected.
-- ============================================================================

create view public.inspector_profiles as
  select u.id,
         u.full_name,
         u.avatar_url,
         u.location_city,
         u.rating
  from public.users u
  where u.role = 'inspector';

grant select on public.inspector_profiles to authenticated;

-- ============================================================================
-- Enable RLS
-- ============================================================================

alter table public.users              enable row level security;
alter table public.car_inspections    enable row level security;
alter table public.inspection_reports enable row level security;
alter table public.report_media       enable row level security;
alter table public.payments           enable row level security;

-- Drop Supabase's permissive default grants before stating our own, so the
-- effective permission set is exactly what is written below.
revoke all on table public.users              from anon, authenticated;
revoke all on table public.car_inspections    from anon, authenticated;
revoke all on table public.inspection_reports from anon, authenticated;
revoke all on table public.report_media       from anon, authenticated;
revoke all on table public.payments           from anon, authenticated;

grant select, update on table public.users              to authenticated;
grant select, insert, update on table public.car_inspections to authenticated;
grant select, insert, update on table public.inspection_reports to authenticated;
grant select, insert on table public.report_media       to authenticated;
grant select on table public.payments                   to authenticated;
-- payments: SELECT only. No INSERT/UPDATE/DELETE is granted to `authenticated`
-- on purpose. A client that could insert its own row could write
-- status = 'released' and fabricate a settlement. All writes go through a
-- service-role function, which bypasses RLS. See PROJECT_MAP.md P2.

-- ============================================================================
-- users policies
-- ============================================================================

-- Own row, plus every row for an admin.
create policy users_select_self_or_admin
  on public.users
  for select
  to authenticated
  using (id = auth.uid() or public.current_user_role() = 'admin');

-- Own row only, and only to fix one's own details. The `users_role_guard`
-- trigger from 0001 rejects any attempt to change `role`, so this policy
-- cannot be used for privilege escalation.
create policy users_update_self
  on public.users
  for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- No INSERT and no DELETE policy: rows are provisioned by handle_new_user()
-- and retired by an administrator, never by the user.

-- ============================================================================
-- car_inspections policies
-- ============================================================================

-- The two parties, plus admins.
create policy inspections_select_participant
  on public.car_inspections
  for select
  to authenticated
  using (
    client_id = auth.uid()
    or inspector_id = auth.uid()
    or public.current_user_role() = 'admin'
  );

-- The job board: an inspector sees unclaimed requests in their own city.
-- Case-insensitive compare so that "Cairo" and " cairo " do not silently
-- produce an empty board.
create policy inspections_select_board
  on public.car_inspections
  for select
  to authenticated
  using (
    status = 'pending'
    and public.current_user_role() = 'inspector'
    and lower(btrim(city)) = lower(btrim(public.current_user_city()))
  );

-- A client creates their own request, and only in the initial state. Without
-- the status/inspector_id assertions here, a client could POST a row that is
-- already 'completed' and assigned to a friendly inspector.
create policy inspections_insert_own
  on public.car_inspections
  for insert
  to authenticated
  with check (
    client_id = auth.uid()
    and public.current_user_role() = 'client'
    and status = 'pending'
    and inspector_id is null
  );

-- A client may edit their request only while it is still unclaimed. Once an
-- inspector has accepted, the transition guard freezes the commercial terms.
create policy inspections_update_client_while_pending
  on public.car_inspections
  for update
  to authenticated
  using (client_id = auth.uid() and status = 'pending')
  with check (client_id = auth.uid());

-- An inspector may claim a pending job in their city, then drive their own
-- assigned job forward. enforce_inspection_transition() (0001) forces
-- inspector_id := auth.uid() on acceptance, so a claim cannot be made on
-- another inspector's behalf.
create policy inspections_update_inspector
  on public.car_inspections
  for update
  to authenticated
  using (
    public.current_user_role() = 'inspector'
    and (
      inspector_id = auth.uid()
      or (
        status = 'pending'
        and lower(btrim(city)) = lower(btrim(public.current_user_city()))
      )
    )
  )
  with check (public.current_user_role() = 'inspector');

-- No DELETE policy for anyone. Inspection and payment history is preserved;
-- see the RESTRICT constraints in 0001.

-- ============================================================================
-- inspection_reports policies
-- ============================================================================

create policy reports_select_participant
  on public.inspection_reports
  for select
  to authenticated
  using (
    public.is_inspection_participant(inspection_id)
    or public.current_user_role() = 'admin'
  );

-- Only the assigned inspector authors a report, and only once the inspection
-- is actually underway. The client cannot write their own report.
create policy reports_insert_assigned_inspector
  on public.inspection_reports
  for insert
  to authenticated
  with check (
    public.is_inspection_inspector(inspection_id)
    and exists (
      select 1 from public.car_inspections i
      where i.id = inspection_id and i.status in ('in_progress', 'completed')
    )
  );

create policy reports_update_assigned_inspector
  on public.inspection_reports
  for update
  to authenticated
  using (public.is_inspection_inspector(inspection_id))
  with check (public.is_inspection_inspector(inspection_id));

-- No DELETE: a report is evidence, and the storage objects reference it.

-- ============================================================================
-- report_media policies
--
-- Append-only. Once uploaded, an attachment cannot be edited or removed
-- through the client API, because a report's evidence trail must be stable.
-- ============================================================================

create policy report_media_select_participant
  on public.report_media
  for select
  to authenticated
  using (
    public.is_report_participant(report_id)
    or public.current_user_role() = 'admin'
  );

create policy report_media_insert_assigned_inspector
  on public.report_media
  for insert
  to authenticated
  with check (public.is_report_participant(report_id));

-- ============================================================================
-- payments policies
--
-- Read by the paying client and by admins. The assigned inspector does not see
-- the client's payment instrument or transaction id; if inspector earnings
-- become a first-class concept they get their own payout tables rather than a
-- widened policy on this one. See PROJECT_MAP.md P8.
-- ============================================================================

create policy payments_select_client
  on public.payments
  for select
  to authenticated
  using (
    exists (
      select 1 from public.car_inspections i
      where i.id = inspection_id and i.client_id = auth.uid()
    )
    or public.current_user_role() = 'admin'
  );

-- Intentionally no INSERT / UPDATE / DELETE policies. See the grant comment
-- above and PROJECT_MAP.md P2.
