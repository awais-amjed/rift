# Database Schema

## Tables

### servers

| Column             | Type        | Constraints                 | Description                              |
|--------------------|-------------|-----------------------------|------------------------------------------|
| id                 | uuid        | Primary Key, Auto-generated | Unique server identifier                 |
| created_at         | timestamptz | Auto-created                | Timestamp of server creation             |
| name               | text        | Required                    | Server name                              |
| icon_url           | text        | Optional                    | URL to server icon                       |
| livekit_url        | text        | Required                    | LiveKit server URL                       |
| livekit_api_key    | text        | Required                    | LiveKit API key                          |
| livekit_secret_key | text        | Required                    | LiveKit secret key                       |

### users

| Column             | Type        | Constraints                        | Description                                      |
|--------------------|-------------|------------------------------------|-------------------------------------------------|
| id                 | uuid        | Primary Key, FK → auth.users.id (cascade) | = `auth.uid()` (GoTrue identity), supplied at register — not auto-generated. Identity is derived per `(host, server_id)`, so the same person on two servers in one project has two distinct ids |
| created_at         | timestamptz | Auto-created                       | Timestamp of user creation                       |
| server_id          | uuid        | Required, Foreign Key → servers.id | The server this user is registered on            |
| username           | text        | Required, Unique per server        | Username, unique within a server (migration 010) — the same name may exist on other servers in the project |
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
| max_uses           | integer     | Nullable                           | Max uses (NULL = unlimited)                     |
| uses               | integer     | Default: 0                         | Current use count                               |

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
| edited_at    | timestamptz | Nullable (migration 013)                          | Last edit; null = never edited       |

Both `messages` and `dm_messages` gained `edited_at` in migration 013. An edit
overwrites `ciphertext`/`nonce`/`signature`/`key_version` in place (re-sealed
and re-signed client-side, at the *current* key version — a rotation may have
happened since the original send) and stamps `edited_at`. Deletion is a **hard**
delete, not a tombstone: in an E2E app "deleted" has to mean the ciphertext is
gone. Reactions cascade with the row.

### users.avatar_path (migration 014)

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

### message_reactions / dm_message_reactions (migration 012)

Emoji reactions on channel messages / server DMs. **Not E2E** — the server
stores who reacted with which emoji, in the clear (accepted metadata trade-off,
ARCHITECTURE.md §4). One row per (message, user, emoji); toggling re-adds or
removes it. RLS enabled with no policies (access is via the service-role
`toggle_reaction` / `list_reactions` edge functions). On the **central** project
the equivalent table is `dm_reactions` with participant-scoped RLS (direct
client access, not an edge function).

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

### notifications

Per-recipient message notifications (migration 007). Fanned out by `send_message` and — since
migration 015 — by `send_dm`, read directly by clients over authenticated Realtime (Postgres
Changes) — RLS scopes each subscription to `auth.uid()`. Added to the `supabase_realtime`
publication.

A row targets **either** a channel message (`channel_id` + `message_id`) **or** a DM
(`dm_peer_id` + `dm_message_id`), enforced by the `notifications_one_target` CHECK. The DM half
names the *peer* rather than a conversation because only inbound DMs are ever unread, and the
client badges one count per person. One table for both means DM badges inherit everything the
channel path already had: server-side read state that agrees across a user's devices, delivery
for servers the user isn't currently looking at, and the retention prune below.

Transient signal, not a source of truth (the message lives in `messages`), so it's pruned to bound
growth (migration 008): an hourly `cleanup-notifications` pg_cron job deletes rows read more than a
day ago or older than 7 days. `idx_notifications_created_at` backs the age prune.

| Column        | Type        | Constraints                             | Description                                |
|---------------|-------------|-----------------------------------------|--------------------------------------------|
| id            | bigserial   | Primary Key                             | Monotonic notification id                  |
| created_at    | timestamptz | Auto-created                            | Server-assigned time                       |
| user_id       | uuid        | Required, FK → users.id (cascade)       | Recipient (RLS: `auth.uid() = user_id`)    |
| channel_id    | uuid        | FK → channels.id (cascade)              | Channel the message was sent to (channel rows) |
| message_id    | bigint      | FK → messages.id (cascade)              | The channel message that triggered this    |
| dm_peer_id    | uuid        | FK → users.id (cascade), migration 015  | The sender, for DM rows — what's badged    |
| dm_message_id | bigint      | FK → dm_messages.id (cascade), mig. 015 | The DM that triggered this                 |
| sender_id     | uuid        | Required, FK → users.id (cascade)       | Message author                             |
| read_at       | timestamptz | Nullable                                | Set when the client marks it read          |

Indexes: `idx_notifications_user_unread` `(user_id, id DESC) WHERE read_at IS NULL`,
`idx_notifications_user_dm_unread` `(user_id, dm_peer_id) WHERE read_at IS NULL` (the
per-conversation count and clear).

The **central** project has no equivalent and doesn't need one: its clients read `dm_messages`
directly over RLS, so unread is derived client-side from the rows already fetched, against a
per-conversation cursor in `dm_read_state` (below).

### dm_read_state (central project only)

One row per conversation holding the newest central DM the caller has read. Written directly by
the client (RLS `user_id = auth.uid()` for all operations), so it is private to its owner — a
sender never learns whether their message was read.

Central DMs get their badge from this rather than from fanned-out rows because the client is
already allowed to see every message addressed to it; only the *read* half was missing. It lives
on the server rather than in local storage so a conversation read on one device is read on the
others.

| Column       | Type        | Constraints                            | Description                            |
|--------------|-------------|----------------------------------------|----------------------------------------|
| user_id      | uuid        | PK (with peer_id), FK → auth.users     | Whose read state this is               |
| peer_id      | uuid        | PK (with user_id), FK → auth.users     | The other side of the conversation     |
| last_read_id | bigint      | Required, default 0                    | Newest `dm_messages.id` read from them |
| updated_at   | timestamptz | Required, default now()                | Last time it moved                     |

## Enums

### channel_type

- `voice` - Voice channel
- `text` - Text channel

## Storage Buckets

### servers

- **Access**: Public
- **Purpose**: Storage for server-related assets (e.g., icons)

### chat-attachments (migration 011)

- **Access**: Private; RLS allows any authenticated member to insert/select.
- **Size cap**: 25 MB per object (`file_size_limit`).
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
