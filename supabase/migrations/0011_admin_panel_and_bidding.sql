-- Moaen (معاين) — 0011_admin_panel_and_bidding.sql
-- Admin role and panel, account verification, account/centre suspension, and
-- buyer-budget bidding with the platform commission separated out of it.
--
-- Three business rules land here, and they interlock:
--
--   1. Buyers use the platform the moment they sign up, if not blocked.
--      Inspectors do nothing until an admin approves them, and are told when
--      they are.
--   2. An admin can approve or reject inspectors, suspend buyers, inspectors
--      and repair centres, read the money, read every order, and set the
--      platform's commission.
--   3. The buyer proposes a budget. The inspector's earnings are the budget
--      minus the platform's fee, and either side may move once.
--
-- The money rule is the one with the sharp edges, so it is worth stating
-- plainly. `car_inspections.price` used to hold the estimate the buyer was
-- *shown* — a figure this codebase computed, not one the buyer chose. It now
-- holds the budget the buyer *proposes*, which is the original meaning of the
-- column and the one the business has asked for. Nothing about the column
-- changes; what changes is who decides its value.
--
-- Three money columns join it, and each exists for one reason:
--
--   platform_fee  snapshotted at creation from `platform_settings`. An admin who
--                 changes the commission tomorrow must not restate a deal the
--                 buyer priced yesterday, so the fee is copied onto the row and
--                 then never written again.
--   inspector_net  what the inspector keeps. Never written by a client — a
--                 trigger derives it from the budget and the snapshot, or copies
--                 it off an accepted counter-offer.
--   agreed_total   what the buyer pays, stored rather than derived, because the
--                 invoice is a fact about a transaction and not a
--                 recomputation against a setting that may since have moved.
--
-- The commission split is between the *buyer* and the *inspector*. A centre's own
-- fee (`center_fee`, migration 0007) is a separate pass-through the inspector
-- supplies when booking, recorded against the inspection but deliberately kept
-- out of the bid arithmetic: adding it to the net would charge the commission on
-- money the platform never collected.
--
-- Fully re-runnable. `add column if not exists`, drop-then-add named constraints,
-- `drop trigger if exists`, and the one-time backfill is guarded by a column
-- comment rather than by a row count, so a second run cannot re-approve an
-- inspector an admin has since rejected.

-- ============================================================================
-- 1. Enumerated types
-- ============================================================================

create type public.commission_type as enum ('fixed', 'percent');

-- `none`     nothing negotiated; the job is priced at the buyer's budget.
-- `pending`  the assigned inspector has offered a different amount and the buyer
--            has not answered.
-- `agreed`   settled. Either at the buyer's budget on acceptance, or at an
--            accepted counter-offer.
-- `declined` the buyer refused the counter-offer. The job is still claimed; the
--            inspector may submit a new one, which supersedes it.
create type public.bid_status as enum ('none', 'pending', 'agreed', 'declined');

create type public.admin_notification_kind as enum (
  'inspector_approved',
  'inspector_rejected'
);

-- ============================================================================
-- 2. Identity and verification on `users`
-- ============================================================================

alter table public.users add column if not exists id_photo_url text;
alter table public.users add column if not exists is_approved boolean not null default false;
alter table public.users add column if not exists is_blocked boolean not null default false;

-- Why an account is suspended or was turned down. Kept as a column rather than
-- folded into a status enum because the two are independent: a rejected inspector
-- is not blocked, they simply never got verified, and an approved inspector can
-- still be suspended next month.
alter table public.users add column if not exists rejection_reason text;
alter table public.users add column if not exists blocked_reason text;

-- Who approved, and when. `approved_by` is not a foreign key: an admin's own row
-- is deletable (an account can be closed), and a deleted approver should not
-- cascade away the audit trail of who let an inspector in.
alter table public.users add column if not exists approved_at timestamptz;
alter table public.users add column if not exists approved_by uuid;

comment on column public.users.id_photo_url is
  'Object path in the private `identity-documents` bucket. Not a URL: the bucket is private, so a signed URL is minted per read.';
comment on column public.users.is_approved is
  'Whether an admin has verified this inspector. Meaningless for a client, who uses the platform as soon as they are not blocked.';

create index if not exists users_review_queue_idx
  on public.users (is_approved, is_blocked)
  where role = 'inspector';

create index if not exists users_blocked_idx
  on public.users (is_blocked)
  where is_blocked;

-- ----------------------------------------------------------------------------
-- The one-time backfill
--
-- `is_approved` defaults to false, so applying this file would lock out every
-- inspector already working on the platform. They are grandfathered in: they are
-- operating today, most of them have completed jobs, and re-verifying them is a
-- business decision rather than a schema one. The cost of that choice is visible
-- rather than hidden — they hold no `id_photo_url`, and the admin panel's
-- verification queue filters on exactly that so the gap can be closed by hand.
--
-- The guard is the presence of the column comment above, not a row count. A row
-- count would re-approve anyone an admin rejected since the first run, which is
-- the one outcome this file must never have on a second application.
-- ----------------------------------------------------------------------------

do $$
begin
  if not exists (
    select 1
      from pg_description
     where objoid = 'public.users'::regclass
       and classoid = 'pg_class'::regclass
       and objsubid = (
         select attnum from pg_attribute
          where attrelid = 'public.users'::regclass
            and attname = 'is_approved'
       )
  ) then
    update public.users set is_approved = true where role = 'inspector';
  end if;
end;
$$;

comment on column public.users.is_approved is
  'Whether an admin has verified this inspector. Meaningless for a client, who uses the platform as soon as they are not blocked.';

-- ----------------------------------------------------------------------------
-- `handle_new_user` — carry the ID photo path, and default approval by role
--
-- The photo's *path* arrives as signup metadata, because the object is uploaded
-- after the row exists: Supabase Auth mints the user id itself, so there is no
-- id to write an object under until sign-up has returned. The client uploads
-- immediately afterwards and points `id_photo_url` at the result; see
-- `IdentityRepository.uploadIdPhoto`.
--
-- A client is provisioned approved. Not a privilege — approval gates inspectors
-- and nothing else — but it means the admin panel does not show a queue full of
-- buyers waiting on a verification that was never going to happen.
-- ----------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role public.user_role;
begin
  v_role := case
    when new.raw_user_meta_data ->> 'role' = 'inspector'
      then 'inspector'::public.user_role
    else 'client'::public.user_role
  end;

  insert into public.users (
    id, full_name, email, phone, role, location_city, id_photo_url, is_approved
  )
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
      split_part(new.email, '@', 1)
    ),
    new.email,
    nullif(trim(new.raw_user_meta_data ->> 'phone'), ''),
    v_role,
    nullif(trim(new.raw_user_meta_data ->> 'city'), ''),
    nullif(trim(new.raw_user_meta_data ->> 'id_photo_url'), ''),
    v_role = 'client'
  );
  return new;
end;
$$;

-- ----------------------------------------------------------------------------
-- Only an admin writes the verification and suspension flags
--
-- The trigger, not the policy. A policy would have to name every column, and the
-- next migration adding one would widen the hole silently. Here the rule is
-- stated once, as a field list: these four columns belong to the administration
-- screen and to nothing else.
--
-- `current_user in ('service_role', 'postgres', 'supabase_admin')` is the escape
-- hatch for the SQL editor and the service key. A client connecting through
-- PostgREST arrives as `authenticated`, whatever it claims in its JWT, so the
-- list cannot be reached from outside.
-- ----------------------------------------------------------------------------

create or replace function public.protect_verification_flags()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.is_approved    is distinct from old.is_approved
     or new.is_blocked  is distinct from old.is_blocked
     or new.approved_at is distinct from old.approved_at
     or new.approved_by is distinct from old.approved_by
  then
    if current_user not in ('service_role', 'postgres', 'supabase_admin') then
      if coalesce(public.current_user_role() <> 'admin', true) then
        raise exception 'verification and suspension may only be changed by an administrator'
          using errcode = 'insufficient_privilege';
      end if;
    end if;
  end if;

  -- `id_photo_url` is not admin-only — a user attaches their own document — but
  -- only their own. Without the `old.id` comparison a client could rewrite
  -- another account's photo, and an admin could not correct a typo.
  if new.id_photo_url is distinct from old.id_photo_url
     and current_user not in ('service_role', 'postgres', 'supabase_admin')
     and auth.uid() is distinct from old.id
  then
    raise exception 'a user may only set their own id photo'
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$$;

drop trigger if exists users_verification_guard on public.users;
create trigger users_verification_guard
  before update on public.users
  for each row execute function public.protect_verification_flags();

-- ============================================================================
-- 3. Identity documents — the private bucket
-- ============================================================================
--
-- A separate bucket from `inspection-media`, and it has to be one.
--
-- `inspection-media`'s read policy is `is_inspection_participant(name's first
-- path segment)`, which parses that segment as an *inspection* uuid. An identity
-- document is filed under the *user's* uuid, so that predicate returns false and
-- the object is unreadable — correct, but by accident, and the write side would
-- have been worse: `is_inspection_inspector` would have let any inspector file a
-- document under any account by naming that account in the path.
--
-- The rules here are the plainest version of the question:
--
--   * you may read your own document, and an admin may read anyone's, because
--     reviewing it is the entire job;
--   * you may write your own document and nobody else's, including an admin's —
--     an admin who could plant a document on an account would be able to make
--     that account look verified by something other than the holder;
--   * nobody may delete. A rejected applicant's ID stays on file, because
--     "why was this refused" is the next question an admin will ask. Re-uploading
--     replaces the object in place, since the path is deterministic.
--
-- No UPDATE would be defensible here — the same "evidence is immutable" rule
-- migration 0003 applies — but that rule assumes the evidence is the inspector's,
-- and this is a document the holder may legitimately correct before submitting it.
-- The UPDATE is therefore allowed and it is confined to one's own object.

insert into storage.buckets (id, name, public)
values ('identity-documents', 'identity-documents', false)
on conflict (id) do nothing;

comment on storage.buckets is 'Private buckets: inspection-reports, inspection-media, identity-documents.';

-- Object path convention: identity-documents/{user_id}/id.{ext}
--
-- Deterministic on purpose. A random filename would make "re-upload" leave the old
-- object orphaned in a bucket nobody can delete from, and would need a cleanup job
-- to keep honest — for no benefit, since two documents for one account is not a
-- state the product has.

-- The path segment *is* the ownership check, so no `owner_id` predicate appears
-- in any of these. `storage.objects.owner_id` is the account that ran the upload,
-- which for an admin re-filing a document would be the admin — and the column's
-- name has changed between Supabase releases, which is one more reason not to
-- depend on it when the path already says whose document this is.

drop policy if exists identity_documents_read on storage.objects;
create policy identity_documents_read
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'identity-documents'
    and (
      public.is_admin()
      or (
        not public.current_user_blocked()
        and (storage.foldername(name))[1] = auth.uid()::text
      )
    )
  );

drop policy if exists identity_documents_insert on storage.objects;
create policy identity_documents_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'identity-documents'
    and not public.current_user_blocked()
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists identity_documents_update on storage.objects;
create policy identity_documents_update
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'identity-documents'
    and not public.current_user_blocked()
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ============================================================================
-- 4. Centres get suspended too
-- ============================================================================
--
-- "Block a repair centre" needs a flag on the centre. It is enforced as a filter
-- on the SELECT policy in section 10 rather than as a trigger, because there is no
-- write for it to stop: nothing about a suspension should make an existing
-- booking unreadable to the two parties who hold it.

alter table public.inspection_centres
  add column if not exists is_blocked boolean not null default false;

comment on column public.inspection_centres.is_blocked is
  'Suspended by an admin: hidden from the booking dropdown. Existing bookings keep working.';

create index if not exists inspection_centres_blocked_idx
  on public.inspection_centres (is_blocked)
  where is_blocked;

-- ============================================================================
-- 5. Platform settings — the commission
-- ============================================================================

create table if not exists public.platform_settings (
  -- The single-row guard. `id` may only be true, so the table can hold exactly
  -- one row and no more, which is a constraint rather than a convention.
  id               boolean primary key default true check (id),
  commission_type  public.commission_type not null default 'fixed',
  -- A fixed amount in SAR, or a percentage of the budget when the type is
  -- 'percent'. One column for both because there is only ever one live value and
  -- two nullable columns would leave a half-configured row the rest of the app
  -- has to guess about. `numeric(12,4)` because 10% is 10.0000 and a
  -- `numeric(12,2)` would round it to 10.00 by a mechanism nobody would notice.
  commission_value numeric(12, 4) not null default 49
    check (commission_value >= 0)
    check (
      (commission_type = 'percent' and commission_value <= 100)
      or commission_type = 'fixed'
    ),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.users (id) on delete set null
);

comment on table public.platform_settings is
  'One row. The platform commission, applied to a request when it is created and frozen onto that request.';
comment on column public.platform_settings.commission_value is
  'SAR when the type is ''fixed'', percent when it is ''percent''.';

alter table public.platform_settings enable row level security;

-- Provisioned at migration time so `platform_fee_for` never has to handle a
-- missing row. `on conflict do nothing` because the file is re-runnable and a
-- second run must not reset a commission an admin has since changed.
insert into public.platform_settings (id, commission_type, commission_value)
values (true, 'fixed', 49)
on conflict (id) do nothing;

-- ----------------------------------------------------------------------------
-- The fee, as the database computes it
--
-- Two guards on the result, both load-bearing:
--
--   * never more than the budget itself, so `budget - fee` can never go negative
--     and turn an inspector's earnings into a debt;
--   * zero for a zero or negative budget, rather than a negative fee.
--
-- SECURITY DEFINER because the trigger below calls it while inserting into
-- `car_inspections` as a client: `authenticated` has SELECT on the settings table
-- for display purposes, but the fee that lands on a row should not depend on
-- that grant surviving the next migration.
-- ----------------------------------------------------------------------------

create or replace function public.platform_fee_for(p_total numeric)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    least(
      case s.commission_type
        when 'percent' then round(p_total * s.commission_value / 100, 2)
        else s.commission_value
      end,
      p_total
    ),
    0
  )
  from public.platform_settings s
   where s.id;
$$;

revoke all on function public.platform_fee_for(numeric) from public, anon;
grant execute on function public.platform_fee_for(numeric) to authenticated;

-- ============================================================================
-- 6. Bidding columns on `car_inspections`
-- ============================================================================

alter table public.car_inspections add column if not exists platform_fee numeric(12, 2);
alter table public.car_inspections add column if not exists inspector_net numeric(12, 2);
alter table public.car_inspections add column if not exists agreed_total numeric(12, 2);
alter table public.car_inspections add column if not exists bid_status public.bid_status not null default 'none';
alter table public.car_inspections add column if not exists agreed_at timestamptz;
alter table public.car_inspections add column if not exists counter_note text;

alter table public.car_inspections
  drop constraint if exists car_inspections_inspector_net_positive;
alter table public.car_inspections
  add constraint car_inspections_inspector_net_positive
  check (inspector_net is null or inspector_net >= 0);

alter table public.car_inspections
  drop constraint if exists car_inspections_agreed_total_positive;
alter table public.car_inspections
  add constraint car_inspections_agreed_total_positive
  check (agreed_total is null or agreed_total >= 0);

comment on column public.car_inspections.price is
  'The budget the buyer proposed, inclusive of the platform fee. Priced against `platform_fee` at creation and frozen thereafter by `enforce_inspection_transition`.';
comment on column public.car_inspections.platform_fee is
  'The platform commission, snapshotted from `platform_settings` when the request was created and never changed again.';
comment on column public.car_inspections.inspector_net is
  'What the inspector keeps. Written only by `enforce_bidding`.';
comment on column public.car_inspections.agreed_total is
  'What the buyer pays. Stored rather than derived: the invoice is a fact about the transaction.';
comment on column public.car_inspections.counter_note is
  'The buyer''s one line on why they declined, shown to the inspector on the next offer form.';

-- ----------------------------------------------------------------------------
-- The fee snapshot, and the rule that no client writes the money
--
-- SECURITY DEFINER, unlike migration 0009's transition trigger, and for a
-- structural reason rather than a stylistic one: this function has to *write* —
-- settling an offer means moving `inspection_bids` rows, which no client has an
-- UPDATE policy for and should have. It still does its own identity checks, and
-- the check is `auth.uid()`, which reads the JWT and is unaffected by the
-- elevated rights.
-- ----------------------------------------------------------------------------

create or replace function public.enforce_bidding()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_incoming_net    numeric;
  v_incoming_total  numeric;
  v_incoming_agreed timestamptz;
  -- Named rather than `%rowtype`: this function is created before
  -- `public.inspection_bids` exists, and plpgsql resolves a DECLARE type when the
  -- function is created, not when it first runs. The table reference inside the
  -- body is a different matter — plpgsql parses SQL lazily, on first execution —
  -- so only the declaration needed spelling out.
  v_bid_id          uuid;
  v_bid_net         numeric;
  v_bid_total       numeric;
  v_is_buyer        boolean;
begin
  -- ==========================================================================
  -- INSERT — the buyer proposes, the database prices
  --
  -- Every money column is assigned here rather than accepted from the client, so
  -- a request cannot be filed with a pre-cooked net or a zero fee. `price` is the
  -- one exception: it is the buyer's own budget and nobody else's to invent.
  -- ==========================================================================
  if tg_op = 'INSERT' then
    new.platform_fee  := public.platform_fee_for(new.price);
    new.inspector_net := null;
    new.agreed_total  := null;
    new.bid_status    := 'none';
    new.agreed_at     := null;
    return new;
  end if;

  -- ==========================================================================
  -- The snapshot is permanent
  --
  -- Without this an admin changing the commission from 49 to 10 would silently
  -- take 39 SAR from every open inspection and hand it back to nobody. The
  -- buyer priced their budget against 49 and accepted that number.
  -- ==========================================================================
  if new.platform_fee is distinct from old.platform_fee then
    raise exception 'the platform fee is fixed when the request is created'
      using errcode = 'check_violation';
  end if;

  -- ==========================================================================
  -- Claiming the job settles it at the buyer's budget
  --
  -- The common case needs no negotiation at all: an inspector who is happy with
  -- the posted budget simply claims, and `bid_status` goes straight to 'agreed'.
  -- The counter-offer in section 7 is an alternative to that, not a stage after
  -- it, which is why this fires only while the row is still unsettled.
  --
  -- Read from `old`, not `new`: `enforce_bidding` sorts before
  -- `enforce_inspection_transition` alphabetically, so rule 1's
  -- `new.inspector_id := auth.uid()` has not run yet and `new` still describes
  -- the pending job.
  -- ==========================================================================
  if old.status = 'pending' and new.status = 'accepted' then
    if old.bid_status = 'none' then
      new.inspector_net := old.price - old.platform_fee;
      new.agreed_total  := old.price;
      new.bid_status    := 'agreed';
      new.agreed_at     := now();
    end if;
  end if;

  -- ==========================================================================
  -- The buyer answers a counter-offer
  --
  -- The buyer writes one word, `bid_status`. The amounts come off the offer row,
  -- so a buyer cannot agree to a number that was never offered — and cannot set
  -- an arbitrary one either, which is why the columns below are rejected outright
  -- a few lines down.
  -- ==========================================================================
  -- Two arguments: migration 0010's `is_buyer_row` reads `auth.uid()` itself and
  -- answers "is the caller the client and not also the inspector". Called with the
  -- row's *current* ids, so it is true only for the buyer of this inspection.
  v_is_buyer := public.is_buyer_row(old.client_id, old.inspector_id);

  if new.bid_status is distinct from old.bid_status and v_is_buyer then
    select id, net_amount, total_amount
      into v_bid_id, v_bid_net, v_bid_total
      from public.inspection_bids
     where inspection_id = old.id
       and status = 'pending'
     order by round desc
     limit 1;

    if v_bid_id is null then
      raise exception 'there is no counter-offer to respond to'
        using errcode = 'check_violation';
    end if;

    if new.bid_status = 'agreed' then
      new.inspector_net := v_bid_net;
      new.agreed_total  := v_bid_total;
      new.agreed_at     := now();
      update public.inspection_bids
         set status = 'accepted', responded_at = now()
       where id = v_bid_id;
    elsif new.bid_status = 'declined' then
      new.agreed_at := now();
      update public.inspection_bids
         set status = 'declined', responded_at = now()
       where id = v_bid_id;
    else
      raise exception 'a buyer may only agree to or decline a counter-offer'
        using errcode = 'check_violation';
    end if;
  end if;

  -- ==========================================================================
  -- Nobody writes the money by hand
  --
  -- Everything above derives these three columns. A caller that tried to set
  -- them directly would have them overwritten, so the check is not "the value is
  -- wrong" — it is "the value arrived from somewhere it should not have", which
  -- is worth refusing loudly rather than quietly correcting.
  -- ==========================================================================
  v_incoming_net    := new.inspector_net;
  v_incoming_total  := new.agreed_total;
  v_incoming_agreed := new.agreed_at;

  if auth.uid() is not null
     and current_user not in ('service_role', 'postgres', 'supabase_admin')
     and (
       v_incoming_net    is distinct from new.inspector_net
       or v_incoming_total  is distinct from new.agreed_total
       or v_incoming_agreed is distinct from new.agreed_at
     )
  then
    raise exception 'the agreed amounts are written by the bidding rules, not by the caller'
      using errcode = 'insufficient_privilege';
  end if;

  -- ==========================================================================
  -- `bid_status` is not a field either party writes freely
  --
  -- It moves in exactly three ways: the settlement branch above, the buyer's
  -- response branch above, and `sync_bid_status` firing when an offer lands. The
  -- third is a trigger-initiated write, identified by being nested inside another
  -- trigger — a statement arriving from PostgREST is always at depth 1, so this
  -- is a property of the call stack that a client cannot forge, rather than a
  -- session flag it could set for itself.
  -- ==========================================================================
  if new.bid_status is distinct from old.bid_status
     and not v_is_buyer
     and pg_trigger_depth() = 1
     and auth.uid() is not null
     and current_user not in ('service_role', 'postgres', 'supabase_admin')
  then
    raise exception 'bid status is derived, not written'
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$$;

drop trigger if exists car_inspections_bid_guard on public.car_inspections;
create trigger car_inspections_bid_guard
  before insert or update on public.car_inspections
  for each row execute function public.enforce_bidding();

-- ============================================================================
-- 7. `inspection_bids` - the offers
--
-- Each row is self-describing: it carries the fee that applied when it was made
-- and the total it worked out to, so an offer reads the same years later
-- whatever the commission is set to now. That is the same reasoning as the
-- `platform_fee` snapshot on the inspection, one level down.
-- ============================================================================

create table if not exists public.inspection_bids (
  id            uuid primary key default gen_random_uuid(),
  inspection_id uuid not null references public.car_inspections (id) on delete cascade,
  inspector_id  uuid not null references public.users (id) on delete cascade,

  -- What the inspector asks to keep. A *net*: the platform's fee is not the
  -- inspector's concern, and quoting the gross would let them argue about a
  -- commission they have no part in.
  net_amount    numeric(12, 2) not null check (net_amount > 0),

  -- The buyer's total for this offer. Both are filled in by `seal_bid`, never by
  -- the client: `total_amount` is arithmetic and the inspector should not be
  -- asked to do it twice.
  platform_fee  numeric(12, 2) not null default 0 check (platform_fee >= 0),
  total_amount  numeric(12, 2) not null default 0 check (total_amount >= 0),

  -- The attempt number. One while nothing has been refused; two after a decline,
  -- and so on. It exists so the buyer can say "that's your second offer" and so a
  -- superseded row is still legible in the history.
  round         integer not null default 1 check (round > 0),

  status        public.bid_status not null default 'pending',

  -- One line from the inspector. Free text, so the column is sized generously and
  -- nothing is validated on it beyond not being absurd.
  note          text check (note is null or char_length(note) <= 500),

  created_at    timestamptz not null default now(),
  responded_at  timestamptz
);

comment on table public.inspection_bids is
  'Counter-offers on an inspection. Written by the assigned inspector only; read by that inspector, the buyer, and an admin.';
comment on column public.inspection_bids.net_amount is
  'What the inspector keeps, after the platform fee. The gross is derived as total_amount.';

-- At most one open offer per inspection. A partial unique index rather than a
-- check constraint because `status` is one column of eight and the rule only
-- binds on one of its values.
create unique index if not exists inspection_bids_one_open_per_inspection
  on public.inspection_bids (inspection_id)
  where status = 'pending';

create index if not exists inspection_bids_inspection_idx
  on public.inspection_bids (inspection_id, round desc);

create index if not exists inspection_bids_inspector_idx
  on public.inspection_bids (inspector_id, created_at desc);

-- ----------------------------------------------------------------------------
-- Seal the offer
--
-- The client sends a net and a note. Everything else — the fee, the total, the
-- round, the attempt number — is settled here, so an offer cannot claim a
-- commission that was never charged or inflate its round count.
--
-- The superseded offer is closed from inside this function, which is why the
-- function is SECURITY DEFINER: `inspection_bids` has no client UPDATE policy and
-- does not need one. A second offer is the only way to replace the first, so
-- "who withdrew it and when" is a fact rather than an inference.
-- ----------------------------------------------------------------------------

create or replace function public.seal_bid()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inspection public.car_inspections%rowtype;
  v_next_round integer;
begin
  select * into v_inspection
    from public.car_inspections
   where id = new.inspection_id;

  if v_inspection.id is null then
    raise exception 'no such inspection' using errcode = 'foreign_key_violation';
  end if;

  -- The claimed inspector, or an admin acting for them. Not "any signed-in
  -- user": an offer is a negotiation on one named job, and the whole point of
  -- `bid_status` is that only one person is on the other side of it.
  if v_inspection.inspector_id is distinct from auth.uid()
     and coalesce(public.current_user_role() <> 'admin', true)
  then
    raise exception 'only the inspector holding this job may submit an offer'
      using errcode = 'insufficient_privilege';
  end if;

  -- Not before the job is claimed. An inspector has nothing to counter while the
  -- request is still on the board and anyone may take it.
  if v_inspection.status = 'pending' then
    raise exception 'an offer can only be submitted once the job has been claimed'
      using errcode = 'check_violation';
  end if;

  if v_inspection.status in ('completed', 'cancelled') then
    raise exception 'this inspection is closed'
      using errcode = 'check_violation';
  end if;

  -- An offer above the budget is not a counter-offer, it is a different job. The
  -- database does not stop it — the buyer can always choose to pay more — but the
  -- round is recorded so the buyer's side shows it plainly.
  select coalesce(max(round), 0) + 1 into v_next_round
    from public.inspection_bids
   where inspection_id = new.inspection_id;

  update public.inspection_bids
     set status = 'declined',
         responded_at = now()
   where inspection_id = new.inspection_id
     and status = 'pending';

  new.round         := v_next_round;
  new.platform_fee  := v_inspection.platform_fee;
  new.total_amount  := new.net_amount + new.platform_fee;
  new.status        := 'pending';
  new.responded_at  := null;
  new.inspector_id  := coalesce(auth.uid(), v_inspection.inspector_id);

  return new;
end;
$$;

drop trigger if exists inspection_bids_seal on public.inspection_bids;
create trigger inspection_bids_seal
  before insert on public.inspection_bids
  for each row execute function public.seal_bid();

-- ----------------------------------------------------------------------------
-- Move the inspection to 'pending' when an offer lands
--
-- So the board and the buyer's screen agree with the offers table without either
-- having to read it. Returns null because the effect is entirely on another row.
--
-- This write runs the whole `car_inspections` trigger chain, including
-- `enforce_inspection_transition` and `enforce_custom_centre`. Both are inert
-- here: nothing about the status, the assignment or a custom centre changes.
-- ----------------------------------------------------------------------------

create or replace function public.sync_bid_status()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  update public.car_inspections
     set bid_status = 'pending'
   where id = new.inspection_id
     and bid_status is distinct from 'pending';
  return null;
end;
$$;

drop trigger if exists inspection_bids_sync_status on public.inspection_bids;
create trigger inspection_bids_sync_status
  after insert on public.inspection_bids
  for each row execute function public.sync_bid_status();

-- ============================================================================
-- 8. Settlements carry their own fee
--
-- `payments` is written by the service role and read by nobody but the two
-- parties, so there is no client code path to keep in step. The column exists
-- because the financial overview is the one place the platform's income is
-- stated as a fact, and re-deriving it from today's commission setting would
-- restate history every time an admin moved the number.
-- ============================================================================

alter table public.payments add column if not exists platform_fee_amount numeric(12, 2);

comment on column public.payments.platform_fee_amount is
  'The platform commission taken on this payment, captured at settlement.';

-- ============================================================================
-- 9. Admin helpers
-- ============================================================================

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(public.current_user_role() = 'admin', false);
$$;

create or replace function public.current_user_blocked()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select u.is_blocked from public.users u where u.id = auth.uid()),
    false
  );
$$;

create or replace function public.current_user_approved()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select u.is_approved from public.users u where u.id = auth.uid()),
    false
  );
$$;

revoke all on function public.is_admin() from public, anon;
revoke all on function public.current_user_blocked() from public, anon;
revoke all on function public.current_user_approved() from public, anon;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.current_user_blocked() to authenticated;
grant execute on function public.current_user_approved() to authenticated;

-- ----------------------------------------------------------------------------
-- Where the gate lives, and why not everywhere
--
-- `is_approved` is required to *see the board* and to *claim a job* — the two
-- things an unverified account would otherwise use the platform for. It is not
-- required to read an inspection the inspector has already claimed, because an
-- inspector who was approved and then re-reviewed should not lose access to work
-- already in their hands.
--
-- `is_blocked` is required on every write and on every participant read. It is
-- not required to read the centre catalogue or the commission: a suspended
-- account looking at a price sheet is not a disclosure, and refusing it would
-- only produce a support ticket about a blank screen.
-- ----------------------------------------------------------------------------

-- ============================================================================
-- 10. RLS for the new and widened tables
-- ============================================================================

alter table public.inspection_bids enable row level security;

-- ---- grants

grant select on public.platform_settings to authenticated;
grant select, insert on public.inspection_bids to authenticated;

-- ---- platform_settings: everyone reads, an admin writes

drop policy if exists platform_settings_read on public.platform_settings;
create policy platform_settings_read
  on public.platform_settings
  for select
  to authenticated
  using (true);

drop policy if exists platform_settings_write_admin on public.platform_settings;
create policy platform_settings_write_admin
  on public.platform_settings
  for insert, update, delete
  to authenticated
  using (public.is_admin() and not public.current_user_blocked())
  with check (public.is_admin());

-- ---- inspection_bids

drop policy if exists inspection_bids_read_participant on public.inspection_bids;
create policy inspection_bids_read_participant
  on public.inspection_bids
  for select
  to authenticated
  using (
    public.is_admin()
    or public.is_inspection_participant(inspection_id)
  );

-- INSERT only. The "which job, whose offer, which round" rules live in
-- `seal_bid`, because they need to read the parent row and write to this one —
-- neither of which a policy may do.
drop policy if exists inspection_bids_insert_inspector on public.inspection_bids;
create policy inspection_bids_insert_inspector
  on public.inspection_bids
  for insert
  to authenticated
  with check (
    not public.current_user_blocked()
    and public.current_user_approved()
    and inspector_id = auth.uid()
  );

-- ============================================================================
-- 11. Admin reach on the tables that already exist
--
-- Every one of these is a *widen*, never a replacement. Migration 0002's
-- participant policies stay exactly as written, so closing an admin hole cannot
-- reopen one.
-- ============================================================================

-- ---- users: an admin sees and manages everyone
--
-- 0002's `users_select_self_or_admin` re-created with the suspension gate. RLS
-- ORs permissive policies together, so *adding* a narrow admin policy would have
-- widened nothing: 0002's own `or public.current_user_role() = 'admin'` already
-- let an admin read anyone. The gate has to go into the original.
--
-- An admin needs to see a blocked row in order to unblock it, so this does *not*
-- filter on the target's `is_blocked` — only on the caller's own. What a blocked
-- account cannot see is itself.

drop policy if exists users_select_self_or_admin on public.users;
create policy users_select_self_or_admin
  on public.users
  for select
  to authenticated
  using (
    (id = auth.uid() or public.current_user_role() = 'admin')
    and not public.current_user_blocked()
  );

drop policy if exists users_update_self on public.users;
create policy users_update_self
  on public.users
  for update
  to authenticated
  using (id = auth.uid() and not public.current_user_blocked())
  with check (id = auth.uid());

drop policy if exists users_select_admin on public.users;
create policy users_select_admin
  on public.users
  for select
  to authenticated
  using (public.is_admin() and not public.current_user_blocked());

drop policy if exists users_update_admin on public.users;
create policy users_update_admin
  on public.users
  for update
  to authenticated
  using (public.is_admin() and not public.current_user_blocked())
  with check (public.is_admin());

-- ---- car_inspections: the orders monitor
--
-- `inspections_select_participant` already admitted an admin, so this is the same
-- situation as `users_select_admin` above and is kept only because the admin panel
-- also needs to *write* an inspection — cancelling an order, most often, which
-- `enforce_inspection_transition` allows and no other role can do for someone
-- else's row.

drop policy if exists inspections_select_admin on public.car_inspections;
create policy inspections_select_admin
  on public.car_inspections
  for select
  to authenticated
  using (public.is_admin() and not public.current_user_blocked());

drop policy if exists inspections_update_admin on public.car_inspections;
create policy inspections_update_admin
  on public.car_inspections
  for update
  to authenticated
  using (public.is_admin() and not public.current_user_blocked())
  with check (public.is_admin());

-- ---- payments: the financial overview

drop policy if exists payments_select_admin on public.payments;
create policy payments_select_admin
  on public.payments
  for select
  to authenticated
  using (public.is_admin() and not public.current_user_blocked());

-- ---- inspection_centres: a suspended centre drops out of the dropdown
--
-- 0007's `inspection_centres_select_authenticated` is *dropped*, not merely
-- supplemented, and that is the whole difficulty with this table. Its body was
-- `using (true)` — readable by any signed-in user, because an inspector picks a
-- centre before the request has an inspector and so there is no participant to test
-- against. Adding a narrower policy beside it would have widened nothing and
-- narrowed nothing: RLS ORs permissive policies together, so `using (true)` swallows
-- any second disjunction outright, and `is_blocked` would have been a column nothing
-- consulted. The same trap the `users` and `car_inspections` sections below describe
-- in prose, reached from the other direction.
--
-- The `is_admin()` arm is load-bearing rather than a convenience: an admin has to be
-- able to see a blocked centre in order to unblock it, which is the same argument as
-- for `users_select_self_or_admin`.
drop policy if exists inspection_centres_select_authenticated on public.inspection_centres;
drop policy if exists inspection_centres_read_active on public.inspection_centres;
create policy inspection_centres_read_active
  on public.inspection_centres
  for select
  to authenticated
  using (
    (not is_blocked or public.is_admin())
    and not public.current_user_blocked()
  );

drop policy if exists inspection_centres_update_admin on public.inspection_centres;
create policy inspection_centres_update_admin
  on public.inspection_centres
  for update
  to authenticated
  using (public.is_admin() and not public.current_user_blocked())
  with check (public.is_admin());

-- ---- the job board: an unverified inspector sees an empty board
--
-- 0002's `inspections_select_board` re-created with the verification gate added
-- and nothing else changed — including the case-insensitive city compare, which
-- is what stops "Cairo" and " cairo " from silently producing an empty board.

drop policy if exists inspections_select_board on public.car_inspections;
create policy inspections_select_board
  on public.car_inspections
  for select
  to authenticated
  using (
    status = 'pending'
    and public.current_user_role() = 'inspector'
    and public.current_user_approved()
    and not public.current_user_blocked()
    and lower(btrim(city)) = lower(btrim(public.current_user_city()))
  );

-- ---- claiming a job, and driving it forward
--
-- 0002's `inspections_update_inspector`, re-created with the two gates the rest of
-- this file uses. The claim arm (`status = 'pending'` in the caller's city) is what
-- an unverified inspector is stopped from, which is the whole point of the
-- requirement; the assigned arm is what they use once they hold the job.
--
-- An earlier draft of this comment claimed the assigned arm "stays open for an
-- inspector who was approved and later suspended, so their in-flight work is not
-- stranded", and the policy said the opposite: `not current_user_blocked()` sat
-- *outside* the parenthesised disjunction, so it closed both arms and the prose
-- described a branch that did not exist. The uniform reading is the one kept —
-- suspension stops everything, and the remedy for a stranded job is the Orders tab's
-- per-order cancel. The report-chain policies below state the same trade, because
-- leaving a suspended inspector able to finish their report while being unable to
-- move the job it belongs to would be the least coherent of the three options.

drop policy if exists inspections_update_inspector on public.car_inspections;
create policy inspections_update_inspector
  on public.car_inspections
  for update
  to authenticated
  using (
    public.current_user_role() = 'inspector'
    and not public.current_user_blocked()
    and (
      inspector_id = auth.uid()
      or (
        public.current_user_approved()
        and status = 'pending'
        and lower(btrim(city)) = lower(btrim(public.current_user_city()))
      )
    )
  )
  with check (public.current_user_role() = 'inspector');

-- ---- the buyer's own write
--
-- 0009's `inspections_update_client`, re-created with the suspension gate.
-- `cancelled` stays absent from the state list: it is terminal, so there is
-- nothing left for the buyer to write, and `completed` stays absent because the
-- inspector owns that transition.

drop policy if exists inspections_update_client on public.car_inspections;
create policy inspections_update_client
  on public.car_inspections
  for update
  to authenticated
  using (
    client_id = auth.uid()
    and not public.current_user_blocked()
    and status in ('pending', 'accepted', 'in_progress')
  )
  with check (client_id = auth.uid());

-- ---- the participant read
--
-- 0002's `inspections_select_participant` plus the suspension gate, re-created as
-- one policy rather than split into a client arm and an inspector arm. Two
-- policies would read better and mean nothing: RLS ORs them together, and the
-- third disjunct already in the original — `current_user_role() = 'admin'` — is
-- the reason this file's `inspections_select_admin` adds nothing an admin did not
-- already have for reads, and only ever narrows.
--
-- This is also the one place a suspension has teeth on a buyer. An inspector
-- blocked mid-job keeps write access to their assigned row above, but loses read
-- access to it here, which is deliberate: a suspended account should not be
-- reading other people's inspection details either.

drop policy if exists inspections_select_participant on public.car_inspections;
create policy inspections_select_participant
  on public.car_inspections
  for select
  to authenticated
  using (
    (
      client_id = auth.uid()
      or inspector_id = auth.uid()
      or public.current_user_role() = 'admin'
    )
    and not public.current_user_blocked()
  );

-- ---- filing a request
--
-- 0002's `inspections_insert_own` plus the suspension gate. `is_approved` is
-- absent deliberately: the requirement is that a *buyer* may use the platform as
-- soon as they sign up, so filing a request depends only on not being blocked.

drop policy if exists inspections_insert_own on public.car_inspections;
create policy inspections_insert_own
  on public.car_inspections
  for insert
  to authenticated
  with check (
    client_id = auth.uid()
    and public.current_user_role() = 'client'
    and not public.current_user_blocked()
    and status = 'pending'
    and inspector_id is null
  );

-- ----------------------------------------------------------------------------
-- The certified report, suspended with its author
--
-- The rest of this sweep covers `users`, `car_inspections`, `payments` and
-- `inspection_centres`. It does not cover `inspection_reports`,
-- `inspection_report_parts`, `inspection_report_sections` or `report_media`, and
-- that omission is not an oversight: those four are reachable by an inspector
-- through `is_inspection_inspector(inspection_id)`, which asks nothing about
-- whether the inspector is suspended. So without the policies below, blocking an
-- inspector stops them filing requests, claiming jobs and quoting prices — and
-- leaves them free to keep writing the certified report they had already started,
-- including the findings, the efficiency scores and the photographic evidence.
--
-- A certified report is an evidence document handed to a buyer who has been told
-- the inspector is under investigation. Leaving the account able to mint them
-- would make suspension worse than useless: it would convert a suspension into a
-- quiet window in which to finish the paperwork.
--
-- All thirteen policies are re-created with `not public.current_user_blocked()`
-- and nothing else changed. That is the only edit, and it is the same edit as
-- everywhere else in this section, which is why it is worth doing here rather than
-- trusting that a gate added to the tables an admin screen lists will reach the
-- tables an inspector screen writes.
--
-- The consequence is stated rather than left to be discovered: suspending an
-- inspector mid-job strands that job. It stays assigned, no longer moves, and the
-- remedy is the admin panel's Orders tab, which can cancel it. That is a deliberate
-- trade — the buyer gets a cancellation and a refund instead of a report written by
-- somebody the platform has suspended, and the inspector gets their account back by
-- being unblocked.
-- ----------------------------------------------------------------------------

drop policy if exists reports_select_participant on public.inspection_reports;
create policy reports_select_participant
  on public.inspection_reports
  for select
  to authenticated
  using (
    (public.is_inspection_participant(inspection_id)
     or public.current_user_role() = 'admin')
    and not public.current_user_blocked()
  );

drop policy if exists reports_insert_assigned_inspector on public.inspection_reports;
create policy reports_insert_assigned_inspector
  on public.inspection_reports
  for insert
  to authenticated
  with check (
    public.is_inspection_inspector(inspection_id)
    and not public.current_user_blocked()
    and exists (
      select 1 from public.car_inspections i
      where i.id = inspection_id and i.status in ('in_progress', 'completed')
    )
  );

drop policy if exists reports_update_assigned_inspector on public.inspection_reports;
create policy reports_update_assigned_inspector
  on public.inspection_reports
  for update
  to authenticated
  using (
    public.is_inspection_inspector(inspection_id)
    and not public.current_user_blocked()
  )
  with check (
    public.is_inspection_inspector(inspection_id)
    and not public.current_user_blocked()
  );

-- No DELETE for anyone, as in 0002: a report is evidence, and the storage objects
-- reference it.

-- ---- report_media
--
-- `report_media_insert_assigned_inspector` is named for the assigned inspector and
-- its body is `is_report_participant`, which is also true of the buyer. The gap is
-- a known finding, recorded by the test that pins it rather than quietly fixed
-- here, and the body is copied over verbatim so this migration neither widens nor
-- quietly closes it. Only the suspension gate is new.

drop policy if exists report_media_select_participant on public.report_media;
create policy report_media_select_participant
  on public.report_media
  for select
  to authenticated
  using (
    (public.is_report_participant(report_id)
     or public.current_user_role() = 'admin')
    and not public.current_user_blocked()
  );

drop policy if exists report_media_insert_assigned_inspector on public.report_media;
create policy report_media_insert_assigned_inspector
  on public.report_media
  for insert
  to authenticated
  with check (
    public.is_report_participant(report_id)
    and not public.current_user_blocked()
  );

-- ---- inspection_report_parts

drop policy if exists report_parts_select_participant on public.inspection_report_parts;
create policy report_parts_select_participant
  on public.inspection_report_parts
  for select
  to authenticated
  using (
    public.is_report_participant(report_id)
    and not public.current_user_blocked()
  );

drop policy if exists report_parts_insert_assigned_inspector on public.inspection_report_parts;
create policy report_parts_insert_assigned_inspector
  on public.inspection_report_parts
  for insert
  to authenticated
  with check (
    public.is_inspection_inspector(
      (select inspection_id from public.inspection_reports where id = report_id)
    )
    and not public.current_user_blocked()
  );

drop policy if exists report_parts_update_assigned_inspector on public.inspection_report_parts;
create policy report_parts_update_assigned_inspector
  on public.inspection_report_parts
  for update
  to authenticated
  using (
    public.is_inspection_inspector(
      (select inspection_id from public.inspection_reports where id = report_id)
    )
    and not public.current_user_blocked()
  )
  with check (
    public.is_inspection_inspector(
      (select inspection_id from public.inspection_reports where id = report_id)
    )
    and not public.current_user_blocked()
  );

drop policy if exists report_parts_delete_assigned_inspector on public.inspection_report_parts;
create policy report_parts_delete_assigned_inspector
  on public.inspection_report_parts
  for delete
  to authenticated
  using (
    public.is_inspection_inspector(
      (select inspection_id from public.inspection_reports where id = report_id)
    )
    and not public.current_user_blocked()
  );

-- ---- inspection_report_sections
--
-- The four efficiency rows. Same three arms as the parts: read, write, delete, all
-- inspector-only, all now closed to a suspended account.

drop policy if exists report_sections_select_participant on public.inspection_report_sections;
create policy report_sections_select_participant
  on public.inspection_report_sections
  for select
  to authenticated
  using (
    public.is_report_participant(report_id)
    and not public.current_user_blocked()
  );

drop policy if exists report_sections_insert_assigned_inspector on public.inspection_report_sections;
create policy report_sections_insert_assigned_inspector
  on public.inspection_report_sections
  for insert
  to authenticated
  with check (
    public.is_inspection_inspector(
      (select inspection_id from public.inspection_reports where id = report_id)
    )
    and not public.current_user_blocked()
  );

drop policy if exists report_sections_update_assigned_inspector on public.inspection_report_sections;
create policy report_sections_update_assigned_inspector
  on public.inspection_report_sections
  for update
  to authenticated
  using (
    public.is_inspection_inspector(
      (select inspection_id from public.inspection_reports where id = report_id)
    )
    and not public.current_user_blocked()
  )
  with check (
    public.is_inspection_inspector(
      (select inspection_id from public.inspection_reports where id = report_id)
    )
    and not public.current_user_blocked()
  );

drop policy if exists report_sections_delete_assigned_inspector on public.inspection_report_sections;
create policy report_sections_delete_assigned_inspector
  on public.inspection_report_sections
  for delete
  to authenticated
  using (
    public.is_inspection_inspector(
      (select inspection_id from public.inspection_reports where id = report_id)
    )
    and not public.current_user_blocked()
  );

-- ============================================================================
-- 12. The approval notification
--
-- An outbox, not an `http_request` to a webhook from a trigger.
--
-- The alternative is a database webhook: a trigger calling
-- `supabase_functions.http_request`, with the service key in Vault. It sends mail
-- from inside the transaction, so a wrong address or an unreachable SMTP relay
-- fails the *approval* — the admin clicks Approve, the screen hangs, and the
-- inspector is neither approved nor told. An outbox decouples the two: the
-- approval commits, a row records that a notification is owed, and delivery is
-- retried separately by `supabase/functions/notify-inspector-approved`.
--
-- Nothing is silently dropped either way. If the function is not deployed the row
-- simply stays `delivered_at is null`, which is what the admin panel's pending
-- count reads.
-- ============================================================================

create table if not exists public.admin_notifications (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.users (id) on delete cascade,
  kind         public.admin_notification_kind not null,
  payload      jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now(),
  delivered_at timestamptz,
  attempts     integer not null default 0,
  last_error   text
);

comment on table public.admin_notifications is
  'Outbox for admin-triggered email. Written by trigger, drained by the notify-inspector-approved edge function under the service role.';

create index if not exists admin_notifications_pending_idx
  on public.admin_notifications (created_at)
  where delivered_at is null;

-- The outbox is drained by an edge function holding the service key, which
-- bypasses RLS, and read by the admin panel to show what is still owed. There is
-- no client INSERT: the trigger is the only writer, so a client cannot queue mail
-- to anyone.
alter table public.admin_notifications enable row level security;
grant select on public.admin_notifications to authenticated;

drop policy if exists admin_notifications_read_admin on public.admin_notifications;
create policy admin_notifications_read_admin
  on public.admin_notifications
  for select
  to authenticated
  using (public.is_admin() and not public.current_user_blocked());

-- ----------------------------------------------------------------------------
-- Queue the mail on the transition that means something changed
--
-- `is_approved` false -> true, or a rejection reason appearing on an account
-- that was approved. A second approval is not queued: nothing changed, and an
-- admin re-save should not re-mail an inspector who already knows.
-- ----------------------------------------------------------------------------

create or replace function public.queue_admin_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.role <> 'inspector' then
    return null;
  end if;

  if new.is_approved and not old.is_approved then
    insert into public.admin_notifications (user_id, kind, payload)
    values (
      new.id,
      'inspector_approved',
      jsonb_build_object('full_name', new.full_name, 'email', new.email)
    );
  elsif new.rejection_reason is not null
        and (old.rejection_reason is null or old.rejection_reason = '')
  then
    insert into public.admin_notifications (user_id, kind, payload)
    values (
      new.id,
      'inspector_rejected',
      jsonb_build_object(
        'full_name', new.full_name,
        'email', new.email,
        'reason', new.rejection_reason
      )
    );
  end if;

  return null;
end;
$$;

drop trigger if exists users_queue_notification on public.users;
create trigger users_queue_notification
  after update on public.users
  for each row execute function public.queue_admin_notification();

-- ============================================================================
-- 13. The financial overview
--
-- A view rather than a query the admin screen composes in Dart, so the arithmetic
-- is written once and the three places that show money cannot drift.
--
-- `security_invoker` is on: the view runs as the caller and is therefore subject
-- to `payments`' own policies, which by this point admit an admin and reject
-- everyone else. Without it the view would run as its owner and quietly bypass
-- RLS for any role that could SELECT it.
--
-- "Revenue" is fees that were *collected*, so it reads only from released
-- payments. Escrow is money the platform is holding and has not earned, and
-- refunded is money it gave back; both are reported on their own lines so the
-- three cannot be added together by mistake.
-- ============================================================================

create or replace view public.admin_financial_overview
with (security_invoker = true)
as
  select
    coalesce(sum(p.amount) filter (where p.status = 'released'), 0)::numeric(12, 2)
      as collected_volume,
    coalesce(sum(p.platform_fee_amount) filter (where p.status = 'released'), 0)::numeric(12, 2)
      as platform_revenue,
    coalesce(sum(p.amount) filter (where p.status = 'escrow'), 0)::numeric(12, 2)
      as held_in_escrow,
    coalesce(sum(p.amount) filter (where p.status = 'refunded'), 0)::numeric(12, 2)
      as refunded,
    count(*) filter (where p.status = 'released')::integer
      as completed_payments,
    count(*)::integer
      as total_payments
  from public.payments p;

comment on view public.admin_financial_overview is
  'One row, always. Money the platform has actually taken.';

grant select on public.admin_financial_overview to authenticated;

-- ----------------------------------------------------------------------------
-- The order monitor's counts, so the admin screen does not count in Dart
--
-- A client that counted rows would either fetch every order to filter them or ask
-- for a count per status; both put a number that can drift in Dart. This keeps
-- the figures next to the data they describe.
-- ----------------------------------------------------------------------------

create or replace view public.admin_order_summary
with (security_invoker = true)
as
  select
    ci.status::text              as status,
    count(*)::integer             as orders,
    coalesce(sum(ci.agreed_total), 0)::numeric(12, 2) as value,
    coalesce(sum(ci.platform_fee), 0)::numeric(12, 2) as platform_fees
  from public.car_inspections ci
  group by ci.status;

grant select on public.admin_order_summary to authenticated;

-- ============================================================================
-- 14. Tell PostgREST the schema changed
-- ============================================================================
--
-- Required, not decorative. PostgREST validates every request against a cached
-- snapshot of the public schema, so `platform_fee`, `inspection_bids` and the
-- two views all fail with PGRST204 until this fires — which looks exactly like
-- the columns not having been created.

notify pgrst, 'reload schema';
