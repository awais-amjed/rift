-- Migration: 001_create_backups_table
-- Description: Creates the backups table used by the central Supabase server
--              to store per-user encrypted vault backups.

-- Each user may have at most one backup row (unique on user_id).
create table if not exists backups (
  id          uuid        primary key default gen_random_uuid(),
  user_id     uuid        not null references auth.users on delete cascade,
  backup_json text        not null,
  updated_at  timestamptz not null default now(),

  constraint backups_user_id_unique unique (user_id)
);

-- Row-level security: every user can only read and write their own row.
alter table backups enable row level security;

create policy "Users can view their own backup"
  on backups for select
  using (auth.uid() = user_id);

create policy "Users can insert their own backup"
  on backups for insert
  with check (auth.uid() = user_id);

create policy "Users can update their own backup"
  on backups for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users can delete their own backup"
  on backups for delete
  using (auth.uid() = user_id);
