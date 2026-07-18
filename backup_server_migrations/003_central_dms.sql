-- Migration: 003_central_dms
-- Description: Central DMs — the discovery/first-contact tier of Rift's
--              two-tier DM design (ARCHITECTURE.md §4). E2E encrypted
--              (Design 1); the server stores only opaque envelopes and
--              enforces the funnel limits server-side: a per-sender daily
--              quota, a 30-day TTL, and a per-conversation history cap.

-- ── Directory: handles + published public keys ──────────────────────────────
-- One row per user who opts into central DMs. The handle is how people find
-- each other; the keys are the user's central-host chat identity (X25519 for
-- encryption, Ed25519 for message signatures), self-published (TOFU).

create table if not exists dm_profiles (
  user_id            uuid        primary key references auth.users on delete cascade,
  handle             text        not null unique
                     check (handle ~ '^[a-z0-9_]{3,20}$'),
  chat_public_key    text        not null check (length(chat_public_key) <= 64),
  signing_public_key text        not null check (length(signing_public_key) <= 64),
  created_at         timestamptz not null default now()
);

alter table dm_profiles enable row level security;

-- The directory is readable by any signed-in user (that's the point of it);
-- rows are writable only by their owner.
create policy "Authenticated users can read the directory"
  on dm_profiles for select
  to authenticated
  using (true);

create policy "Users can create their own profile"
  on dm_profiles for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "Users can update their own profile"
  on dm_profiles for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ── Messages: opaque E2E envelopes ──────────────────────────────────────────

create table if not exists dm_messages (
  id           bigint      generated always as identity primary key,
  created_at   timestamptz not null default now(),
  sender_id    uuid        not null references auth.users on delete cascade,
  recipient_id uuid        not null references auth.users on delete cascade,
  ciphertext   text        not null check (length(ciphertext) <= 16384),
  nonce        text        not null check (length(nonce) <= 64),
  signature    text        not null check (length(signature) <= 128),
  key_version  integer     not null,

  check (sender_id <> recipient_id)
);

create index if not exists idx_central_dm_pair
  on dm_messages (least(sender_id, recipient_id),
                  greatest(sender_id, recipient_id), id);
create index if not exists idx_central_dm_sender_time
  on dm_messages (sender_id, created_at);
create index if not exists idx_central_dm_recipient
  on dm_messages (recipient_id, id);

alter table dm_messages enable row level security;

-- Participants read their own conversations. There is deliberately NO insert
-- policy: writes go through the send_dm() RPC below so the daily quota is
-- enforced transactionally and can't be bypassed by a modified client.
create policy "Participants can read their conversations"
  on dm_messages for select
  to authenticated
  using (auth.uid() = sender_id or auth.uid() = recipient_id);

-- Live delivery: recipients subscribe to INSERTs via Realtime (RLS applies).
alter publication supabase_realtime add table dm_messages;

-- ── Send RPC: quota-enforced insert ─────────────────────────────────────────
-- Central is a funnel, not a home (no revenue → cost must stay flat): each
-- sender gets DM_DAILY_QUOTA messages per rolling 24 h. Returns the stored
-- row's id/created_at plus the remaining quota for the UI meter.

create or replace function send_dm(
  recipient   uuid,
  ciphertext  text,
  nonce       text,
  signature   text,
  key_version integer
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  daily_quota constant integer := 100;
  sent_recently integer;
  new_id bigint;
  new_at timestamptz;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  if recipient = auth.uid() then
    raise exception 'cannot_dm_self';
  end if;
  if not exists (select 1 from dm_profiles where user_id = auth.uid()) then
    raise exception 'sender_has_no_profile';
  end if;
  if not exists (select 1 from dm_profiles where user_id = recipient) then
    raise exception 'recipient_has_no_profile';
  end if;
  if length(ciphertext) > 16384 or length(nonce) > 64 or length(signature) > 128
     or key_version < 1 then
    raise exception 'envelope_invalid';
  end if;

  select count(*) into sent_recently
    from dm_messages
    where sender_id = auth.uid()
      and created_at > now() - interval '24 hours';
  if sent_recently >= daily_quota then
    raise exception 'quota_exceeded';
  end if;

  insert into dm_messages (sender_id, recipient_id, ciphertext, nonce, signature, key_version)
    values (auth.uid(), recipient, ciphertext, nonce, signature, key_version)
    returning id, created_at into new_id, new_at;

  return jsonb_build_object(
    'id', new_id,
    'created_at', new_at,
    'remaining', daily_quota - sent_recently - 1,
    'quota', daily_quota
  );
end;
$$;

revoke all on function send_dm(uuid, text, text, text, integer) from public, anon;
grant execute on function send_dm(uuid, text, text, text, integer) to authenticated;

-- Quota read for the composer meter.
create or replace function dm_quota() returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  daily_quota constant integer := 100;
  sent_recently integer;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  select count(*) into sent_recently
    from dm_messages
    where sender_id = auth.uid()
      and created_at > now() - interval '24 hours';
  return jsonb_build_object(
    'quota', daily_quota,
    'remaining', greatest(daily_quota - sent_recently, 0)
  );
end;
$$;

revoke all on function dm_quota() from public, anon;
grant execute on function dm_quota() to authenticated;

-- ── Retention: 30-day TTL + per-conversation cap ────────────────────────────
-- Server-side deletion is the source of truth; clients render what remains.

create extension if not exists pg_cron;

select cron.schedule(
  'central-dm-retention',
  '17 3 * * *',  -- daily, 03:17 UTC
  $cron$
  delete from dm_messages where created_at < now() - interval '30 days';
  delete from dm_messages where id in (
    select id from (
      select id,
             row_number() over (
               partition by least(sender_id, recipient_id),
                            greatest(sender_id, recipient_id)
               order by id desc
             ) as rn
      from dm_messages
    ) ranked
    where rn > 500
  );
  $cron$
);
