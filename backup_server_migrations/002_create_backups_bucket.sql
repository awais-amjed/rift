-- Migration: 002_create_backups_bucket
-- Description: Creates the `backups` storage bucket for per-user encrypted
--              vault backups and drops the old `backups` table.
--
-- Storage layout:
--   Bucket  : backups  (private)
--   Object  : {user_id}/vault.json
--
-- RLS policies ensure each authenticated user can only access their own object.

-- ── Drop old table ────────────────────────────────────────────────────────────

drop table if exists backups;

-- ── Create storage bucket ─────────────────────────────────────────────────────

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'backups',
  'backups',
  false,            -- private: no public URL access
  5242880,          -- 5 MB max per file (vault backups are tiny; this is generous)
  array['application/json']
)
on conflict (id) do nothing;

-- ── Storage RLS policies ──────────────────────────────────────────────────────

-- Users can upload (insert) only into their own folder.
create policy "Users can upload their own backup"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'backups'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Users can overwrite (update) only their own object.
create policy "Users can update their own backup"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'backups'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Users can download (select) only their own object.
create policy "Users can download their own backup"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'backups'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Users can delete only their own object.
create policy "Users can delete their own backup"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'backups'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

