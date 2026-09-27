-- Moaen (معاين) — 0003_storage.sql
-- Private buckets for report PDFs and inspection media, with RLS policies.
--
-- Object path convention: {bucket}/{inspection_id}/{filename}
--
-- Reading is gated on participation, not on uploader identity, because the
-- client is not the uploader — the inspector uploads and the client reads.
-- That rules out the common "prefix the path with the uploader's id" pattern,
-- which would lock the buyer out of the very report they paid for.

-- ============================================================================
-- Safe inspection-id extraction
--
-- storage.foldername(name)[1] yields a text segment that may not be a UUID.
-- A bare ::uuid cast on a malformed path raises inside the policy and turns a
-- bad request into a 500. This returns NULL instead, and every caller treats
-- NULL as "not permitted" because the EXISTS checks it feeds are false for a
-- NULL id. Fail closed.
-- ============================================================================

create or replace function public.storage_inspection_id(p_object_name text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  segment text;
begin
  segment := split_part(coalesce(p_object_name, ''), '/', 1);
  if segment ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
    return segment::uuid;
  end if;
  return null;
end;
$$;

revoke all on function public.storage_inspection_id(text) from public, anon;
grant execute on function public.storage_inspection_id(text) to authenticated;

-- ============================================================================
-- Buckets — private
--
-- With `public = false`, a signed URL is required for every read, so object
-- visibility is decided entirely by the policies below.
-- ============================================================================

insert into storage.buckets (id, name, public)
values
  ('inspection-reports', 'inspection-reports', false),
  ('inspection-media',   'inspection-media',   false)
on conflict (id) do nothing;

-- ============================================================================
-- Remove any permissive public-access policy on storage.objects
--
-- A fresh Supabase project ships without policies on storage.objects, but a
-- project that has been through the storage quickstart may carry the scaffolded
-- "Allow public ..." policies. Those would sit alongside ours and, because
-- Postgres ORs permissive policies together, would silently defeat the
-- isolation below. Only policies matching that exact scaffolded name are
-- dropped; anything hand-written is left for a human to review.
-- ============================================================================

do $$
declare
  leftover record;
begin
  for leftover in
    select policyname
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'Allow public%'
  loop
    execute format('drop policy if exists %I on storage.objects', leftover.policyname);
  end loop;
end;
$$;

-- ============================================================================
-- Object policies
--
-- Reads: either party to the inspection. Writes: the assigned inspector only,
-- which keeps a client from uploading evidence into a report.
-- ============================================================================

create policy inspection_reports_read
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'inspection-reports'
    and public.is_inspection_participant(public.storage_inspection_id(name))
  );

create policy inspection_reports_write
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'inspection-reports'
    and public.is_inspection_inspector(public.storage_inspection_id(name))
  );

create policy inspection_media_read
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'inspection-media'
    and public.is_inspection_participant(public.storage_inspection_id(name))
  );

create policy inspection_media_write
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'inspection-media'
    and public.is_inspection_inspector(public.storage_inspection_id(name))
  );

-- No UPDATE or DELETE policies. Evidence is immutable once written, and an
-- orphan-cleanup job runs server-side under the service role.
