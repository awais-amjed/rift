# Database Schema

Two databases, each with its own migration folder:

- **self-hosted server** — `self_hosted_server_migrations/`, one per community.
- **central** — `central_server_migrations/`, the shared discovery tier.

The migrations are the source of truth and are written to be read in order; this file is the
reference view. Access rules are not repeated here — every table's grants and policies live in
that folder's `002_security.sql`, deliberately in one place.

Where the two schemas hold the same idea they now use the same names: `users`, `dm_messages`,
`read_state`. Central's account row was `dm_profiles` until it was
written down as migrations — it is the account, and it will hold more than a directory profile.

## Tables (self-hosted)

### servers

| Column             | Type        | Constraints                 | Description                              |
|--------------------|-------------|-----------------------------|------------------------------------------|
| id                 | uuid        | Primary Key, Auto-generated | Unique server identifier                 |
| created_at         | timestamptz | Auto-created                | Timestamp of server creation             |
| name               | text        | Required                    | Server name                              |
| icon_url           | text        | Optional                    | URL to server icon                       |
| livekit_url        | text        | Required                    | LiveKit server URL                       |
| max_attachment_bytes | bigint    | Default: 26214400 (25 MB), 1 … 500 MB | Per-file attachment cap. Mirrored onto `chat-attachments`' `file_size_limit` by `update_server`; that mirror is the enforcement, this column is what the client reads to refuse a file before uploading |
| default_channel_daily_quota | integer | Default: 0, ≥ 0        | Messages/member/rolling 24h in a channel that sets no quota of its own. **0 = no limit** |
| dm_daily_quota     | integer     | Default: 0, ≥ 0             | Messages/member/rolling 24h across all server DMs. **0 = no limit** |
| message_retention_days | integer | Default: 0, ≥ 0            | Delete messages older than this. **0 = keep forever** |
| message_history_cap | integer    | Default: 0, ≥ 0             | Keep at most this many per channel and per DM pair, newest first. **0 = no cap** |

Members can read this row directly. The LiveKit credentials that used to sit in it live in
**server_secrets** instead — one row per server, no grant and no policy, reachable only by the
service role (`get_channel_token`, `create_server`, `update_server`). That split is what makes the
rest of the row safe to expose.

The limit columns (migration 007) are on this row rather than a settings table for the same
reason: there is one per server, members already select it, and the client needs to *read* the
attachment cap. There is no client-reachable UPDATE grant on `servers`, so admins change them
through `update_server` like the name and the LiveKit URL. **Every count-based limit defaults
to 0 = off**, so a server upgraded and never touched behaves as it did before.

### server_secrets

| Column             | Type | Constraints                      | Description        |
|--------------------|------|----------------------------------|--------------------|
| server_id          | uuid | Primary Key, FK → servers.id     | Server it belongs to |
| livekit_api_key    | text | Required                         | LiveKit API key    |
| livekit_secret_key | text | Required                         | LiveKit API secret |

### users

| Column             | Type        | Constraints                        | Description                                      |
|--------------------|-------------|------------------------------------|-------------------------------------------------|
| id                 | uuid        | Primary Key, FK → auth.users.id (cascade) | = `auth.uid()` (GoTrue identity), supplied at register — not auto-generated. Identity is derived per `(host, server_id)`, so the same person on two servers in one project has two distinct ids |
| created_at         | timestamptz | Auto-created                       | Timestamp of user creation                       |
| server_id          | uuid        | Required, Foreign Key → servers.id | The server this user is registered on            |
| username           | text        | Required, Unique per server        | Username, unique within a server  — the same name may exist on other servers in the project |
| display_name       | text        | Required                           | User's display name                              |
| public_key         | text        | Not Null, Unique per server        | Ed25519 public key (base64) — SIWS login + message signing |
| stable_id          | text        | Not Null, Unique per server        | Permanent HMAC identity hash. Never changes      |
| is_banned          | boolean     | Default: false                     | If true, the user is rejected on every call      |
| is_server_admin    | boolean     | Default: false                     | Whether user has server admin privileges         |
| is_channel_manager | boolean     | Default: false                     | Whether user can manage channels                 |
| can_create_tokens  | boolean     | Default: false                     | Whether user can create invites                  |
| is_muted           | boolean     | Default: false                     | Moderation: enforced in get_channel_token grants  |
| is_deafened        | boolean     | Default: false                     | Moderation: enforced in get_channel_token grants  |
| chat_public_key    | text        | Nullable                           | X25519 chat identity (base64); published by the client after login |

### channels

| Column       | Type         | Constraints                        | Description                     |
|--------------|--------------|------------------------------------|---------------------------------|
| id           | uuid         | Primary Key, Auto-generated        | Unique channel identifier       |
| created_at   | timestamptz  | Auto-created                       | Timestamp of channel creation   |
| server_id    | uuid         | Required, Foreign Key → servers.id | Reference to associated server  |
| name         | text         | Required                           | Channel name                    |
| channel_type | channel_type | Required                           | Type of channel (voice or text) |
| daily_quota  | integer      | Optional, ≥ 0                      | Per-member messages/rolling 24h here. **NULL inherits** `servers.default_channel_daily_quota`; **0 explicitly means no limit** — the two are different answers |

`daily_quota` is the only nullable limit in the schema, and deliberately: nullable is what
"inherit" needs, which is a third state beyond "some number" and "none". Channel managers may
write it — `GRANT UPDATE (daily_quota)` in 007, under the existing
`channels_update_managers` policy.

### invites

Permission grants with reuse support — used to register new users.

| Column             | Type        | Constraints                        | Description                                    |
|--------------------|-------------|------------------------------------|-------------------------------------------------|
| id                 | uuid        | Primary Key, Auto-generated        | Unique invite identifier                        |
| created_at         | timestamptz | Auto-created                       | Timestamp of invite creation                    |
| server_id          | uuid        | Required, Foreign Key → servers.id | Reference to associated server                  |
| code               | text        | Required, Unique                   | Invite code value                               |
| is_server_admin    | boolean     | Default: false                     | Grant server admin to registrant                |
| is_channel_manager | boolean     | Default: false                     | Grant channel manager to registrant             |
| can_create_tokens  | boolean     | Default: false                     | Grant invite creation to registrant             |
| created_by         | uuid        | FK → users.id (set null)           | Who minted it — what lets a member manage their own invites without being able to read anyone else's codes |
| max_uses           | integer     | Nullable                           | Max uses (NULL = unlimited)                     |
| uses               | integer     | Default: 0                         | Current use count                               |
| expires_at         | timestamptz | Nullable                           | Expiry (NULL = never); swept hourly             |

The code is generated by a column default (base58, 10 chars), so creating an invite is an ordinary
insert rather than a privileged endpoint.

### messages

E2E chat envelopes (ARCHITECTURE.md §4) — the server only ever stores ciphertext.

| Column      | Type        | Constraints                         | Description                                                    |
|-------------|-------------|-------------------------------------|----------------------------------------------------------------|
| id          | bigserial   | Primary Key                         | Monotonic message id — used for pagination + live after-fetch  |
| created_at  | timestamptz | Auto-created                        | Server-assigned send time                                      |
| channel_id  | uuid        | Required, Foreign Key → channels.id | Channel the message belongs to                                 |
| sender_id   | uuid        | Required, Foreign Key → users.id    | Author (server-attested)                                       |
| ciphertext  | text        | Required                            | AES-256-GCM ciphertext + tag, base64                           |
| nonce       | text        | Required                            | AES-GCM nonce, base64                                          |
| signature   | text        | Required                            | Sender's Ed25519 signature over the canonical payload, base64  |
| key_version | integer     | Required                            | Channel-key version that encrypted this message                |

### dm_messages

E2E direct messages between members (Design 1 — pairwise X25519 DH, no keyring).
Signature context: `dm:<lowerUserId>:<higherUserId>`.

| Column       | Type        | Constraints                                       | Description                          |
|--------------|-------------|---------------------------------------------------|--------------------------------------|
| id           | bigserial   | Primary Key                                       | Monotonic id — pagination + catch-up |
| created_at   | timestamptz | Auto-created                                      | Server-assigned send time            |
| sender_id    | uuid        | Required, FK → users.id                           | Author (server-attested)             |
| recipient_id | uuid        | Required, FK → users.id, `<> sender_id`           | Recipient                            |
| ciphertext   | text        | Required                                          | AES-256-GCM + tag, base64            |
| nonce        | text        | Required                                          | AES-GCM nonce, base64                |
| signature    | text        | Required                                          | Sender's Ed25519 signature, base64   |
| key_version  | integer     | Required                                          | Always 1 for DMs (no rotation)       |
| edited_at    | timestamptz | Nullable                                          | Last edit; null = never edited       |

Both `messages` and `dm_messages` carry `edited_at`. An edit
overwrites `ciphertext`/`nonce`/`signature`/`key_version` in place (re-sealed
and re-signed client-side, at the *current* key version — a rotation may have
happened since the original send) and stamps `edited_at`. Deletion is a **hard**
delete, not a tombstone: in an E2E app "deleted" has to mean the ciphertext is
gone. Reactions cascade with the row.

### users.avatar_path

`users` gained `avatar_path` — the object name inside the server's private
`avatars` bucket (`<user_id>/<random>.img`), or NULL for no picture (render
initials). It is a path rather than a URL so the bucket can move without
rewriting rows, and the random segment means a new upload never collides with a
cached copy of the old one.

**Avatars are not E2E.** The server stores the image in the clear, the same
accepted trade-off as reactions: an avatar is shown to every member, so
per-member wrapping buys nothing. The bucket is private (authenticated read),
so it isn't exposed to the unauthenticated internet. Message bodies,
attachments and DMs are unaffected.

Storage RLS: any authenticated member may read; insert/update/delete only
inside their own `<user_id>/` folder. `update_profile` additionally rejects an
`avatar_path` outside the caller's folder, so a row can't point at someone
else's object.

### message_reactions / dm_message_reactions

Emoji reactions on channel messages / server DMs. **Not E2E** — the server
stores who reacted with which emoji, in the clear (accepted metadata trade-off,
ARCHITECTURE.md §4). One row per (message, user, emoji); toggling re-adds or
removes it. Direct table access under participant-scoped policies: you may read
reactions on messages you can read, insert only as yourself, and delete only
your own.

Message reads embed these rows, so a page of history arrives with its reactions
already tallied and nothing is fetched per page. **Self-hosted only** — the
central tier has no reactions at all (migration 006 dropped the table).

| Column     | Type        | Constraints                                    | Description                     |
|------------|-------------|------------------------------------------------|---------------------------------|
| message_id | bigint      | FK → messages.id / dm_messages.id, cascade     | Reacted-to message              |
| user_id    | uuid        | FK → users.id, cascade                         | Reactor                         |
| emoji      | text        | 1–32 chars                                     | The emoji                       |
| created_at | timestamptz | Auto-created                                   | When added                      |
| —          | —           | Primary Key (message_id, user_id, emoji)       | One reaction per user per emoji |

### channel_keyring

The symmetric channel key sealed per member (ephemeral-static X25519 "sealed box") —
the server can't read any entry. A whole key version is inserted in one statement with
no ON CONFLICT: first writer wins, losers re-wrap the winner's key.

| Column               | Type        | Constraints                             | Description                                  |
|----------------------|-------------|-----------------------------------------|----------------------------------------------|
| id                   | uuid        | Primary Key, Auto-generated             | Unique entry identifier                      |
| created_at           | timestamptz | Auto-created                            | Timestamp of entry creation                  |
| channel_id           | uuid        | Required, Foreign Key → channels.id     | Channel this key belongs to                  |
| key_version          | integer     | Required                                | Key version (rotated on kick/ban)            |
| user_id              | uuid        | Required, Foreign Key → users.id        | Member this entry is sealed to               |
| wrapped_by           | uuid        | Required, Foreign Key → users.id        | Member whose client produced the wrap        |
| ephemeral_public_key | text        | Required                                | Ephemeral X25519 public key, base64          |
| ciphertext           | text        | Required                                | Sealed channel key (AES-256-GCM), base64     |
| nonce                | text        | Required                                | AES-GCM nonce, base64                        |

Unique: `(channel_id, key_version, user_id)`.

### read_state

One cursor per conversation: the newest message this member has read. It is what every unread
badge is computed from, by `unread_counts()`.

This replaced a `notifications` table that fanned out one row per recipient per message — a write
per member per send, plus a retention job to stop it growing forever — whose only purpose was to
give the client something it was allowed to subscribe to. With policies on the message tables,
Realtime delivers the messages themselves (RLS-checked per subscriber), so the fanout bought
nothing. A cursor is written when someone actually reads.

Cursors are own-row (`user_id = auth.uid()`), which also keeps them from becoming read receipts:
a sender can never learn whether their message was read.

| Column       | Type        | Constraints                                | Description                               |
|--------------|-------------|--------------------------------------------|-------------------------------------------|
| user_id      | uuid        | PK (with scope, scope_id), FK → users.id   | Whose read state this is                  |
| scope        | read_scope  | PK — `channel` or `dm`                     | What kind of conversation                 |
| scope_id     | uuid        | PK                                         | Channel id, or the other person's user id |
| last_read_id | bigint      | Required, default 0                        | Newest message id read in that scope      |
| updated_at   | timestamptz | Required, default now()                    | Last time it moved                        |

New members are seeded at registration with a cursor per channel at the current newest message —
otherwise joining a server would show every channel screaming with unread counts for history they
cannot decrypt anyway.

## Functions and jobs (self-hosted)

Most of what a client does is a policy-checked table call; these are the exceptions worth
naming. The full set lives in `003_api.sql` and `007_limits.sql`.

### chat_quota(p_channel_id uuid default null)

What the composer footer reads. A channel id asks about that channel; NULL asks about the
caller's server DMs — one function so the client asks both surfaces the same question, the
way central's `dm_quota()` answers for its one surface.

Returns `{quota, remaining}`. **`remaining` is NULL when unlimited, not 0** — a quota of 0
meaning "no limit" and a remaining of 0 meaning "you are out" are one keystroke apart in a
UI, and returning the same number for both is how that gets confused. Asking about a channel
on another server raises `not_a_member`, so the setting doesn't leak.

### enforce_message_quota() — trigger on messages, dm_messages

BEFORE INSERT, one function for both tables. Raises `quota_exceeded` (P0001) when the sender
is out for that channel, or for DMs server-wide. Skips service-role writes (no `auth.uid()`),
and returns immediately when no quota is configured — the default. **Must sort after
`attest_message()`**, which stamps `sender_id`; Postgres runs same-timing triggers in name
order, so `attest_*` before `enforce_*` is load-bearing.

INSERT only: an edit is not a new message and must not cost quota, the same rule central
states by having its edit path bypass `send_dm()`.

### app.enforce_retention() — pg_cron `rift-message-retention`, nightly

Applies `message_retention_days` and `message_history_cap` per server. In the `app` schema,
not `public`, because it returns VOID and PostgREST would otherwise expose a history-wiping
RPC to any member. Deletes are permanent; **attachment blobs of deleted messages are not
swept** (see ARCHITECTURE.md §4).

## Tables (central)

Central mirrors the self-hosted shapes where the idea is the same, so one client path serves both.

### users (central)

The account row, and the directory: readable by every signed-in account by design, because you
cannot message someone you cannot find. Holds a handle and the two public keys needed to seal and
verify a first message.

| Column             | Type        | Constraints                          | Description                        |
|--------------------|-------------|--------------------------------------|------------------------------------|
| id                 | uuid        | Primary Key, FK → auth.users.id      | = `auth.uid()`                     |
| created_at         | timestamptz | Auto-created                         | When the account was created       |
| handle             | text        | Required, Unique, `^[a-z0-9_]{3,20}$`| How the account is found           |
| chat_public_key    | text        | Required                             | X25519, for the pairwise DM key    |
| signing_public_key | text        | Required                             | Ed25519, for signature verification |

### dm_messages / read_state (central)

Same columns as their self-hosted counterparts. Differences that matter:

- **No reactions.** Central DMs are the first-contact tier — quota'd, retained
  30 days, running on infrastructure the project pays for — so they carry only
  what first contact needs. React on a server you share.

- **Sends go through `send_dm()`**, an RPC, because the daily quota is a count over *other* rows
  and has to happen in the same statement that inserts. Edits and deletes are ordinary policy-
  checked writes — an edit is not a new message and must not cost quota.
- **Retention is enforced** (`004_jobs.sql`): nothing older than 30 days, no more than 500 messages
  per conversation, both hard deletes. A self-hosted server keeps everything, because it is
  somebody's own disk.
- `read_state` uses the same `scope`/`scope_id` shape with only `dm` in use.
- **Claiming a handle goes through `claim_handle()`**, and moving a read cursor through
  `mark_read()`, rather than PostgREST upserts. Both tables grant UPDATE on named columns only,
  and a PostgREST upsert writes *every* payload column into its `ON CONFLICT DO UPDATE` clause —
  the conflict key included. That is checked when the statement is planned, so it failed even
  when no row existed: "permission denied for table users" on a first claim. The RPCs spell the
  same upsert without touching the key. **Any future upsert against a column-granted table has
  this problem**; write it as an RPC.

## Enums

### channel_type

- `voice` - Voice channel
- `text` - Text channel

### read_scope

- `channel` - a read cursor pointing at a channel
- `dm` - a read cursor pointing at the other person in a conversation

## Storage Buckets

### servers

- **Access**: Public
- **Purpose**: Storage for server-related assets (e.g., icons)

### chat-attachments

- **Access**: Private; RLS allows any authenticated member to insert/select.
- **Size cap**: `servers.max_attachment_bytes`, mirrored here by `update_server` (25 MB
  until an admin changes it). One Supabase project can host several servers sharing this
  bucket, so the mirror writes the **MAX** across them — on a multi-server project a
  stricter server's cap is client-enforced only.
- **Purpose**: E2E-encrypted attachment blobs for channels + server DMs. Each
  object is AES-256-GCM ciphertext under a per-file key that lives only inside
  the encrypted message body — the server can't decrypt them. Objects are named
  `<scope>/<random>.bin` (scope = channel id or DM context). "Authenticated
  read" leaks nothing: the bytes are meaningless without the in-message key and
  paths are unguessable.

### central-dm-attachments (central project only)

- **Access**: Private; insert restricted to the caller's own `<uid>/` folder,
  select for any authenticated user. 10 MB per-object cap.
- **Purpose**: same E2E-encrypted blobs for central DMs; uploads count against
  the sender's daily DM quota.
