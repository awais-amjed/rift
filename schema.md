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
| is_bot             | boolean     | Required, default `false`            | A program, not a person (migration 014). Pinned after registration |
| is_muted           | boolean     | Default: false                     | Moderation: enforced in get_channel_token grants  |
| is_deafened        | boolean     | Default: false                     | Moderation: enforced in get_channel_token grants  |
| chat_public_key    | text        | Nullable                           | X25519 chat identity (base64); published by the client after login |

### Bots (migration 014)

`users.is_bot` and `invites.is_bot`. A bot is the same `users` row as a person — same SIWS login,
same JWT, same RLS — so almost nothing is added. What matters is the one thing that is:

**A bot can never hold a channel key.** `channel_keyring` has a BEFORE trigger
(`refuse_bot_keyring`) that raises `bot_cannot_hold_channel_key` for a bot `user_id`. That is the
boundary; the filters in `get_channel_key`, `sweep_channel_keys` and `post_channel_keys` are an
optimisation on top of it.

The reason it is a trigger and not three filters is the failure it prevents, which is not an
attacker: `get_channel_key` returns `members_missing`, and **any member's client heals them
automatically**. A bot publishes a chat key like everybody else, so the first member to open a
channel would have wrapped it for the bot as a courtesy, silently. Three filters is three places
to forget; the fourth thing to read `users` would not know it was supposed to have one.

`users.is_bot` is pinned by `pin_is_bot` on UPDATE — no client has a column grant for it, but
`SECURITY DEFINER` functions run as the owner, and turning a person into a bot changes who may
hold the keys to a room.

`invites.is_bot` is chosen when the link is minted and cannot be changed (no UPDATE grant), so one
link never becomes the other kind. `invites_insert` refuses a bot invite that also carries
`is_server_admin`. `register_user` copies the flag onto the new row and, for a bot only, stops
granting `can_create_tokens` unconditionally — a program that can hand out membership of somebody
else's server is not a sensible default.

Phase 5 (moderation bots, BOTS.md §6) is the one case that needs the opposite, and arrives as an
explicit per-channel grant the trigger consults instead of refusing outright.

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
| to_bot      | uuid        | Foreign Key → users.id, SET NULL    | The bot a `/` command is addressed to (migration 015)          |
| reply_to    | bigint      | Foreign Key → messages.id, CASCADE  | The command a bot reply answers (migration 016)                |
| ephemeral_for| uuid       | Foreign Key → users.id, CASCADE     | A bot reply only this member may read (migration 016)          |
| mentions    | uuid[]      | Required, default `{}`              | User ids this message names — **plaintext** (migration 012)    |
| mentions_all| boolean     | Required, default `false`           | The `@all` flag                                                |

**`key_version = 0` is a body the server can read** (migration 013, BOTS.md §3). It exists so an
incoming webhook can post — GitHub holds no Rift key, so nothing it sends could ever be sealed.
Four CHECKs keep the two shapes from blurring into each other:

| Constraint | Says |
|---|---|
| `messages_one_origin` | exactly one of `sender_id` / `origin_name` — a message from nobody is not a message |
| `messages_origin_is_plain` | a non-member message is always `key_version = 0` |
| ~~`messages_plain_is_origin`~~ | **dropped in 015.** It said a member may not write in the clear; bot commands are exactly that. The rule did not disappear, it moved — see below |
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

### Bot commands (migration 015)

`messages.to_bot` addresses a message to a bot. It is plaintext by necessity: the bot holds no
channel key (014), so a sealed command is one it could never open.

**The rule, as a policy:**

```sql
-- messages_select
AND (NOT app.is_bot() OR to_bot = auth.uid() OR sender_id = auth.uid())
```

A bot reads the rows addressed to it and the rows it wrote. Nothing else — not the message before
it, not the one that mentions it, not the rest of the channel it is sitting in. A *member's* view
is unchanged: a command is an ordinary badged message and the room can see what was asked.

`messages_insert` carries the other half: plaintext is a command or it is nothing
(`key_version >= 1 OR to_bot IS NOT NULL`), the target must be an addressable bot on this server
(`app.is_addressable_bot`), and a *sealed* message may not be addressed to a bot — that shape looks
delivered and is unopenable.

**Why the insert rule is a policy and not a CHECK.** 013's `messages_plain_is_origin` was a CHECK,
and the obvious relaxation — `... OR to_bot IS NOT NULL` — would have broken the moment a bot was
deleted: `ON DELETE SET NULL` is an UPDATE, and a row that satisfied the constraint at insert would
stop satisfying it afterwards. That is the same shape as the trigger that made webhook deletion
impossible in 013. So: **CHECKs guard the shape of a row; policies guard who may write one.**

`app.can_see_message` — which the reaction policies consult, and which is `SECURITY DEFINER` so it
reads past RLS — now applies the same bot rule. Without it a bot could read who reacted to
conversations it cannot see: not content, but the shape of a room, one emoji at a time.

`pin_bot_command` refuses an edit that changes a command's body, because a bot may already have
acted on it. It deliberately does *not* pin `to_bot`, for the deletion reason above.

### Bot replies (migration 016)

Two of the three shapes in BOTS.md §5. A **channel message** everyone sees, badged like a
webhook's; an **ephemeral reply** only the asker sees. Panels are still planned — they need a
declarative block set, which is a design rather than a column.

`messages_insert` gains two clauses: a bot may write plaintext without addressing anybody (its
reply is the answer, not the question), and a bot may never write `key_version >= 1` — it holds no
channel key, so a sealed reply would be one its readers had to open. **Only a bot may set
`ephemeral_for`:** a member able to write a message inside a channel that only one other member
can see is a way to hold a conversation the room cannot audit and the operator's retention
settings do not describe.

`messages_select` and `app.can_see_message` both gain
`ephemeral_for IS NULL OR ephemeral_for = auth.uid() OR sender_id = auth.uid()` — the sender clause
is what lets a bot edit or withdraw its own answer.

Both new columns are `ON DELETE CASCADE`, and that is deliberate rather than incidental. 013 and
015 each had to route around `SET NULL` firing an UPDATE that a BEFORE trigger then fought. Here
the row has no meaning without its referent — a reply to a deleted command, a private answer for a
departed member — so it goes with it, and no trigger sees the update.

#### The unread bug this fixed

`unread_counts` filtered with `m.sender_id <> auth.uid()`. A webhook's sender is NULL, and
`NULL <> uid` is NULL rather than true, so **every webhook message had been invisible to the unread
badge since 013**: a channel of seven messages, four from webhooks, reported three. Now
`IS DISTINCT FROM`.

This is the same NULL that silenced `ring_channel_members`, which 013 caught and fixed one function
away from this one. The fix was known; nothing looked for a second instance of the shape.

`ring_channel_members` also stops waking bots (they have no phone and would be rung for rooms they
cannot read) and, for an ephemeral reply, wakes only the member it is for.

### bot_channel_keys (migration 017)

The one bot grant that spends the trust model. A moderation bot has to read every message, and
there is no cryptographic middle ground — it holds the channel key or it does not. So this is an
explicit, per-channel, **admin-only** grant (not channel manager: it is the same weight as a ban,
because it changes what somebody else's messages mean).

| Column | Note |
|---|---|
| `channel_id`, `bot_id` | the pair is the primary key |
| `granted_by`, `granted_at` | so the notice can say who decided |
| `from_key_version` | the first version this bot may hold — **one past** the current one at grant time |

Four rules make it offerable rather than regrettable:

1. **Bots are still refused by default.** 014's trigger now consults this table instead of refusing
   outright, so the only way a bot is ever keyed is somebody deciding it should be.
2. **Forward-only**, enforced on the row: `refuse_bot_keyring` raises
   `bot_key_version_before_grant` below `from_key_version`. A member joining gets full scrollback;
   a bot gets what is said after somebody chose to let it listen.
3. **Revoking rotates.** `revoke_bot_channel_key` drops the grant and the bot's keyring rows; the
   sweep then sees a bot sealed into the current version with no grant and rotates.
4. **The channel says who is listening.** `bot_channel_keys` is `SELECT`-able by every member —
   the admin grants, and every member's future messages pay for it, so a notice only the admin sees
   reaches the wrong audience. `channel_bot_listeners` is the view clients read.

There is no INSERT, UPDATE or DELETE grant: both writes go through the two `SECURITY DEFINER`
functions, so "who may listen" cannot be changed by anything that skipped the check.

#### Three self-clearing rotation signals

`sweep_channel_keys` already rotated on one: a banned member still sealed into the current version.
It is a good signal because it clears itself — the next version is sealed only to whoever is
eligible then. Both new ones are built the same way, so nothing has a flag to set or reset:

| Signal | Means |
|---|---|
| banned member sealed into current | the original |
| **revoked bot** sealed into current | same shape, same reason |
| **grant `from_key_version` above current** | a grant just made; the rotation is what makes it forward-only |

### bot_voice_grants (migration 031)

Which bots may **hear** a voice channel. Its absence is the feature: without a row, a bot's LiveKit
token is minted with `canSubscribe: false`, so it publishes into a call and receives nothing.

Before this, `get_channel_token` never asked what the caller was. `@everyone` carries `CONNECT` and
`SPEAK`, a bot holds `@everyone` like anybody else, and the token said `canSubscribe` — so any bot
invited to a server could sit in a call and hear everyone, with nothing shown in the room. Voice was
the one place BOTS.md's rule was simply false.

| Column | Note |
|---|---|
| `channel_id`, `bot_id` | the pair is the primary key |
| `granted_by`, `granted_at` | so the marker can say who decided |

`SELECT` for anyone who can see the channel — `app.can_see_channel`, not `server_id`, because a
private voice channel's membership is not public and neither is what is listening to it. No write
grant at all: `grant_bot_voice_listen` / `revoke_bot_voice_listen` are `SECURITY DEFINER` and carry
`MANAGE_BOTS`. `voice_listeners` is the view clients read for the marker, joined to a name.

Three things distinguish it from `bot_channel_keys`, and they are why it is a separate table rather
than a column:

1. **It gates subscription, live.** `set_bot_voice_listen` is an edge function because the row is
   half the job — it pushes the new permission onto the live connection, so the audio stops mid-call
   rather than at the next join. The same lesson `moderate_user` learned about mutes.

   This used to be described as making the grant *revocable*, unlike §6's key grant. That was true
   only while voice was unencrypted. A bot that may hear now needs the channel key itself
   (`bot_voice_keys`, 032), and a key that has been handed over cannot be taken back.
2. **There is no server-wide form.** §6's bulk grant exists because thirty channels one at a time
   produces a button somebody else builds badly. That argument does not carry for calls.
3. **A channel made private drops its listeners**, the same re-decision 030 makes for text keys.

### bot_voice_keys (migration 032)

The key a bot **speaks** with in one voice channel, sealed to its chat identity by a member.

Calls are end-to-end encrypted (031), and that removed the mechanism 031 had just built. Encrypting
is what makes a bot audible, holding the key is what makes it a listener, and with one key per room
those are the same act — BOTS.md §2's "write but not read is not expressible with a key", arriving
in voice. So the two directions get different keys:

```
memberKey = channelKey
botKey    = HMAC-SHA256(channelKey, 'voicebot:v1:<botId>')
```

Members hold `channelKey`, derive `botKey`, and hear the bot. The bot is sealed only `botKey` and
cannot invert HMAC, so it cannot reach `channelKey`. Two bots in one call cannot decrypt each other
either — the bot id is in the context string.

| Column | Note |
|---|---|
| `channel_id`, `bot_id`, `key_version` | the triple is the primary key |
| `is_channel_key` | false: the derived publish key. true: the channel key itself, for a bot with a listening grant |
| `wrapped_by` | which member sealed it |
| `ephemeral_public_key`, `ciphertext`, `nonce` | `wrap:v1`, same as a keyring entry (WIRE.md §6) |

`INSERT` by any member who can see the channel and **never by a bot** — it has no channel key to
derive from, and `refuse_bot_keyring` already settled that bots do not write key material.
`is_channel_key` may only be true where a `bot_voice_grants` row exists; that much the server can
check. It cannot check what is *inside* the ciphertext, and a member holding the key could leak it
anywhere — true of every channel, and not what this defends against. What it defends against is the
grant meaning one thing in the UI and another in the room.

`SELECT` by the bot itself and by members who can see the channel — the latter because they are the
ones who notice a bot has no key and seal one, the same healing loop the text keyring uses.

Changing a grant drops the rows (`bot_voice_grants_reset_keys`), so the next member into the call
seals the right key. Leaving the channel key sealed to a bot whose grant is gone would be the grant
not actually being revoked.

**A listening grant is therefore a key grant**, with everything §6 says about one: it cannot be
taken back, only rotated past. 031's note that this grant was revocable was true only while voice
was unencrypted.

### member_role_list (migration 033 exposes `is_default`)

Which roles each member holds, joined to the role's own columns so a client draws a name and a
colour without a second query.

`is_default` was missing until 033, and its absence showed: every human is given the default role
when they register (025), so every client drew a "Members" chip on every row — saying, next to
every name, what was true of everybody. A badge that never varies is furniture, and the roles worth
noticing had to compete with it. Clients hide that one chip now; the roles editor and the
per-member menu still list the role, because it is a real assignment that can be taken away and a
role you cannot see is one you cannot remove.

### users.manifest (migration 015)

A bot's published command list and data declaration (BOTS.md §4, §8). `JSONB`, null for a person
(`users_manifest_is_bot`), capped at 8 KB, written by the bot itself through the existing
`users_update_self` policy plus a column grant.

Plaintext and readable by every member on purpose: it is an advertisement, the same way a public
server listing is. It is also where a bot states what it does with what it is handed — worth more
than any amount of key management, since the bot reads the command either way and what the user
needs is to know that *before* typing. **Advertisement, not evidence:** a client renders it, and
nothing is authorised by what it claims.

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

### channel_audience(p_channel uuid) — migration 034, **dropped by 039**

Answered "who can a message here reach" as a whole set: `app.channel_eligible` for every user on
the server, gated on `app.can_see_channel` so an outsider asking a private channel got an empty
answer rather than its membership.

It existed because the composer had no way to ask. `validate_message_mentions` strips a mention of
somebody outside a private channel — silently, which is right for the wire and wrong for the person
typing: the `@` menu offered the whole roster, the name lit up in the sent message, and nothing
said the ping had been dropped.

**Dropped in 039.** The question is right and the *shape* was wrong: a whole set is unbounded by
exactly the number the client stopped being allowed to assume, and on a large private channel it
would have been cut off by the same 1000-row response ceiling. The same predicate is now a filter —
`list_members(p_channel => …)` for a page of it and `members_by_usernames(p_names, p_channel)` for
the handful of names in one message. A granted `SECURITY DEFINER` function that resolves private
channel membership and that nothing calls is a door nobody remembers, so it went with its callers.

### app.bot_reads_channel(p_channel uuid) / app.bot_reads_version(p_channel uuid, p_version int) — migration 035

Whether the calling bot holds a live grant on this channel, and whether that grant reaches back as
far as this key version. Only bots have `bot_channel_keys` rows, so neither needs an `is_bot` test.

They are what finally made the moderation grant do something. 017 built the key half correctly —
who may be granted, from which version, what revoking does, who is told — but `messages_select` had
restricted every bot to `to_bot = me OR sender_id = me` since 015 and nothing changed it. A fully
granted bot, in a public channel, holding the channel key, read **zero** member messages, while
`grant_bot_channel_key` posted *"It can read every message sent here from now on"* into the
channel.

035 widens three policies:

- **`messages_select`** — `app.bot_reads_version(channel_id, key_version)` is a fourth way past the
  bot clause, so `from_key_version` is now the same number on the way out that
  `refuse_ineligible_keyring` enforces on the way in. The ephemeral and interaction clauses are
  untouched: a grant is permission to read the channel's conversation, not a reply one person was
  shown or another bot's button press. `key_version = 0` rows stay out — webhook posts, system
  notices and commands to other bots were never sealed under any version.
- **`channel_keyring_select`** — a granted bot may read **its own** wrapped key. Without this a
  private-channel grant returned messages it had no way to open. Scoped to its own row: the rest of
  the keyring is a list of who holds a key to that room.
- **`bot_channel_keys_select`** — a bot may read its own grant, so it can tell a channel it was
  never granted from one whose history simply starts later.

A granted bot reads a private channel **without becoming a member**: `can_see_channel` still says
no, so it cannot list the channel, see the roster, or post there. Speaking needs a role with
`channel_role_access` — the same door a `/` command comes through.

### Permissions — bits 22 and 23, migration 036

`MANAGE_BOTS` was carrying three jobs of very different weight, so it became three bits:

| Bit | Permission | Gates | Default |
|---|---|---|---|
| 7 | `MANAGE_BOTS` | handing a bot a key — read a channel (§6) or hear a call (§6b) | admins |
| 22 | `ADD_BOTS` | creating an invite with `is_bot` | Moderator, admins |
| 23 | `SUMMON_BOTS` | bringing a bot into a voice channel | **`@everyone`** |

Summoning is on by default, on existing servers as well as new ones: a permission nobody holds
looks exactly like a feature that is broken, and a summoned bot's token is minted with
`canSubscribe: false` unless an admin granted listening — it publishes and cannot hear. An admin
who wants it narrower takes the bit off `@everyone`.

`ADD_BOTS` is the half that is a real change. Creating a bot invite used to need nothing but
`CREATE_INVITE`, the same bit as inviting a friend, so anyone who could bring a person could bring
a program that sits in every public channel. Administrators need no backfill — `has_perm` reads
`ADMINISTRATOR` as every bit.

### bot_voice_summons — migration 037

`(channel_id, bot_id, summoned_by, summoned_at)`. A bot asked into one voice channel, until
dismissed. Permission to **publish there and nothing else**: it is not membership and it is not
listening.

Only `channel_joinable_by` reads it, and only `get_channel_token` calls that — `app.sees_channel` is
untouched, so a summoned bot still cannot list the channel, read its roster or messages, or post in
it. `summon_bot_to_voice` needs `SUMMON_BOTS` plus the caller's own `can_see_channel` (the bot's
visibility is exactly what it does not have yet); `dismiss_bot_from_voice` needs only that
visibility, or the bot dismissing itself — a bot playing to an empty room should not need the person
who summoned it to come back.

`bot_voice_summons_reset_keys` drops the bot's `bot_voice_keys` row on insert or delete, so a
dismissed bot loses its media key rather than keeping something usable behind a closed token. The
same trigger shape as `bot_voice_grants_reset_keys` (032).

`bot_voice_key_candidates` was rewritten to join through this table. It used to list every bot on
the server for every public voice channel, so clients sealed media keys for bots that would never
join; a summon is now what puts a bot on the list, in a public channel and a private one alike.

Select is granted to the room (`can_see_channel`) **or** the bot itself — a summoned bot is not in
the channel, so `bot_id = auth.uid()` is the only way it learns where it was asked to go. No write
grant: summoning moves through the two functions.

### Ending a summon — migration 038

037 gave a summon two ways to end and both were somebody deciding. Nothing ended one because the
*reason* for it had gone, which left three holes:

- **`channels_drop_bot_voice_summons`** — closing a channel now drops its summons, as 031 already
  does for listening grants. Without it a bot summoned into a public call could still take a token
  after the channel was made private: `channel_joinable_by` reads the summon and never asks about
  privacy.
- **`app.expire_bot_voice_summons()`**, on the same hourly `pg_cron` job as the invite sweep. A
  summon is a request to come and play *now*, so one unanswered for an hour has been answered by
  events. The exact end of a call is LiveKit's to know; an age is worse at the edges and cannot
  break. A connected bot is unaffected — dropping the row takes its right to a *new* token, and
  dismissing is what disconnects.
- **`voice_summons`** — the view a client draws them from, sibling of `voice_listeners` and
  `security_invoker` for the same reason. It exists because "Send away" lives on the participant
  menu, which needs the bot to be *in* the call: a summon whose bot never arrived could be neither
  seen nor cleared.

### The member directory — migration 039

Every client read of `users` was `SELECT … FROM users` with no limit, and PostgREST is configured
with `PGRST_DB_MAX_ROWS=1000`. A server's 1001st member therefore did not fail to load — they were
*silently absent*, and everything built on the roster inherited it: the member sidebar, the `@`
menu, the `/` menu, mention resolution on send, "start a DM with…", the private channel member
picker. The other half of the problem was that the read was whole-table and repeated: the roster,
every role and every role assignment were refetched on each `users` row event, so somebody else
renaming themselves cost three full-table reads.

So this is not the same query with a `LIMIT`. It is the set of questions the client actually has,
each answerable in bounded work.

- **`member_directory`** — a `security_invoker` view fixing the columns a member row has, so all
  six functions and the client parser agree on one shape. It adds no reach: `users_select` still
  decides who is visible.
- **`list_members(p_channel, p_bots, p_banned, p_after_name, p_after_id, p_limit)`** — one
  alphabetical page, **keyset**-paged on `(lower(display_name), id)`. Not `OFFSET`: the sidebar
  pages while people are joining and renaming themselves, and a shifting sort under an offset skips
  and repeats rows at every boundary. Hand the last row back as `p_after_*` for the next page.
- **`search_members(p_query, p_channel, p_bots, p_banned, p_limit)`** — the best matches, prefix
  before substring, capped. Searching and browsing are different questions, so they are different
  functions: a ranked order cannot be keyset-paged coherently, and a typeahead does not need it.
  An empty query is the first alphabetical page, which is what lets a field open on focus. Matches
  username and display name with spaces squashed out of the latter, so `animb` finds "Anim Bot" —
  the same rule `MentionSuggestions.suggest` applies to rows the client already holds, and the two
  must agree or the list reshuffles as the server's answer lands.
- **`members_by_ids(p_ids)`** and **`members_by_usernames(p_names, p_channel)`** — the other half
  of dropping the whole-table read. Once the client no longer holds every member it still has ids
  in hand (Realtime presence, message senders, voice participants) and names in hand (the `@`s
  just typed). Without these, removing the roster read would only move the bug.
- **`member_counts(p_channel)`** — how many people and how many bots, so a paged list can say how
  long it is instead of a header reading "Offline — 50" forever.
- **`member_roles_for(p_ids)`** — role chips for the rows on screen. `member_role_list` is one row
  per (member, role), so it hits the ceiling sooner than the roster did.

Shared machinery: `app.member_page_max()` (100) caps every one of them, so no caller can ask for
the whole table however it asks; `app.member_limit()` **clamps** rather than rejects, because an
over-eager client has a bug and answering it with an error turns that bug into an empty sidebar.
`p_bots` and `p_banned` are tri-state (`NULL` both, `true` only, `false` only) — bots are listed
apart from people everywhere in the UI (BOTS.md §9), and `p_banned` defaults to `false` because a
banned member is not in the room; the moderation modal asks for them by name to lift the ban.

`p_channel` answers per query what `channel_audience` (034) answered as a whole set: who a message
here can actually reach. A caller who cannot open the channel gets nothing — not a filtered list,
which would still leak its size. `app.member_in_scope` deliberately does **not** call
`app.channel_eligible` per row: that re-reads the channel each time, and the membership test only
matters when the channel is private, so the scalar `is_private` subquery is evaluated once and the
`OR` short-circuits for every row of a public channel.

Indexes: `(server_id, lower(display_name), id)` for the keyset walk, `text_pattern_ops` on the
lowercased username and display name for prefix search, and a `pg_trgm` GIN index for substring
search created inside a `DO` block that swallows its own failure — the extension is not guaranteed
on every host, and a missing one must not take the migration down. Without it the substring pass is
a scan bounded by the page limit.

### message_reaction_tallies(p_scope, p_ids) — migration 040

Reaction counts for a page of messages, as `{message_id: [{emoji, count, mine}]}` — the shape
`ReactionOps.byMessage` used to build on the client.

The standalone reaction read asked for one row per person per emoji across a whole page, and
PostgREST caps a response at 1000 rows. Fifty messages is a page; twenty people reacting to each of
them is a lively channel, not an extreme one. Past that the response was cut off and the client
tallied whatever survived, so a count quietly read low — or your own reaction stopped being yours
and the button un-filled. Nothing about it looked wrong, which is the shape of every bug in this
batch: a limit that trims an answer instead of refusing the question.

Counting here makes the response smaller by exactly the factor that was overflowing it: one row per
(message, emoji) rather than per (message, emoji, person). Returned as **one JSONB object** rather
than a set, for the same reason `unread_counts` and `dm_conversations` are — a scalar is not
row-capped, so it cannot be truncated however many reactions a page collects. `p_ids` is capped at
100; a page is fifty. Entries are ordered by emoji so two clients draw the same message the same
way, and `mine` is the database's answer rather than a client comparing user ids it was handed.

`security_invoker`, so `message_reactions_select` (`app.can_see_message`) decides what is counted,
exactly as it does for a direct read. `ReactionOps.aggregate` stays on the client: a message page
carries its reactions as an embedded select, and folding those is free.

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

### dm_conversations(p_limit, p_before) — central migration 013

One page of the caller's conversations, newest first. Each row carries everything it draws: the
peer and their published keys, the newest envelope, the unread count, the newest inbound id a
"mark read" writes back, and the notification level (null meaning "the default", which is the
client's word). Answers `{conversations, has_more}`, keyset-paged on the last message id.

**It replaced four unbounded reads.** The client derived this list from `listRecentMessages(limit:
1000)` — the last thousand envelopes, scanned once for the newest row per peer and again for the
unread counts — with `read_state` and `notification_prefs` fetched whole beside it, both of which
grow a row per conversation. Three things were wrong with that and only the first is about
bandwidth: a thousand envelopes crossed the wire to draw a dozen rows; past a thousand *total*
messages an old conversation dropped off the list silently and its unread badge went with it; and
there was no cursor with which to ask for more, because the list was a by-product rather than a
query. The self-hosted tier had already made this move — `003_api.sql` says so in a comment above
its own `dm_conversations`, about an edge function that "pulled a thousand rows and grouped them in
TypeScript".

`SECURITY DEFINER` on the same gate as `directory_profiles`: a message exchanged, not a friendship.
A conversation has to keep opening after an unfriend or a block, because a DM key is derived from
the peer's published X25519 key and re-read on every launch — a version that stopped answering
would quietly make the other person's copy undecryptable.

It **replaces** an earlier no-argument `dm_conversations()` from 003 that nothing ever called. That
one was unbounded, and being `SECURITY INVOKER` it would have silently dropped the conversation
with anybody unfriended once 012 narrowed `users_select_directory` to `knows_user(id)` — the exact
failure `directory_profiles` exists to avoid, sitting unnoticed in an uncalled function.

Two indexes come with it — `(recipient_id, sender_id, id)` and `(sender_id, recipient_id, id)` — so
the per-peer count and the newest-inbound lookup are index range scans over one pair's messages
rather than filters over the whole inbox.

### The friends graph a tab at a time — central migration 014

`friend_counts()`, `friend_bucket(p_bucket, p_after, p_limit)` and `app_friend_state(p_peer)`,
replacing `friend_list()`. Their entries are under `friendships / blocks` below; what belongs here
is why, and the bug it fixes.

**Why.** 012 answered all four buckets in one call because the client needed all of them to draw
anything. Only three *derived facts* were ever needed outside their own tab: how many requests are
waiting (the rail badge, on screen everywhere), who is blocked (the conversation list leaves them
out), and where you stand with one peer (a conversation tile's menu). None of those needs the rows.
So the counts became a scalar, the per-peer state moved onto the conversation row beside the unread
count and the notification level, and what is left is three lists that each only their own tab
reads — fetched when that tab is opened, and paged.

**The bug.** `dm_conversations` now excludes blocked peers itself. The client used to drop them
after the page arrived, which was fine while the list was the whole thing and stopped being fine in
013, which made it paged: a page of thirty containing four blocked peers renders twenty-six rows,
while `has_more` and the cursor were both computed for thirty. The list is quietly shorter than it
should be and every further page compounds it. **A filter has to be on the same side of the page
boundary as the paging.**

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
- `friend_counts()` answers how many are in each bucket — friends, requests each way, blocks.
  Small enough to be eager, which is what lets the rows wait: it feeds the rail badge and the
  three tab labels, and those are on screen before anybody clicks a tab.
- `friend_bucket(p_bucket, p_after, p_limit)` answers **one** bucket, keyset-paged on the peer's
  handle. A handle is unique, so it is a total order by itself and needs no tiebreaker — unlike
  the member roster's display name (self-hosted 039), whose cursor carries an id alongside it.
  SECURITY DEFINER specifically so the blocked bucket carries handles: blocking deletes the
  friendship, so the policy above stops admitting them, and a blocked list of bare UUIDs cannot
  be unblocked from.
- `app_friend_state(p_peer)` answers where the caller stands with **one** person, which is what
  a conversation row carries (see `dm_conversations`) so no screen has to hold the graph to
  work it out.

These three replaced `friend_list()`, which answered all four buckets at once — right while
three of them were read from outside their own tab, and unpageable by construction. Migration
014 took those jobs away; see it for the argument, and for the paging bug it fixes in the
conversation list.

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
