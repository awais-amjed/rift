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
| max_attachment_bytes | bigint    | Default: 26214400 (25 MB), 1 … 500 MB | Per-file attachment cap. A trigger mirrors it onto this server's `chat-<uuid>` bucket's `file_size_limit` (migration 008); that mirror is the enforcement, this column is what the client reads to refuse a file before uploading |
| message_retention_days | integer | Default: 0, ≥ 0            | Server default: delete messages older than this. **0 = keep forever.** A channel may override it |
| message_history_cap | integer    | Default: 0, ≥ 0             | Server default: keep at most this many per channel and per DM pair, newest first. **0 = no cap.** A channel may override it |
| dm_retention_days  | integer     | Optional, ≥ 0               | DM override (migration 009). **NULL inherits** `message_retention_days`; **0 explicitly keeps DMs forever** while the channels are still swept |
| dm_history_cap     | integer     | Optional, ≥ 0               | DM override. **NULL inherits** `message_history_cap`; **0 explicitly means no cap.** Counts a conversation, not a sender |

Members can read this row directly. The LiveKit credentials that used to sit in it live in
**server_secrets** instead — one row per server, no grant and no policy, reachable only by the
service role (`get_channel_token`, `create_server`, `update_server`). That split is what makes the
rest of the row safe to expose.

The limit columns (migration 007) are on this row rather than a settings table for the same
reason: there is one per server, members already select it, and the client needs to *read* the
attachment cap. There is no client-reachable UPDATE grant on `servers`, so admins change them
through `update_server` like the name and the LiveKit URL. **Both sweeps default to 0 = off**,
so a server upgraded and never touched behaves as it did before.

There is deliberately **no daily message quota** here. A quota is a rate limit, not a storage
bound — see ARCHITECTURE.md §4. An earlier draft of 007 added per-channel and per-DM quotas;
the current file drops those columns, so a database that ran the draft converges on re-run.

The two DM columns are nullable where the two above them are `NOT NULL DEFAULT 0`, because
they override rather than set the base case — the same shape `channels.retention_days` uses.
They sit on `servers` because a per-conversation setting would have no owner: a DM belongs to
two people, and neither of them should be deciding how long the other's messages survive.

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
| retention_days | integer    | Optional, ≥ 0                      | Delete this channel's messages older than this. **NULL inherits** `servers.message_retention_days`; **0 explicitly means keep forever** — the two are different answers |
| history_cap  | integer      | Optional, ≥ 0                      | Keep at most this many messages here. **NULL inherits** `servers.message_history_cap`; **0 explicitly means no cap** |

These are the only nullable limits in the schema, and deliberately: nullable is what "inherit"
needs, which is a third state beyond "some number" and "none". Channel managers may write them
— `GRANT UPDATE (retention_days, history_cap)` in 007, under the existing
`channels_update_managers` policy.

A **voice** channel carries both columns and ignores them; it has no messages. The settings
dialog hides them for one rather than offering a switch wired to nothing.

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
| sender_id   | uuid        | Foreign Key → users.id              | Author (server-attested). NULL when no member sent it          |
| ciphertext  | text        | Required                            | AES-256-GCM ciphertext + tag, base64 — or plain text at v0     |
| nonce       | text        | Required at key_version ≥ 1         | AES-GCM nonce, base64                                          |
| signature   | text        | Required at key_version ≥ 1         | Sender's Ed25519 signature over the canonical payload, base64  |
| key_version | integer     | Required, ≥ 0                       | Channel-key version — **0 means not encrypted** (migration 013)|
| webhook_id  | uuid        | Foreign Key → webhooks.id, SET NULL | Which webhook posted it, for management. Not what it renders as|
| origin_name | text        | 1–80 chars                          | Display name when no member sent it. Frozen at insert          |
| mentions    | uuid[]      | Required, default `{}`              | User ids this message names — **plaintext** (migration 012)    |
| mentions_all| boolean     | Required, default `false`           | The `@all` flag                                                |

**`key_version = 0` is a body the server can read** (migration 013, BOTS.md §3). It exists so an
incoming webhook can post — GitHub holds no Rift key, so nothing it sends could ever be sealed.
Four CHECKs keep the two shapes from blurring into each other:

| Constraint | Says |
|---|---|
| `messages_one_origin` | exactly one of `sender_id` / `origin_name` — a message from nobody is not a message |
| `messages_origin_is_plain` | a non-member message is always `key_version = 0` |
| `messages_plain_is_origin` | and, for now, the converse — a *member* may not write in the clear. Bot commands (BOTS.md §4) will relax this half |
| `messages_envelope_complete` | `nonce`/`signature` are present exactly when there is an envelope |

`origin_name` is denormalised rather than read through `webhook_id` on purpose: revoking a webhook
must not rewrite the history it posted, and `ON DELETE SET NULL` would otherwise leave rows with no
name and no sender. **Clients read the origin from `origin_name`, never from `webhook_id`.**

The signature rule in ARCHITECTURE.md §4 — unverifiable messages are never rendered — is unchanged
**for `key_version ≥ 1`**. At 0 there is no signer, so a client must render the message with its
origin visible and must never attribute it to a person.

`mentions` and `mentions_all` are the only part of a message that is not sealed, and they
exist for one reason: the server cannot open the envelope, so without them it cannot tell a
message that named somebody from one that did not — which is exactly what a mentions-only
channel turns on. **The operator learns who was addressed; never what was said.** That is the
same class of metadata already in the open for `dm_messages.recipient_id` and for reactions.

They are written by the sender and **validated, not trusted**: a BEFORE trigger
(`validate_message_mentions`) drops ids that aren't live members of this channel's server,
drops the sender, dedupes, and caps the array at 50. They are insert-only — the UPDATE grant
names four columns and none of them are these — because an edit rings nobody, so rewriting the
array could only change who a later reader thinks was addressed.

The phone still decrypts before it says anything, so a client that lies about who it mentioned
buys a silent wake and never a false "mentioned you".

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

### webhooks (migration 013)

Incoming webhooks: a secret URL an outside service posts to, which lands in a channel as an
unencrypted message. The point of one is that **nobody runs anything** — a bot is a program
somebody hosts, and this exists for the case where there is no program.

| Column       | Type        | Constraints                          | Description                                            |
|--------------|-------------|--------------------------------------|--------------------------------------------------------|
| id           | uuid        | Primary Key                          |                                                        |
| created_at   | timestamptz | Auto-created                         |                                                        |
| server_id    | uuid        | Required, Foreign Key → servers.id   |                                                        |
| channel_id   | uuid        | Required, Foreign Key → channels.id  | One webhook posts to one channel                       |
| created_by   | uuid        | Foreign Key → users.id, SET NULL     | The integration outlives whoever set it up             |
| name         | text        | Required, 1–80 chars                 | Shown as the message's author                          |
| secret_hash  | text        | Required, Unique                     | SHA-256 hex of the URL secret. **The secret is never stored** |
| last_used_at | timestamptz |                                      | So a dead integration is visible                       |
| rate_window  | timestamptz |                                      | Fixed one-minute window                                |
| rate_count   | integer     | Required, default 0                  | Posts in that window; 30 is the cap                    |

**The URL is the credential.** That is what makes a webhook usable by a service that cannot log
in, and it is also its weakness — a URL ends up in CI config, in a screenshot, in a paste. So it
is hashed, shown exactly once at creation, and rate-limited.

`secret_hash` has **no column grant at all**, so it never leaves the database, not even to the
admin who made it. `SELECT` and `DELETE` are granted to `authenticated` and gated by
`app.can_manage_channels()`; there is no `INSERT` or `UPDATE` grant, because minting the secret is
the operation and a secret the caller chose is not a secret.

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

### device_tokens / push_config (migration 010)

Where a member's phones can be reached, and the credential this server rings them over.

A row in `device_tokens` is a **device, not a person**: the same account on a phone and a tablet
is two rows and both should ring. `token` is the primary key because FCM hands the same one back
to a reinstalled app, so a device that changes hands must replace the previous owner's row rather
than accumulate beside it. `user_id` is stamped from `auth.uid()` by a BEFORE trigger — a client
that could name the owner could register its token against somebody else's account and be woken
for their messages. A nightly job drops rows nobody has refreshed in 60 days; the client
re-registers on every session, so that is a device that has not opened Rift in 60 days.

`push_config` is one row **per server** (one Supabase project can host several), and has RLS with
no policy and no grant at all. It holds the relay endpoint, the relay id, and the secret that
proves a forward request came from this server. The ring triggers read it as SECURITY DEFINER;
no session ever can — not even the admin who set it, who held the secret once, in transit.

**This server cannot send a push itself.** An FCM registration token is scoped to the Firebase
project the *app* was built against, so waking a Rift install needs Rift's credentials, which an
operator does not have and must not be given. `ring_devices()` posts to central's `push_send`
with `pg_net`, which queues and returns immediately: a delivered message with no doorbell is a far
smaller problem than a message that could not be sent because a push gateway was down.

Who gets rung is decided by `has_unread_before()` together with each member's
`notification_prefs` level — see below.

### notification_prefs (migration 012; central migration 011)

How much a server, a channel or a conversation is allowed to interrupt one member. Keyed like
`read_state`, and for the same reason: the question is identical whichever of the three it is
about, so one table answers it for all of them and one client path reads it.

| Column     | Type         | Constraints                              | Description                                        |
|------------|--------------|------------------------------------------|----------------------------------------------------|
| user_id    | uuid         | PK part, FK → users.id, stamped          | Whose setting this is (`auth.uid()`)               |
| scope      | notify_scope | PK part                                  | `server`, `channel` or `dm`                        |
| scope_id   | uuid         | PK part                                  | Server id, channel id, or the other person's id    |
| level      | notify_level | Required                                 | `all` / `mentions` / `none`                        |
| updated_at | timestamptz  | Auto                                     | Last change                                        |

Its own `notify_scope` rather than `read_scope`: a read cursor cannot point at a server —
there is nothing to be "read up to" — so adding the value there would make that type's name a
lie and permit a `read_state` row nothing could interpret.

**A row exists only where somebody has changed something.** Channels default to `mentions`
and DMs to `all`; choosing the default *deletes* the row rather than storing it, so what a
default means stays one decision instead of a copy in everybody's table. A server has no
default of its own — no row means no opinion, and each scope inside falls through to its
own — so the client shows an untouched server as `mentions`, the level its channels are
actually at, and writes a `server` row only for `all` or `none`. RLS is own-row and
`user_id` is stamped by a BEFORE trigger — a client that could name the owner could mute
somebody else's conversations, which is a quiet way of making sure a person never hears from
anyone again.

**The scopes are a fallback chain, not a fight.** `app.notify_level(user, scope, scope_id)`
(self-hosted) and `notify_level_for(...)` (central) resolve it in one place, in this order:

1. what this exact channel or conversation is set to;
2. failing that, what the **server** it belongs to is set to;
3. failing that, the scope's default (`mentions` for a channel, `all` for a DM).

So muting a server quiets everything you have not spoken about individually, and a channel you
deliberately set to `all` stays loud inside a muted server. Discord resolves it the other way
and then needs per-channel overrides to climb back out; this order is the one you can predict
from the menu in front of you, because a channel showing an explicit level is telling you it is
in force. `NotificationLevel.resolve` is the only copy of the order on the client.

Both functions are SECURITY DEFINER, because the ring triggers ask them about *other people*,
whose rows no session may read.

What the ring triggers do with it:

| Level      | When it rings                                                              |
|------------|----------------------------------------------------------------------------|
| `none`     | never                                                                      |
| `all`      | on the 0→1 unread transition, **or** whenever the message names you        |
| `mentions` | whenever the message names you, gate or no gate                            |

A mention is not "one more unread" — it is the message the level exists for, so suppressing it
because something else was already unread would make the setting useless. A DM has nobody in it
to be named among, so `mentions` there reads as `all`; the UI does not offer it.

`unread_counts()` returns the levels beside the counts, as
`{channels, dms, prefs: {servers, channels, dms}}`. Every caller of one wants the other — the desktop
app draws badges and decides what may interrupt, the push isolate decides what is worth a
notification — and asking a round trip apart is how a muted channel gets one notification anyway.

## Functions and jobs (self-hosted)

Most of what a client does is a policy-checked table call; these are the exceptions worth
naming. The full set lives in `003_api.sql`, `007_limits.sql` and `009_dm_limits.sql`.

### app.enforce_retention() — pg_cron `rift-message-retention`, nightly

Applies `message_retention_days` and `message_history_cap`, taking each channel's override
where it set one (`COALESCE(c.retention_days, s.message_retention_days)`) and the server's DM
override for DMs (`COALESCE(s.dm_retention_days, s.message_retention_days)`). The DM cap counts
a conversation rather than a sender.

The window is relative, not a calendar boundary: each run removes what is older than N days *at
that moment*. A message sent this evening survives tomorrow morning's run and goes the night
after — which reads as a broken sweep if you expect "older than today".

In the `app` schema, not `public`, because it returns VOID and PostgREST would otherwise
expose a history-wiping RPC to any member. Deletes are permanent.

### app.orphaned_attachments(p_grace interval default '1 hour')

Returns `(bucket, object_name)` — a batch can span several buckets on a project hosting more
than one server.

Attachment blobs with no message left, found **without any message→blob linkage** — there is
none to have, since storage paths live inside the encrypted body. It uses the one thing the
server knows: an object's name begins with the scope it was uploaded for
(`<channelId>/…` or `dm_<lower uuid>_<higher uuid>/…`, the client's conversation context with
colons swapped for underscores). Anything older than the oldest surviving message of its scope
belonged to a message that is gone; a scope with no messages at all is entirely orphaned.

`p_grace` does two jobs. It ignores objects newer than the grace period, so an upload whose
message row is still in flight survives. And it is subtracted from the watermark, because **an
attachment is uploaded before the message carrying its key** — without that, the blobs of the
oldest surviving message would be swept on every run, silently.

### sweep_attachments(p_limit integer default 1000)

The one door into both of the above, and the only function of this feature in `public` —
because PostgREST cannot see the `app` schema, and the `sweep_attachments` edge function
reaches the database through PostgREST. Granted to `service_role` **only**; the grant is all
that stands between a member and a history sweep, so `tests/policies_test.sql` asserts it.

Returns `{orphans: [names]}`, capped. The edge function deletes them through the Storage API,
which is the only thing that frees bytes: `storage.protect_delete()` refuses a direct DELETE on
`storage.objects`.

### create_webhook(p_channel_id uuid, p_name text) — migration 013

Mints a webhook and **returns its secret once**. `SECURITY DEFINER`, granted to `authenticated`,
and it checks `app.can_manage_channels()` itself rather than leaning on a policy — there is no
INSERT grant on `webhooks` for a policy to apply to. Caps a channel at 10, so a compromised admin
account cannot quietly leave a hundred ways back in.

Returns `{reason}` where reason is `ok` (plus `id`, `secret`), `forbidden`, `no_such_channel`,
`bad_name` or `too_many`.

### post_webhook_message(p_secret text, p_text text) — migration 013

The lookup, the rate check and the insert in one statement, so nothing can sit between them.
Hashes the secret, finds the webhook `FOR UPDATE`, enforces 30 posts per minute and the 16 KB body
cap, inserts a `key_version = 0` row carrying the webhook's name, and stamps `last_used_at`.

Granted to **`service_role` only** — never `authenticated`, never PUBLIC. Its one caller is the
`webhook` edge function, which is the part that can be reached without a JWT. A member able to call
this could post under any name in any channel by guessing a secret, with the rate limit never
having to be right.

Returns `{reason}`: `ok` (plus `message_id`, `channel_id`, `server_id`), `no_such_webhook`,
`empty`, `too_long` or `rate_limited`. Every refusal looks the same from outside — a caller with a
wrong secret learns that it is wrong and nothing else.

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

### public_servers (central)

The server directory — how a self-hosted server becomes findable by someone who
was never handed an invite. Publishing is opt-in per server and reversible, and the row
is **plaintext on purpose**: everything else central stores is encrypted because it belongs
to the user, whereas a listing is an advertisement whose whole point is to be read by
strangers. It holds no service key, no LiveKit credentials and nothing about the members.

| Column       | Type        | Constraints                                | Description                                                                 |
|--------------|-------------|--------------------------------------------|-----------------------------------------------------------------------------|
| id           | uuid        | Primary Key, Auto-generated                | Listing id (central's own — unrelated to the server's)                       |
| created_at   | timestamptz | Auto-created                               | First published                                                              |
| updated_at   | timestamptz | Auto-created, bumped by `publish_server`   | Last saved; what "Updated 3 days ago" in the browser reads                   |
| owner_id     | uuid        | Required, FK → users.id (cascade)          | The account that published it; deleting the account withdraws the listing    |
| supabase_url | text        | Required, `^https?://`, ≤ 200              | Where the server lives. Not an FK to anything — central has never heard of that project |
| server_id    | uuid        | Required                                   | Which server on that project (one project may host several)                  |
| invite_code  | text        | Required, 4–64                             | An ordinary unlimited-use, permissionless invite on the target server        |
| name         | text        | Required, 1–64 (trimmed)                   | Display name                                                                 |
| description  | text        | Optional, ≤ 300                            | Free text shown in the browser                                               |
| icon_url     | text        | Optional, ≤ 500                            | Server icon                                                                  |
| tags         | text[]      | ≤ 5, each `^[a-z0-9-]{2,20}$`              | The whole of the browser's filtering. Free slugs rather than a fixed category list, which would need a migration per community we failed to imagine |
| member_count | integer     | Default 0, ≥ 0                             | **Self-reported** — central cannot count members of a database it has no credentials for. Read it as what the operator claimed at `updated_at` |
| is_listed    | boolean     | Default true                               | Delisting keeps the row, its code and its copy while taking it out of the browser |
| —            | —           | Unique (supabase_url, server_id)           | One listing per server                                                       |

**All writes go through `publish_server()`**; there is no INSERT or UPDATE grant, so the
per-account cap (`max_public_servers()`, 10) and the ownership check can't be stepped around.
SELECT is `is_listed OR owner_id = auth.uid()` — a delisted row stays visible to the person
who has to manage it — and DELETE is own-row.

`publish_server` is SECURITY DEFINER where `claim_handle` is INVOKER, because its ownership
check has to read a row that may be *delisted and someone else's*, which the select policy
hides; under INVOKER that case surfaced as a unique violation instead of an answer.
`owner_id` comes from `auth.uid()` and never from the caller.

**Central cannot verify that the publisher administers the server** — it has no credentials
for that project and never will. The first account to publish a `(supabase_url, server_id)`
owns the listing. What limits the damage is that a listing is only worth anything with a
working invite code, which only someone holding `can_create_tokens` there can produce, and
that the real admin can revoke that code on their own server without central being involved.
See ARCHITECTURE.md §3.

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

### friendships / blocks (central, migration 012)

The central gate: who may reach whom. See ARCHITECTURE §4 for the argument; what matters here is
the shape.

`friendships` is **one row per pair**, not per direction — a friendship is symmetric, and two
rows for one relationship is two chances to disagree about it. `low_id < high_id` is a CHECK, so
"are these two related" is a primary-key lookup rather than an OR over two columns.

| Column       | Type          | Constraints                            | Description                                                  |
|--------------|---------------|----------------------------------------|--------------------------------------------------------------|
| low_id       | uuid          | PK part, FK → users.id, `< high_id`    | The lower of the two ids                                     |
| high_id      | uuid          | PK part, FK → users.id                 | The higher                                                   |
| requester_id | uuid          | FK → users.id, IN (low_id, high_id)    | Who asked. The one asymmetry that is real                    |
| status       | friend_status | Required                               | `pending` until answered, then `accepted`                    |
| requested_at | timestamptz   | Default now()                          | When the **current** request began. Survives an unfriend-and-ask-again, where `updated_at` would not |
| updated_at   | timestamptz   | Default now()                          | When it was last answered                                    |

| Column     | Type        | Constraints                         | Description                              |
|------------|-------------|-------------------------------------|------------------------------------------|
| blocker_id | uuid        | PK part, FK → users.id, `<> blocked`| Who blocked                              |
| blocked_id | uuid        | PK part, FK → users.id              | Who was blocked. **Never readable by them** |
| created_at | timestamptz | Default now()                       | When                                     |

- **SELECT only, and own-row.** `friendships` where you are either side; `blocks` where you are
  the *blocker* — there is no policy anywhere that lets the blocked side read the row. Every
  change goes through an RPC: `friend_request`, `friend_request_by_handle`,
  `respond_friend_request`, `unfriend`, `block_user`, `unblock_user`. Each carries a rule (a
  request may not be accepted by whoever sent it; a block tears the friendship down with it) that
  a policy would force every later reader to re-derive.
- **Revoke from `authenticated`, not just `anon`.** Supabase ships `ALTER DEFAULT PRIVILEGES …
  GRANT ALL ON TABLES TO anon, authenticated`, so a table created in `public` arrives with
  `arwdDxtm` for both. Revoking only `anon` — as the first version of 012 did — leaves
  `authenticated` holding INSERT/UPDATE/DELETE on the whole graph, stopped by nothing but RLS
  having no write policy. That does deny, but it is one layer where the design claims two.
  **The same applies to functions**: the default is EXECUTE for PUBLIC, and 003's blanket revoke
  only covers what already existed.
- **`send_dm` is the gate, in one line.** `IF NOT are_friends(…) THEN RAISE 'not_friends'`. One
  code for every way of not being friends — stranger, pending either direction, unfriended,
  blocked either direction — because which of those it is, a block especially, is not the
  sender's to learn from a bounce. The RPC returns `state` alongside `id`/`created_at`/`quota`;
  it is always `friends`, and a client that disagrees knows its graph is stale.
- **`friend_request_by_handle(text)` is the only handle lookup on the server.** It resolves and
  asks in the same statement, so there is no endpoint that answers "does this handle exist"
  without also knocking. `no_such_user` covers a handle nobody owns, a malformed one, *and* one
  whose owner has blocked the caller — the third must be indistinguishable from the first.
  `blocked` means the caller blocked *them*, which is their own undoable decision, so it is said
  plainly.
- **The directory policy is relationship-scoped.** `users_select_directory` was `USING (true)`;
  it is now `id = auth.uid() OR knows_user(id)`, where `knows_user` is true for a friendship or
  request in either direction, or any message between the two. This is what ends handle search:
  a stranger's row is not filtered out, it is not returned.
  - It is deliberately "we have history", not "we are still speaking". A DM key is derived from
    the peer's published X25519 key and re-read on every launch, so hiding a blocked account from
    the person it blocked would quietly make *their* copy of the conversation undecryptable.
  - `knows_user` **must** be granted to `authenticated`: a policy is evaluated as the querying
    role, so a policy built on a function the role cannot execute fails with "permission denied"
    on every read, own row included. It is safe to grant — everything it reads is already
    readable by the caller, and it reports only about the caller's own relationships. Its
    predecessor `blocked_between` was **not**, and is dropped: it answered "is there a block
    between us", which told a blocked account it had been blocked.
  - `dm_conversations()` (003) is SECURITY INVOKER and joins `users`; every peer it names is one
    messages have passed with, so the policy admits all of them.
  - `claim_handle` (003) is SECURITY INVOKER and upserts on conflict, which needs the existing
    row visible — `id = auth.uid()` is first, and unconditional, for that reason.
- **`ring_recipient` checks `are_friends` first**, above the notification level. `send_dm`
  already refuses a non-friend, so this is belt and braces — but the trigger fires on an INSERT
  rather than on the RPC, and it is the loudest thing the server can do.
- Both tables are `REPLICA IDENTITY FULL` and published to `supabase_realtime` — declining,
  withdrawing, unfriending and unblocking are DELETEs, and the default replica identity ships a
  key the subscriber cannot match against its own id. A client binds `friendships` twice
  (`low_id`, `high_id`) because a Realtime filter is one column and the table is keyed by a pair.
- **`directory_profiles(uuid[])`** is how a client resolves the peers of its own conversation
  list: SECURITY DEFINER, gated on there being a message between the caller and each id. It
  answers what the policy would for the same ids — the message half of `knows_user` — and exists
  as its own function so the client has one call rather than a table read whose result silently
  depends on a policy. It cannot be used to browse.
- `friend_list()` answers all four buckets in one call. It is SECURITY DEFINER specifically so
  the blocked bucket carries handles: blocking deletes the friendship, so the policy above stops
  admitting them, and a blocked list of bare UUIDs cannot be unblocked from.

### push_relays (central, migration 010)

The credential a self-hosted server forwards its pushes over, because it cannot reach a phone by
itself. Minted by `enroll_push_relay()` from a signed-in account — the server's admin — and spent
by `claim_relay_push()`, which verifies the secret, rolls the daily window and increments the
count in one statement, so two forwards that each see room under the ceiling cannot both be let
through.

Only the digest of the secret is stored: it is shown once, at enrolment, and written straight into
the asking server's `push_config`. A leak of this table forwards nothing.

There is deliberately **no uniqueness** on `(supabase_url, server_id)`. A unique key would let the
first account to name somebody else's server hold the only slot for it, and central cannot check
who really administers a database it has never heard of. A second credential for the same server
is harmless — it is only usable by whoever holds its secret, and the server itself stores one.

| Column       | Type        | Constraints                     | Description                                          |
|--------------|-------------|---------------------------------|------------------------------------------------------|
| id           | uuid        | PK                              | Named in every forward request                       |
| owner_id     | uuid        | FK → users.id, cascade          | The account that enrolled it; deleting it revokes    |
| supabase_url | text        | http(s) URL, ≤ 200              | Recorded so a revoke list reads as names, not ids    |
| server_id    | uuid        | Required                        | Same — nothing here trusts either                    |
| label        | text        | ≤ 64                            | The server's name at enrolment                       |
| secret_hash  | text        | Required                        | SHA-256 hex. The secret itself is never stored       |
| daily_cap    | integer     | > 0, default 20000              | Devices per UTC day                                  |
| rung_today   | integer     | Default 0                       | Rolled by `claim_relay_push`                         |
| window_date  | date        | Default current_date            | Which day `rung_today` counts                        |
| is_disabled  | boolean     | Default false                   | Kill switch that leaves the row for the audit trail  |

Owners may SELECT (on named columns — not `secret_hash`, not the counters) and DELETE their own
rows, and nothing else.

`device_tokens` and `push_config` exist here too (migration 009), the same shape as the
self-hosted pair except that `push_config` is a singleton — central is one deployment.

## Enums

### channel_type

- `voice` - Voice channel
- `text` - Text channel

### read_scope

- `channel` - a read cursor pointing at a channel
- `dm` - a read cursor pointing at the other person in a conversation

### notify_level

- `all` - every message rings
- `mentions` - only a message naming you, or `@all`
- `none` - nothing rings (still counted as unread)

### notify_scope

- `server` - the fallback for everything on one server
- `channel` - one channel
- `dm` - the other person in a conversation

### friend_status (central)

- `pending` - somebody asked; `requester_id` says who. Nothing may be sent
  between the two while a row is in this state
- `accepted` - answered. There is no `declined`: declining deletes the row, so
  an absent row means exactly one thing

## Storage Buckets

### servers

- **Access**: Public
- **Purpose**: Storage for server-related assets (e.g., icons)

### chat-&lt;server uuid&gt; — one per server (migration 008)

- **Created by** a trigger on `servers`, so a server has its bucket from the moment its row
  exists. A second trigger moves `file_size_limit` whenever `max_attachment_bytes` changes,
  in the same statement. Nothing outside the database is involved.
- **Access**: Private. Select/insert require `bucket_id = 'chat-' || app.server_id()`, so a
  member reaches their own server's bucket and no other — and a banned member reaches none,
  since `app.server_id()` returns null for them. Delete additionally requires
  `owner = auth.uid()` or channel-manager, matching who may delete the message a blob
  belongs to; that is what lets a client clean up after itself, and `sweep_attachments` gets
  the rest.
- **Size cap**: that server's own `max_attachment_bytes` — exact, because the limit belongs
  to a bucket and each server has one. Storage rejects an oversized upload with a 413.
- **Purpose**: E2E-encrypted attachment blobs for channels + server DMs. Each object is
  AES-256-GCM ciphertext under a per-file key that lives only inside the encrypted message
  body — the server can't decrypt them. Objects are named `<scope>/<random>.bin`
  (scope = channel id or DM context).

### chat-attachments (legacy)

The single project-wide bucket every server used before 008. It still exists — Storage
refuses a SQL DELETE on a bucket — but has **no policy at all**, so nothing can read or
write it. `app.orphaned_attachments` spans every `chat-%` bucket, so anything left inside
drains rather than lingering.

### central-dm-attachments (central project only)

- **Access**: Private; insert restricted to the caller's own `<uid>/` folder,
  select for any authenticated user. 10 MB per-object cap.
- **Purpose**: same E2E-encrypted blobs for central DMs; uploads count against
  the sender's daily DM quota.
