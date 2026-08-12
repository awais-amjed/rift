# Rift Architecture — Identity, Auth & Encryption

Reference for how authentication and encryption work across the system. Each section is marked
**[Implemented]** or **[Planned]**. Update this file when the design changes.

## Components

| Component | Role |
|---|---|
| Flutter app | UI on all platforms; all cryptography runs client-side (`CryptoRepository`) |
| Rust core (`rust/`) | Screen capture + audio pipeline, publishes to LiveKit via flutter_rust_bridge |
| Self-hosted server | One Supabase project (Postgres + Edge Functions) + one LiveKit server. Anyone can run one; holds users, channels, messages, and E2E keyring material |
| Central Supabase | Optional convenience service run by the project: account (email+password) + encrypted vault backups. Never required — privacy mode works without it |

The trust model in one line: **self-hosted server admins are trusted with membership and (plaintext
metadata of) their own server; the central server and hosting providers are trusted with nothing** —
everything they store is encrypted client-side.

---

## 1. Identity & vault — [Implemented]

Every user's entire identity derives from a single **256-bit master seed**, generated on-device at
vault creation. Nothing about identity is ever created server-side.

### Key derivation tree

```
password ──Argon2id(salt, 64 MiB, 2 iter)──► vault key (256-bit)
                                                │
master seed (random 32 B) ◄──AES-256-GCM decrypt┘        (EncryptedSeed blob)
   │
   ├─ HMAC-SHA256(seed, "<host>:<server_id>:<version>") ──► child seed ──► Ed25519 keypair (SIWS login + signing)
   ├─ HMAC-SHA256(seed, "<host>:<server_id>:identity")  ──► stable_id (permanent per-server identity)
   └─ HMAC-SHA256(seed, "vault:v1")                     ──► vault blob key (AES-256-GCM)
```

- `<host>` is the hostname of the self-hosted server's Supabase URL and `<server_id>` the specific
  server, so identities are **per-server** — servers can't correlate a user across servers by key
  material, and two servers sharing one Supabase project still get distinct identities (see §2).
  (The central host derives per-host, without a `<server_id>`.)
- `<version>` is retained only as a derivation hook for a future crypto migration — it's always
  `v1` now (key rotation was removed; see §2). `stable_id` is version-independent.
- Argon2id runs in a background isolate (`Isolate.run`) — never on the UI thread.
- The master seed lives in platform secure storage (`flutter_secure_storage`), never in
  HydratedBloc/JSON state.

### Backup file (v2) — [Implemented]

Portable JSON with three client-side-encrypted blobs (`BackupFile`):

| Blob | Contents | Key |
|---|---|---|
| `seed` | master seed | Argon2id(password, salt) — the only password-protected blob |
| `vault` | joined-servers list (host + key version) | HMAC(seed, "vault:v1") |
| `encrypted_servers` | full server metadata (name, icon, supabase/livekit URLs, anon key) | same key, separate IV |

Session JWTs are **intentionally excluded** — they're short-lived credentials re-minted on import
via SIWS login. Restore = enter password → decrypt seed → derive everything → re-authenticate
everywhere. Storage providers only ever see ciphertext.

---

## 2. Self-hosted server auth — [Implemented]

**Sign-in-with-Web3 (SIWS / Solana).** GoTrue issues the session; no passwords, and no
seed-derived secret ever reaches the server (auth is a signature). Full design in `auth.md`.

1. **Register** (once, invite code required): the client first resolves the invite to its
   `server_id` (`resolve_invite`, no consume), does a SIWS login (below) to obtain a JWT, then
   calls `register` with that JWT + `public_key` + `stable_id` + username. The profile row is bound
   to the GoTrue identity — `users.id = auth.uid()` — so every FK carries the GoTrue uuid and RLS
   ownership is simply `auth.uid() = <col>`.
2. **Login (SIWS)**: the client signs a Sign-in-with-Solana message with its per-`(host, server_id)`
   Ed25519 key (base58 of the key is the "address") and posts it to the `login` Edge Function, which
   proxies GoTrue's `grant_type=web3` server-side (so no anon key is needed client-side) and returns
   a GoTrue session (access JWT + refresh token). `Chain ID: solana:mainnet`, base64 signature.
3. **Session refresh**: all API calls flow through `ServerCubit._callWithAutoRefresh` (and the
   notifications cubit keeps every *joined* server's JWT fresh); a session near expiry (or a rejected
   JWT) triggers a silent re-login — the key is derived from the seed, so it never prompts.
   `server.token` holds the JWT.
4. **Authorization** is RLS, for almost everything. The client talks to PostgREST directly under
   the policies in `002_security.sql`; `anon` is revoked from every table, members get
   column-level grants, and the `app.*` helpers each re-check ban state, so a ban bites on the
   next statement rather than at token expiry. Edge Functions remain only where a call holds a
   secret (LiveKit credentials, the GoTrue admin grant) or runs before the caller is a member
   (`resolve_invite`, `register`); those verify the JWT locally against the stack's JWKS (ES256,
   no GoTrue round-trip — `_shared/jwt.ts`) and load the `users` row on every call.

**Permissions** are three user flags — `is_server_admin`, `is_channel_manager`,
`can_create_tokens` — with the delegation rule: *you can only grant what you hold*.

**Multiple servers per project:** identity is derived per `(host, server_id)` —
`childSeed = HMAC(seed, "<host>:<serverId>:<version>")` — so two servers sharing one Supabase
project yield **distinct** SIWS identities (distinct `auth.uid()`), and the same person can join
both. Username uniqueness is per-server, as are `public_key` and `stable_id`.
The central host derives per-host (no `server_id`), unchanged.

**Removed:** key rotation and the whole opaque-token + challenge machinery (`tokens` /
`auth_challenges` tables, `get_challenge` / `verify_challenge` / `rotate_key`). Seed-derived keys
share the seed's fate, so per-derived-key rotation defended against nothing reachable here.

---

## 3. Central account & cloud backup

### Option B split-key, one password — [Implemented]
Optional email+password Supabase account; the backup blob lives in a private storage bucket
(`backups/{user_id}/vault.json`, RLS-guarded). Default onboarding is the central-account flow;
the local-only flow remains as the **privacy option** (no central-server contact at all, manual
vault password, offline backup-file export/restore in settings).

One password typed by the user; two independent keys derived client-side
(`CryptoRepository.deriveAccountKeys` — Argon2id stretched with SHA-256(email) as salt, then
HMAC-split into `account:auth:v1` / `account:vault:v1` contexts):

```
password ──KDF(context: "auth")──►  auth verifier  → sent to Supabase as the login password
         └─KDF(context: "vault")──► vault password → feeds the existing Argon2id seed encryption
```

The real password never leaves the device, so a compromised/malicious central server cannot
decrypt stored backups (Bitwarden/Proton model).

- **Auto-sync**: backup re-uploaded on vault change; checked for updates on sign-in/app start.
- **Conflict rule**: fresh device → import cloud backup silently; existing local vault + different
  cloud backup → ask the user.
- **Forgot password**: email reset recovers the *account*, not the backup — old blobs are
  undecryptable by design. UI must warn. Recovery path: any still-signed-in device or file backup
  re-encrypts and re-uploads under the new password.
- **[Planned follow-up]**: recovery key — random code shown once at signup, wraps the vault key a
  second time so password *or* recovery key can decrypt.

### Cross-device sync model
The encrypted backup blob **is** the sync mechanism: same seed on every device = same identity
everywhere. Server list becomes eventually-consistent via auto-upload + import-on-start. There is
no realtime state sync and none is needed — live state (presence, voice) lives on each server.

---

## 4. Chat encryption — [Implemented July 2026 — group channels, server DMs, central DMs]

All messages E2E encrypted. Encryption keys are X25519, derived from the master seed exactly like
the Ed25519 identities (per-host, versioned) — **the backup format needs no changes**.

### DMs — "Design 1": encrypt to identity
Diffie-Hellman between sender private key and recipient public key → shared secret → AES-GCM.
Only the two identities can ever decrypt. Seed recovery restores full history; true seed loss
makes history permanently unreadable (accepted).

### DM topology — two tiers (decided July 2026)

Same Design-1 crypto in both tiers; different hosts, different policies. The central server is
a **funnel, not a home**: the project runs on no revenue, so central hosting cost must stay
flat. People find each other on central, exchange first messages there, then move real
conversations to a self-hosted server they share (or any messenger they like).

|               | Central DMs                            | Server DMs                                     |
|---------------|----------------------------------------|------------------------------------------------|
| Purpose       | discovery + first contact              | real conversations                             |
| Storage       | central Supabase                       | a self-hosted server both users are members of |
| Identity keys | X25519 derived for the central host    | X25519 derived for that server's host          |
| Delivery      | GoTrue RLS + native Realtime           | Edge Functions + Realtime Broadcast            |
| Limits        | per-sender daily quota; 30-day TTL; per-conversation history cap (oldest trimmed first) — fixed, Rift's call | no message quota; a TTL and a history cap the admin sets, **off by default** |
| Media         | allowed; counts against quota, per-file size cap | allowed; per-file size cap the admin sets, and blobs swept with their messages |
| Unread badges | `read_state` cursors + `unread_counts()` | the same, for channels and DMs alike |

- Central limits are enforced **server-side** (the send path checks a daily counter; a
  scheduled job sweeps expired and over-cap rows) — a modified client can't bypass them.
  Default knobs (tunable constants): ~100 messages/day per sender, 30-day TTL, ~500 messages
  per conversation.
- Deletion is server-side: past the TTL/cap the ciphertext is gone from central; clients
  render what the server still has.
- The UI surfaces the remaining daily quota as it tightens and nudges long conversations
  toward a shared server ("Continue on <server>" when one exists).
- Privacy-mode users (no central account) simply have no central DMs; server DMs still work.

### Operator limits on a self-hosted server [Implemented August 2026]

Self-hosted used to impose nothing, on the reasoning that a server is somebody's own disk and
therefore their own call. That was right about *whose* call it is and wrong about there being
nothing to decide: an operator running a server for friends still may not want two of them
filling the disk, and had no way to say so.

So limits exist here too — as columns an admin sets from Server Settings, with **every sweep
defaulting to off**. A server that is upgraded and never touched behaves exactly as before.
Migration 007 is the whole feature.

**There is deliberately no daily message quota.** A quota is a rate limit, not a storage
bound: N messages a day, forever, is still unbounded — it only takes longer to get there. The
thing an operator is actually worried about is the disk, and the instruments for that are a
ceiling on kept history and a ceiling on file size. Central still rations messages per day,
because central is a funnel and rationing *is* its product; a self-hosted server is a home.

| Limit | Column | Per-channel override | Off by default |
|---|---|---|---|
| Per-file attachment size | `servers.max_attachment_bytes` | — | no; 25 MB, the ceiling the bucket already had |
| Delete messages older than N days | `servers.message_retention_days` | `channels.retention_days` | yes |
| Keep at most N messages | `servers.message_history_cap` | `channels.history_cap` | yes |

The overrides are three-valued: NULL inherits the server's number, a value sets the channel's
own, and 0 explicitly opts the channel *out* of a server-wide sweep. NULL and 0 are different
answers and the UI keeps them apart. Voice channels carry the columns and ignore them — they
hold no messages, so their settings dialog shows the name alone rather than a switch wired to
nothing. DMs have no per-conversation override; the server's cap applies, and it counts both
people together, since a conversation is one bucket seen from either side.

#### Deleting a message has to delete its files

This is the part that makes the limits mean anything, and it is more awkward than it looks.

A message row is tiny — `ciphertext` is capped at 16 KB, so even a thousand messages is a few
megabytes. **The storage is the attachments.** Sweeping rows without their blobs would be a
limit that looks like it works and doesn't.

Two constraints shape the answer:

- **The server can't find a message's blobs.** Storage paths live inside the E2E-encrypted
  body — that is the whole design. Only a client that has decrypted the message knows which
  blobs are its.
- **The database can't delete them.** `storage.protect_delete()` refuses a direct DELETE on
  `storage.objects` ("Use the Storage API instead"), so an `ON DELETE CASCADE` from a
  message→blob table would have deleted linkage rows and freed **zero bytes**. Such a table
  would have bought a metadata leak and nothing else, which is why there isn't one.

So the work splits in two:

- **A client deleting a message deletes that message's blobs**, through the Storage API, using
  the paths it just decrypted (`AttachmentCleanup`). A `chat_attachments_delete` policy lets a
  member remove what they uploaded, and a channel manager remove anyone's — matching who may
  delete the message itself. Best-effort: a blob must never be able to fail the delete around
  it.
- **`sweep_attachments` collects everything no client will.** Blobs of messages the retention
  sweep removed, uploads whose message insert then failed, channels deleted outright. It finds
  them with no linkage at all, using the one thing the server does know: an object's name
  begins with the scope it was uploaded for, so anything older than the oldest surviving
  message of its scope belonged to a message that is gone. It is an edge function because only
  something holding the service key can call the Storage API. Clients run it on server-ready.

One subtlety in that watermark, worth stating because getting it wrong is silent data loss: an
attachment is uploaded *before* the message carrying its key, so the blobs of the oldest
surviving message are themselves older than the watermark. Comparing against a bare watermark
would delete the attachments of the very message it was protecting, on every sweep. A one-hour
margin covers the gap, and doubles as protection for an upload still in flight.

The central tier has no such sweep — its 30-day TTL trims messages but not storage, so a
central attachment is only ever freed by the client that deletes its message.

### Group channels — "Design 2": wrapped channel key
- Each channel has a random symmetric **channel key**; every message encrypted once with it.
- The server stores a **keyring**: the channel key encrypted separately for each member's public
  key. The server can't read any entry.
- **Join**: an existing member's client wraps the key for the newcomer → full history readable
  (decision: wrap **all** historical key versions — full scrollback, Discord expectation).
- **Kick/ban**: rotate to a new channel key version for subsequent messages.
- **Seed-loss recovery**: re-invite + re-wrap restores history access without touching messages.

### Rich messages — structured body + attachments [Implemented July 2026]

A message's encrypted plaintext is no longer a bare string but a small **tagged
JSON body** (`{t:"rift.msg", v, text, att:[…]}`, `MessageBody`). This carries
attachments (and future rich content) **without changing the envelope wire
format, message tables, or signatures** — only the *content* of the sealed
string changed. Decoding is backward compatible: any plaintext that isn't our
tagged JSON — every pre-existing message — is treated as plain text.

Attachments (images, voice notes, files) are E2E-encrypted just like text:
- The file **bytes** are AES-256-GCM-encrypted client-side under a **fresh
  per-file key** and uploaded as an opaque blob to a Storage bucket
  (`chat-attachments` on each self-hosted server; `central-dm-attachments` on
  central). The server only ever holds ciphertext.
- The per-file key + nonce + metadata (name, mime, size, storage path) live
  **inside** the (separately-encrypted) message body — never as storage
  metadata. So a compromised server can't decrypt a blob it stores, nor learn
  its filename. Bucket access is "authenticated" (blobs are useless without the
  in-message key; paths are unguessable random names).
- Central attachments count against the sender's daily DM quota and are bounded
  by a per-file size cap (bucket `file_size_limit`).

**An edit or a delete rings a doorbell that names the message.** The send
doorbell sends receivers to fetch rows *newer* than the newest one they hold,
which can never surface a change to a message they already have — so for a long
time neither edits nor deletes reached anyone with the conversation already
open; they appeared on the next open, and not before. The change doorbell
carries the message id and nothing else: not the new text, not even which of the
two happened. The receiver re-reads that one row and finds out — present means
an edit, absent means a delete. Keeping the answer in the database is what holds
the invariant that a forged broadcast costs a wasted request rather than letting
anyone put words in someone else's message or make one disappear. Central DMs
get the same behaviour from a Postgres `UPDATE` subscription instead of a
broadcast; deletes there still wait for a reopen, because a `DELETE` event
carries only the primary key and so can't be filtered to the recipient.

**Emoji reactions are deliberately NOT E2E, and exist only on self-hosted
servers.** Unlike message content, an emoji tally is stored in the clear
(`message_reactions` / `dm_message_reactions`) — the server sees who reacted
with which emoji. This
is the accepted metadata cost of a Discord-like reaction UX; message *content*
stays encrypted. Toggling is one call (add if absent, else remove); clients
tally them from the reaction rows they can already read, and refresh live off
Realtime.

Because they are not encrypted, reactions can ride along with the message page
as a PostgREST embed rather than being fetched after it — opening a channel is
one round trip, and the cost does not grow as the reader scrolls back. A change
*after* the page loaded is what the reaction doorbell is for, and it names the
message that changed so each listener re-reads one message instead of its whole
loaded history. A ring without a name still falls back to re-reading everything,
which is what keeps a client on an older build correct rather than silent.

Central DMs have none of this. That tier is first contact — quota'd, retained 30
days, running on infrastructure the project pays for — so it carries only what
first contact needs, and a conversation worth reacting to belongs on a server
the two of you share by then.

**Unread state is server-side, and it is a bookmark.** Each conversation has one
row in `read_state` holding the newest message that member has read — per
channel and per DM peer, in both tiers. `unread_counts()` returns every badge in
one round trip by counting messages above those cursors, and `mark_read()` moves
one forward (never backward, so two devices can't un-read each other's
progress). Keeping the cursor on the server rather than in local storage is what
makes a conversation read on one device read on the others; own-row RLS is what
keeps it from becoming a read receipt, since a sender can never see it.

It used to be a fanned-out `notifications` row per recipient per message, which
cost a write per member per send and a retention job to bound it. That existed
only because a client wasn't allowed to read the message tables, so it needed
something else to subscribe to. With policies on `messages` and `dm_messages`,
Realtime re-checks them per subscriber and delivers the messages themselves —
so badges come from the rows they are about, and the fanout is gone.

What the client still has to decide is *when* a badge clears: when the surface
holding it is on screen **and** the window is focused, not merely when a cubit
still has the conversation open behind another view.

### Decisions locked in for day one
1. **Every message is Ed25519-signed by the sender** — a shared channel key must not allow
   member/server forgery. Unsigned history can't be retro-signed, so this ships with message v1.
2. **Wrapping duty**: inviter's client pre-wraps at invite time; all clients sweep a
   pending-key-requests queue on launch (covers members added while everyone was offline).
3. **Rotation races**: unique `(channel_id, key_version)` server-side; first insert wins,
   losers re-wrap the winner's key.
4. Messages table carries an `encryption`/key-version column from the start.

### Accepted limitations (document honestly, do not "fix")
- **Metadata is visible** to the server admin and host: who, when, where, how much. E2E covers
  content only.
- **No forward secrecy — deliberate.** Static keys are what make "recover seed → recover history"
  possible; ratcheting would destroy that. This is a product choice, not an oversight.
- Search becomes a client-side index; automod is metadata-only; link previews are generated by
  the sender's client; mobile push is data-only + on-device decryption.

---

## 5. Voice, video & screenshare — [Implemented]

- Client asks its self-hosted server for a channel token (`get_channel_token`); the Edge Function
  mints a LiveKit JWT (room = channel id, identity = user id, 1 h TTL, `roomAdmin` for channel
  managers). Screenshare sessions use the same flow with an `_screenshare` identity suffix.
- Media flows through the server's own LiveKit instance over **DTLS-SRTP** — encrypted in
  transit, unreadable to network observers.
- **The LiveKit SFU can technically access media frames** (that's how an SFU works). Since the
  LiveKit server is run by the same admin who runs the Rift server, this matches the trust model:
  voice has the same privacy level as group chat metadata — protected from outsiders, visible in
  principle to the server operator. LiveKit's optional frame-level E2EE exists as a future
  hardening option if that trade-off changes.
- Screenshare capture (video + per-platform system audio) runs in Rust for performance and
  publishes directly to the LiveKit room.

### Two questions, two transports

*Who is online* and *which voice channel are they in* are both answered by Realtime on the selected
server, and deliberately not by the same mechanism — they change at completely different rates.

**Presence (`presence:<serverId>`) carries only `{userId, displayName}`.** Realtime rations how
often one client may publish presence: **5 events per 30 seconds**
(`CLIENT_PRESENCE_MAX_CALLS` / `CLIENT_PRESENCE_WINDOW_MS`, realtime v2.102 defaults; the tenant
columns `max_client_presence_events_per_window` / `client_presence_window_ms` override them). The
sixth is not refused — realtime logs `ClientPresenceRateLimitReached` and **terminates the
channel** (`shutdown_response` → `{:stop, :normal}`).

That failure is close to silent. The client's own copy of the presence state still lists it, so it
looks online to itself while for everyone else it has left; every later track goes to a channel
process that no longer exists and times out. Nothing rejoins on its own. **Only building a new
channel recovers** — the ration and the channel both belong to the connection.

A budget that small is only safe for a fact that doesn't move, so presence publishes **once per
connection**. What it buys in return is the thing nothing else here can do: when the socket dies
the entry dies with it, and every other member is told.

**Broadcast (`voice:<serverId>`) carries the channel someone is in** — one message per hop, because
people change voice channels constantly. Broadcast has no per-client window. It counts against the
tenant-wide events-per-second budget that every chat topic already shares, and moving location off
presence doesn't add to that: a presence diff fanned out to the same subscribers either way.

That tenant budget is the one a self-hosted server actually has to be provisioned for. It defaults
to **100 events per second**, it counts **deliveries rather than sends** (one broadcast to 20
subscribers is 21 events), and `postgres_changes` — which is how unread badges reach every member
of every joined server — spends the same allowance. Twenty or so chatty members is enough to
exhaust it, whereupon realtime terminates channels with `Too many messages per second`. Raising it
is a deployment step, not a code one: `UPDATE _realtime.tenants SET max_events_per_second = …` as
`supabase_admin`, then recreate the container so it re-reads the cached tenant config. Do it in
that order and it still reverts on the *next* restart — the self-host seed deletes and reinserts
the tenant row on every boot with no `max_*` fields, so `SEED_SELF_HOST` has to go to `false` first
(the tenant already exists by then, and schema migrations run regardless of it). LOCAL_DEV.md
"Realtime rate limits" has the full procedure and the reasons short load tests fail to reproduce
any of this.

Broadcast is stateless, so a client that has just connected has missed every hop so far. It starts
from a snapshot — the `voice_roster` edge function asks LiveKit, which is the only party that
can't be out of date, and the merge lets any delta that raced the fetch win.

The two are joined when the state is built: **a location is only drawn while presence still vouches
for the person it belongs to.** A client that crashes mid-call never gets to say it left, and
doesn't have to.

Four rules follow, and `ChannelPresenceCubit` exists to keep them:

1. **Location never travels on presence.** Announcing a hop used to cost two presence events
   (leaving, then arriving), so moving a member three times in half a minute was enough to make
   them disappear until they restarted the app.
2. **Stay inside the ration anyway.** The one publish per connection still waits for room in the
   30-second window (we spend 4 of the 5, keeping one in reserve) — a guard rail against anyone
   quietly walking back into the limit.
3. **Don't announce the gap.** The half-second of "nowhere" between leaving one voice channel and
   joining the next is never sent, or a move would blink the member out of the channel list.
4. **A channel that stops working is rebuilt, not retried** — on a refused track or any
   non-subscribed status, with a doubling backoff so a broken server can't become a reconnect
   storm. Untracking is never done: it is itself a presence event, it blocks for the full socket
   timeout when the channel is already dead, and closing the socket does the same job for free.

---

## 6. Threat model summary

| Adversary | Identity/seed | Backups | Group chat | DMs | Voice |
|---|---|---|---|---|---|
| Network observer | safe | safe | safe (TLS) | safe | safe (SRTP) |
| Central server / its host | safe (E2E) | safe (E2E) | n/a | n/a | n/a |
| Self-hosted server's hosting provider | safe | n/a | safe once E2E chat ships | safe | SFU-accessible |
| Self-hosted server admin | safe | n/a | readable (they're a member anyway) | **safe** | accessible |
| Device thief (no password) | Argon2id + secure storage | — | — | — | — |

## Speaking indicator

Whether a participant's tile/row glows is decided in two different places, on
purpose:

- **Remote participants** — LiveKit's active-speaker detection (the SFU already
  computes audio levels, so the client does no extra work). Sensitivity is a
  *server* setting: `audio.active_level`, `audio.min_percentile`,
  `audio.update_interval`, `audio.smooth_intervals`. The stock defaults are too
  insensitive for conversation; recommended values and what each does are in
  LOCAL_DEV.md. A deployment that leaves them at default will have a sluggish,
  under-triggering indicator — that is a configuration problem, not a bug.
- **The local user** — measured on-device by `SpeechDetector` from the mic
  level. `update_interval` is a floor on how fast the server view can react and
  a few hundred ms of lag on your *own* indicator is very noticeable. It is one
  analyser on the local mic, regardless of channel size.

An earlier version ran an analyser per *remote* track too. It gave identical
behaviour everywhere with no server config, but the CPU scaled with the number
of people in the channel to duplicate work the SFU was already doing — not a
trade worth making.
