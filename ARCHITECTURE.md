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

The whole of it lives in `rift_crypto/`, a package with no Flutter in it, so a
headless bot SDK depends on the same copy the app does rather than on a second
implementation. `WIRE.md` describes the formats and `test/wire_vectors.json`
freezes them.

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
   The message's domain/URI are a fixed `localhost`, never the server's address — GoTrue refuses
   IP domains and non-HTTPS names, and the field is wallet ceremony Rift has no use for.
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
  undecryptable by design. UI must warn. Recovery path: the recovery key below, any still-signed-in
  device, or a file backup, re-encrypting and re-uploading under the new password.

#### Recovery key [Implemented September 2026]

A second, independent wrapping of the **same master seed**: `Argon2id(recoveryKey, salt2)` beside
the password's `Argon2id(password, salt)`. Neither knows about the other, which is what makes it a
spare key rather than a hint — forgetting the password costs one blob and nothing else, and
changing the password does not touch the recovery blob because the plaintext under both is the
seed, and the seed never changes.

- **Format**: 25 characters of Crockford base32 (no `I`, `L`, `O`, `U`) as `XXXXX-XXXXX-…` — 125
  bits, drawn five bits at a time so the alphabet maps on with no modulo bias. Normalisation folds
  case, drops separators and reads `I`/`L`→`1`, `O`→`0`, because those are the mistakes people
  actually make copying it off paper.
- **Issued at vault creation, shown once, never stored after acknowledgement.** `/recovery-key` is
  a router gate, not a notice: while `VaultState.pendingRecoveryKey` is set, no other route is
  reachable. The plaintext key is held in secure storage only between generation and
  acknowledgement, so a crash on that screen cannot strand a blob whose key nobody knows.
- **Travels in the backup file** (`BackupFile.recovery`, v3) — otherwise it would only work on the
  device that generated it, which is the one device you do not need it for. v2 files still load
  with a null recovery blob, which is exactly what they meant.
- Settings can **replace** it (password required) but never display it; there is no stored copy to
  show, and a second copy would only be a thing to leak.

#### Changing the password [Implemented September 2026]

One typed password stands behind two things that fail independently: the verifier GoTrue stores
and the key wrapping the seed. The order is chosen so they cannot end up disagreeing —

1. prove the current password against the **local seed blob** (no email spent on a wrong guess);
2. on an account, GoTrue `reauthenticate()` emails a nonce — the step that separates "walked past
   an unlocked laptop" from "has the password *and* the inbox". Privacy mode has no address and
   skips it;
3. re-wrap the seed locally — reversible, nothing has left the device;
4. `updateUser(password: KDF(new, "auth"), nonce:)`;
5. **if that fails, put the seed back**, or the account would sign in fine and open nothing;
6. only then re-upload the backup.

The recovery key keeps working throughout, and is the reason a torn state is survivable at all.

#### Confirming the address [Implemented September 2026]

When the central project requires email confirmation, sign-up returns no session and the app shows
a "check your email" notice. That notice used to be a dead end: one button, which took you to a
sign-in the server would refuse until the link was clicked. A link that never arrives — lost mail,
spam folder, an expired token — locked you out of the account you had just made, with nothing on
screen able to help.

`SupabaseBackupCubit.resendConfirmation` sends another. Three things shape it:

- **A refused sign-in is a route into it.** GoTrue answers `email_not_confirmed` for an account
  that exists with the right password and an unconfirmed address, and that is where most people
  meet this screen — long after the one-time notice at sign-up. `SupabaseBackupRepository` now
  keeps GoTrue's `code` alongside its message (`_authFailure`) so the cubit can tell that apart
  from a wrong password, and puts the reader back on the notice instead of showing a refusal.
- **The address is never retyped.** Resend uses `state.email`, the address signed up with. A field
  here would turn the screen into a way of sending mail to anybody.
- **The confirmation is conditional on purpose.** The server does not say whether an address is
  real, already confirmed, or unknown, so neither do we: *"If … is waiting to be confirmed, another
  link is on its way."* Anything more definite would answer which emails hold accounts.

**Mail is metered**, and the UI has to respect that rather than discover it. Supabase enforces a
minimum gap per address (`smtp_max_frequency`, 60s on the central project) *and* a project-wide
hourly cap, and a refused request spends the same allowance as an accepted one. So the cooldown
starts whether the send succeeded or failed, and the control becomes a plain countdown rather than
a disabled button — a greyed-out button invites the clicking it exists to prevent. A rate-limit
refusal is passed through in GoTrue's own words because they name the wait; every other GoTrue
message is replaced, being written for a developer reading a log.

The built-in mail service caps the whole project at a handful of emails per hour. **Custom SMTP is
a prerequisite for turning confirmation on for real users** — not a nicety.

### The public server directory — [Implemented August 2026]

A server created in the app existed nowhere but on its own Supabase project and in the vaults
of the people already on it. There was no way to find one you had not been handed an invite
to, which made *self-hosted* and *private* the same word: an operator who **wanted** to be
found had no way to say so. Central is the only place both sides already share, so the
directory lives there for the same reason handles do.

**A listing is plaintext, and that is not a hole in the trust model.** Everything else central
stores is encrypted because it belongs to the user; a listing is an advertisement, and its
whole point is to be read by strangers. It is opt-in per server, reversible, and holds:

| Published | Not published |
|---|---|
| Name, description, up to five tags, icon | Anything about the members |
| The server's Supabase URL and server id | The service key, the LiveKit credentials |
| A member count the admin's client reports | Any message, key or keyring entry |
| One ordinary invite code on that server | Any authority over the server |

Joining from the browser is the invite-link path with the link filled in: `resolve_invite` →
SIWS → `register`, all against the target server. **Central hands out the address, never the
authority** — which is also why the self-hosted schema needed no migration for any of this.

Writes go through `publish_server()` (there is no INSERT or UPDATE grant), so the per-account
cap and the ownership check cannot be stepped around, and `owner_id` comes from `auth.uid()`
rather than the caller. Delisting keeps the row; removing it doesn't. Publishing needs a
claimed handle, because the listing is owned by an account and that ownership is what lets
you edit or withdraw it from another device.

The question is asked on the step after a server is created, and lives afterwards as the
**Discovery** column of Server Settings. That column is the one place in the app where a
single Save writes to two databases under two accounts — the server's own update first, the
listing second, and the dialog reports which half landed rather than pretending it is one
write. It sat in a dialog of its own first, precisely to avoid that; being in the place
people look for it turned out to matter more than the seam being tidy.

#### What central cannot check, and what limits it

**Central cannot verify that the publisher administers the server.** It has no credentials for
that project and never will — the same property that makes self-hosting mean anything. So the
first account to publish a `(supabase_url, server_id)` owns the listing, and a member who is
not an admin could in principle publish a server before its owner does.

What stops that being worth doing is that **a listing is only useful with a working invite
code**, and minting one requires `can_create_tokens` on that server. A squatter without it
publishes a dead link. And the real admin can revoke the code on their own server, which kills
the listing without central being involved at all. This is documented rather than fixed:
the fix would be central verifying a JWT issued by a server it has never heard of, which means
central making outbound requests to arbitrary URLs on a stranger's say-so.

The member count is self-reported for the same reason, and shown next to when it was last
saved rather than as a live figure.

Privacy-mode users have no central account and so no browser and no listings; their servers
work exactly as before, reachable by invite link.

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

### Friends, requests and blocks — the central gate [Implemented August 2026]

Central's directory used to be readable row-by-row by every signed-in account, on the reasoning
that you cannot message somebody you cannot find. What that had silently come to mean was that
the whole membership was *enumerable* — three letters into a search box returned strangers — and
that anyone who appeared there could be messaged, without limit, forever. The directory was the
product; the open inbox behind it was an accident.

The rule now is one sentence:

> **You cannot send anything to somebody who is not your friend.**

Not one message, not a message that doubles as a request. Contact begins with a friend request,
and a friend request carries no payload — so there is no channel to abuse and nothing to
withdraw-and-resend. Accepting is what opens the composer, and it is the only thing that does.

**Finding somebody means typing their handle in full.** There is no prefix search: `users` is
relationship-scoped (your own row, plus anyone you have a friendship, a request or a message
with), and the only way to turn a handle into a person is `friend_request_by_handle`, which
resolves and asks in the same statement. You learn that a handle exists by successfully asking
its owner to be friends — a fact they are told at the same moment, and one that costs you a
visible row in their Pending list.

That is the whole trade, and it is worth being precise about: an exact-handle endpoint is still
an existence oracle for handles you can *guess*. What it is not is a list. It cannot be walked,
sampled, or watched, and a handle nobody told you is 20 characters of `[a-z0-9_]`.

| Table | Shape | Why |
|---|---|---|
| `friendships` | one row per **pair**, canonical `low_id < high_id`, plus `requester_id`, `status`, `requested_at` | A friendship is symmetric. Two rows for one relationship is two chances to disagree about it, and a pair that is friends from one side and pending from the other has no meaning and no repair. |
| `blocks` | directed `(blocker_id, blocked_id)` | Ends the relationship both ways *and* stops the handle resolving — a block that only bounced messages leaves a second account as the obvious next move. |

Every state change is an RPC (`friend_request`, `friend_request_by_handle`,
`respond_friend_request`, `unfriend`, `block_user`, `unblock_user`); there is **no
INSERT/UPDATE/DELETE grant on either table**. Each change carries a rule with it — a request may
not be accepted by whoever sent it, a block has to tear the friendship down with it — and a rule
spelled in a policy has to be re-derived by every policy that reads the table afterwards.
Reading it is `friend_counts()` plus `friend_bucket()` a tab at a time (central migration 014).
It used to be `friend_list()`, all four buckets at once, because everything on screen was drawn
from all of it — until the counts took over the badge and the tab labels, and the per-peer state
moved onto the conversation row. What was left is three lists that only their own tab reads.

**Four consequences worth stating:**

- **Nothing here deletes a message.** Declining removes the request, unfriending removes the
  friendship, blocking removes both and adds a row. All three leave the conversation where it
  was: a request arrives empty, so there is nothing of the sender's to throw away, and a
  conversation two people already had is not something one of them gets to erase from the other.
  Unfriend, re-request, accept — the history is where they left it.
- **A block is invisible from the side it lands on.** No policy lets you read a row where you
  are `blocked_id`, and there is no function granted to `authenticated` that will answer the
  question either. From the blocked side the handle simply stops resolving: `no_such_user`, the
  same refusal a handle nobody owns gets. `send_dm` says `not_friends` for every way of not
  being friends — stranger, pending, unfriended, blocked — so a bounce reveals nothing.
- **The directory predicate is "we have history", not "we are still speaking."** A DM key is
  derived from the peer's published X25519 key and re-read on every launch, so a policy that hid
  a blocked account from the person it blocked would quietly make *their* copy of the
  conversation undecryptable. Nothing deleted; it just stops opening. Blocking takes away reach
  and discoverability — it does not reach into somebody else's device.
- **A request does not ring.** `send_dm` already refuses it, but `ring_recipient()` checks
  `are_friends` *above* the notification level anyway: waking a phone is the loudest thing this
  tier can do, this trigger fires on an INSERT rather than on the RPC, and a future path into
  `dm_messages` that forgets the gate should not also get to wake somebody.

**Server DMs are deliberately not gated.** An invite already let that person in, and
`app.can_receive_dm` already scopes DMs to fellow members of that server. Membership *is* the
relationship there. Gating them would also mean every self-hosted server knowing your central
friends list — and central identities and server identities are unlinked on purpose (§2), so
that is a leak, not a feature.

Existing conversations were backfilled as accepted: applying the gate retroactively would turn
every one of them into a pair who can read their history and not add to it, waiting on a request
neither of them sent.


### Operator limits on a self-hosted server [Implemented August 2026]

Self-hosted used to impose nothing, on the reasoning that a server is somebody's own disk and
therefore their own call. That was right about *whose* call it is and wrong about there being
nothing to decide: an operator running a server for friends still may not want two of them
filling the disk, and had no way to say so.

So limits exist here too — as columns an admin sets from Server Settings, with **every sweep
defaulting to off**. A server that is upgraded and never touched behaves exactly as before.
Migration 007 is the feature; 009 extends it to DMs.

**There is deliberately no daily message quota.** A quota is a rate limit, not a storage
bound: N messages a day, forever, is still unbounded — it only takes longer to get there. The
thing an operator is actually worried about is the disk, and the instruments for that are a
ceiling on kept history and a ceiling on file size. Central still rations messages per day,
because central is a funnel and rationing *is* its product; a self-hosted server is a home.

| Limit | Column | Channel override | DM override | Off by default |
|---|---|---|---|---|
| Per-file attachment size | `servers.max_attachment_bytes` | — | — | no; 25 MB, the ceiling the bucket already had |
| Delete messages older than N days | `servers.message_retention_days` | `channels.retention_days` | `servers.dm_retention_days` | yes |
| Keep at most N messages | `servers.message_history_cap` | `channels.history_cap` | `servers.dm_history_cap` | yes |

The overrides are three-valued: NULL inherits the server's number, a value sets its own, and 0
explicitly opts *out* of a server-wide sweep. NULL and 0 are different answers and the UI keeps
them apart. Voice channels carry the columns and ignore them — they hold no messages, so their
settings dialog shows the name alone rather than a switch wired to nothing.

#### DMs get the same override [Migration 009]

007 gave channels an override and left DMs with only the server-wide numbers, which made the
obvious policy — trim the busy channels, keep the DMs — inexpressible. 009 adds
`dm_retention_days` and `dm_history_cap`, read through the same COALESCE, and reached by
right-clicking **Server DMs** in the sidebar (admins only, like the channel menu).

They live on `servers` rather than on a conversation, and that is a decision rather than a
convenience. **A per-conversation setting has no owner.** A DM belongs to two people, so
neither end is the right person to decide how long the other's messages survive — and the
policy exists to protect the operator's disk, which makes it the operator's call. Nullable
where the two server-wide columns are `NOT NULL DEFAULT 0`, because these override rather than
set the base case, exactly like the channel-level pair.

The cap counts a conversation, not a sender: both people's messages together, one bucket seen
from either side.

#### A bucket per server [Migration 008]

Attachments used to land in one project-wide `chat-attachments` bucket, and since
one Supabase project can host several servers (001 says so, and identity is derived per
`(host, server_id)` precisely to allow it), that cost two things. `file_size_limit` is a
property of a *bucket*, so a shared one can carry only one number — 007 mirrored the MAX
across servers and accepted that a stricter server's cap was client-enforced only. And
`chat_attachments_select` was `bucket_id = 'chat-attachments'` for **any** authenticated
caller, so a member of one server could read another's objects. Ciphertext, so nothing
leaked, but every other rule in the schema is scoped by `app.server_id()` and that one
wasn't.

Each server now owns `chat-<server uuid>` (41 characters against Storage's 100-character
limit), and both problems become the same equality: `bucket_id = 'chat-' || app.server_id()`.

The mechanism is smaller than the endpoint it replaced. `storage.buckets` is protected only
against DELETE, so plain SQL can create a bucket and change its limit — which means triggers
on `servers` do all of it: one mints the bucket on INSERT, another moves `file_size_limit`
whenever `max_attachment_bytes` changes, *in the same statement*, so it cannot be skipped or
raced. `update_server` no longer touches storage at all, and `create_server` needs no extra
step and cannot half-succeed.

The old shared bucket still exists — Storage refuses a SQL DELETE on a bucket — but has no
policy, so nothing can read or write it. Anything left inside is unreachable and also
undecryptable; `orphaned_attachments` spans every `chat-%` bucket, so it drains rather than
lingering.

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
- **Join**: an existing member's client wraps the key for the newcomer. `get_channel_key` returns
  **every version sealed to you**, so scrollback reaches back as far as your oldest entry.
- **What that means in practice**: healing only ever seals the **current** version —
  `members_missing` is computed at `current_version` and clients wrap that one. So a newcomer reads
  everything in a channel that has never rotated, and nothing from before the last rotation in one
  that has. "Full scrollback" is the common case, not a guarantee, and the difference is what makes
  a private channel safe to open up (below).
- **Kick/ban**: rotate to a new channel key version for subsequent messages.
- **Seed-loss recovery**: re-invite + re-wrap restores history access without touching messages.

### Roles and permissions [Implemented August 2026]
- 22 named permission bits (`app.perm('BAN_MEMBERS')`), a `roles` table carrying a bitfield, and
  `member_roles`. `@everyone` is implicit — folded into `app.permissions()` rather than assigned —
  so there is only ever one answer to "what can everybody do".
- `users.is_server_admin`, `is_channel_manager` and `can_create_tokens` still exist and are still
  what every policy reads. Nothing writes them: a trigger keeps them equal to three bits. That is
  what let roles land without touching a single caller.
- **Delegation is two rules, not one.** *Position*: you may only touch a role ranked below your
  own, administrators included, or `MANAGE_ROLES` is `ADMINISTRATOR` with extra steps. *Subset*: a
  role may only carry permissions its author holds. Handing out a role is exempt from position for
  an administrator, or the only admin on a server could never make a second.
- **A client reads its own bits from `my_permissions()`** (021) and names them in
  `ServerPermission` with the same numbers the migration assigns. Drawing a button somebody may not
  press is cosmetic — the policy still decides. Drawing *no* button for something they may press is
  the failure that looks like the feature was never built, which is how the "+" for creating a
  private channel stayed hidden from everyone it was for.
- **An invite names a role** (025), not three flags. `roles.is_default` is the one a *person* gets
  for simply joining; `@everyone` cannot be it, because that one applies to bots too and 014
  decided a bot holds only what its invite named. `set_user_permissions`, `roles.legacy_key` and
  the three columns on `invites` are gone; the three on `users` remain as the trigger-kept cache
  every pre-018 policy reads.
- **Assigning a role and editing one are not the same rule.** Editing is strictly-below for
  everybody, administrators included — nobody rewrites the role they are standing on. Assigning
  exempts an administrator, or the only admin on a server could never make a second. Removing
  follows assigning, minus your own: an admin who could take their own Admin role off would lock
  the server out of ever having one again (026).

### Private channels [Implemented August 2026]
- **`VIEW_CHANNEL` is not like the other bits.** Every other permission is a rule the database
  applies to a request; this one is a key that was sealed to somebody. A rule can be changed and
  the next request obeys it. A sealed key can only be rotated past.
- So visibility resolves to **a list of people** (`channel_members`, plus `channel_role_access`
  read through to its holders) before anything is encrypted, and the keyring refuses a row for
  anyone outside it. Everything else about a channel — send, react, connect, speak — stays an
  ordinary rule.
- **No admin override, deliberately.** An admin holds no key either way, so a policy back door
  would be a promise the crypto cannot keep. An admin does not see a private channel, its messages,
  its keyring, or its membership.
- **Public → private** rotates, because the excluded are sealed into the current version. They keep
  what they already read; nobody can take that back.
- **Private → public** needs `channels.rotate_from_key_version`. Healing seals the *current*
  version, and the current version is the one the private conversation was written under — so the
  sweep must rotate past the mark before anyone new is sealed in. Both markers are self-clearing:
  they are compared against the version that passing them produces.
- **Revocation is a rotation, and a rotation needs somebody online.** In practice the person doing
  the removing is a member holding the current key, so it happens there and then. The exception is
  an admin banning somebody from a private channel the admin is not in: no key, so it waits for a
  member's client to sweep.
- Four things ask "who may read this" from outside the database — the key sweep,
  `get_channel_key`, `voice_roster` and `get_channel_token` — and all four run as the service role,
  with RLS off. They read `channel_eligible_members`, which is the same answer the policies give.
- A private channel tidies itself, since nobody else can see it to do so: the manage bit moves to
  whoever has been there longest, and the last person out takes the room with them.

### Three things a client can do with a row [Implemented August 2026]

Reading a message has three outcomes, and for a long time two of them shared a line.

| Outcome | When | What the reader sees |
|---|---|---|
| **Opened** | decrypted and verified, or never sealed (a webhook, `key_version 0`) | the message |
| **Locked** | sealed under a key version this device does not hold | a placeholder row: author, time, and a lock |
| **Dropped** | the signature does not verify, or the sender's key is gone so it cannot be checked | nothing, ever, and no hint that anything was there |

The middle row used to be the last one. A member nobody had wrapped for yet had every message
dropped by the same `continue` that drops a forgery, so a busy channel came back empty — and the
UI, seeing no key, covered it with a full-screen *Waiting for channel access* that hid whatever
**could** be read. Once webhooks arrived that included messages needing no key at all.

**A missing key is not a failure.** It is the ordinary state of a new member for as long as it
takes another client to come online and wrap for them, and the message is real, its author is
real, and it opens by itself when the key lands. A bad signature is somebody forging a message,
and it must leave no trace at all — a placeholder there would let a forger prove a message
existed. Same line of code, opposite requirements.

So a channel with no key now renders what it has: locked rows in place, webhook messages readable
among them, and the composer replaced by a banner — sending needs the same key, so there is no
half-open state to offer. The full-screen wait survives for the one case where it is still the
honest answer: nothing came back at all, so there is no list to show and nothing to say but why.

The locked row carries the author and the timestamp, which are columns the server already keeps in
the clear (§6, *metadata is visible*). Showing them reveals nothing a member without the key could
not read off the table directly, and without them the row says nothing about whose history this is.

### A send that did not get out [Implemented September 2026]

All three chat surfaces show an optimistic row the moment you press enter, and until now a failure
took that row away: the bubble was removed, a toast said *Failed to send message*, and the sentence
went with it. On a bad connection that is the worst possible outcome — the message was fine, the
network was not, and the only copy of what you typed was the one just deleted.

A failed send now stays where it is, marked **Not sent**, with the text intact and a *Retry* beside
it. `Outbox` (`lib/logic/services/outbox.dart`) holds what a second attempt needs — the row itself,
plus the local attachment bytes, which are the one input the row does not carry.

**Two paths, decided by whether anything answered.** `ErrorCode.isRetryable` is the whole of it:
`server_unreachable` and `server_timeout` describe the *connection*, and only those keep the row.
Everything else — a quota, a policy, an unfriending, a permission denied — is the server having
considered the message and refused it, and those keep the old behaviour of removing the row and
saying why. A *Retry* on a message the server has already declined is a button that cannot work,
and worse, it tells the reader the message might still go.

**Nothing re-sends on its own**, which was a deliberate choice over the usual meaning of "outbox".
A queue that empties itself while nobody is looking can deliver a sentence hours after it stopped
being true. It is the same rule as §*presence* — the client does not assert what the server has not
confirmed, and it does not act on the reader's behalf without being asked.

Three details that are load-bearing:

- **The row survives leaving the conversation.** `Outbox.restoreInto` puts held rows back under a
  freshly fetched page, so a "Not sent" message is still there after a click elsewhere. Without it
  the feature would last exactly one navigation.
- **`sendFailed` is in `ChatMessage.groupKey`.** "Not sent" is drawn in the header, and only the
  first row of a group has one — so a failed message tucking under the message above it would be
  silent about the one thing it exists to report. Same reasoning as `isEncrypted` and `isEphemeral`.
- **A send can time out after the server stored it.** When that message arrives over realtime,
  `mergeIncoming` retires the row it belongs to and now reports which ids it retired, so the entry
  behind them is dropped too. Otherwise reopening the conversation would offer to send a message
  that is already in it.

This is **not** a local message store, and deliberately stops short of one. It holds only what has
*not* been sent, in memory, for as long as the app is open. Rift persists structure — the server
list, channels, window geometry — and no content: caching decrypted messages would put the one
thing the whole design protects into a plain file (`hydrated_bloc` is built with no cipher). If
offline reading is ever wanted, the shape is to store the **envelopes** rather than the plaintext,
which is a different feature with encryption-at-rest as a property rather than a chore.

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

### Notification levels, and the one thing that leaks [Implemented August 2026]

Unread is a fact; being interrupted is a choice. `notification_prefs` holds the
second one, in the same `(user_id, scope, scope_id)` shape as `read_state`:
**all**, **mentions**, or **none**, at three scopes — the **server**, one
**channel**, one **conversation**. Channels default to `mentions`, DMs to `all`,
and a server to no opinion at all — which the menu shows as `mentions`, because
that is what the rooms inside it are actually at. Picking `mentions` on a server
clears its row; picking `all` stores one, and really does turn every channel
with no level of its own up to every message.

It rides along with `unread_counts()` because every reader of one wants the
other, and asking a round trip apart is how a muted channel gets one
notification anyway.

The scopes are a fallback chain, not a fight: **the conversation's own level if
it has one, else the server's if it has one, else the default.** Muting a server
therefore quiets everything you have not spoken about individually, while a
channel you deliberately set to `all` stays loud inside it. Discord resolves
this the other way — a server mute wins over the channels inside it — and then
needs overrides to climb back out. One ordering has to be picked; this is the
one you can predict from the menu in front of you, since a channel showing an
explicit level is telling you it is in force. `app.notify_level` holds the only
copy on the server and `NotificationLevel.resolve` the only copy on the client.

One setting, four readers that must agree: the ring trigger on the server, the
desktop app's OS notifications, the badge it draws, and the background isolate a
push wakes. They agree by all spelling it the same way — `NotificationLevel` in
Dart, `notify_level` in both schemas.

The hard part is that **the server cannot read a message**, so it cannot tell
whether one names you — which is the whole question `mentions` asks. Three ways
out were on the table:

- ring for every message and let the phone decide after decrypting. Private and
  instant, but a 20-member channel at 200 messages a day is ~190 pointless wakes
  per device per day.
- ring on a cooldown and let the phone decide. Private and cheap, but an
  @mention can arrive minutes late, which is the one notification nobody will
  accept being late.
- have the sender's client say who it named.

Rift takes the third. `messages.mentions` is a plaintext `uuid[]` and
`messages.mentions_all` is the `@all` flag. **The operator learns who was
addressed in a message; never what was said** — the same class of metadata this
schema already keeps in the open for `dm_messages.recipient_id` and for
reactions, and it is listed under *Accepted limitations* below with them.

Two things keep it honest. The column is **validated, not trusted**: ids that
aren't live members of the channel's server are dropped, the sender is dropped,
and the array is capped at 50, so a modified client can cause a wake but not a
hundred. And **the phone decrypts before it says anything** — the notification's
wording comes from the plaintext or from nothing, so a client that lies about
who it mentioned buys a silent wake and never a false "mentioned you". The one
place that cannot decrypt, the desktop app's subscription to a *background*
channel, therefore stays on its generic "new message in #general" rather than
claiming a mention on somebody else's say-so.

`@all` is a boolean rather than every member listed, because listing them is
exactly the abuse the cap exists to stop. Nobody may be called `all`
(`users_username_not_reserved`), so it is never ambiguous between the room and a
person.

Muting is not amnesia. A muted conversation still counts what arrived in it and
still shows it — what it loses is the loud pill and any claim on the totals that
add several conversations together. That is where Discord puts the difference
too, and it is the difference between "I don't want to be interrupted" and
"pretend this didn't happen".

### Decisions locked in for day one
1. **Every message is Ed25519-signed by the sender** — a shared channel key must not allow
   member/server forgery. Unsigned history can't be retro-signed, so this ships with message v1.
2. **Wrapping duty**: inviter's client pre-wraps at invite time; all clients sweep a
   pending-key-requests queue on launch (covers members added while everyone was offline).
3. **Rotation races**: unique `(channel_id, key_version)` server-side; first insert wins,
   losers re-wrap the winner's key.
4. Messages table carries an `encryption`/key-version column from the start.

### Accepted limitations (document honestly, do not "fix")
- **Metadata is visible** to the server admin and host: who, when, where, how much — and, since
  August 2026, **who a message named** (`messages.mentions`). E2E covers content only. See
  "Notification levels" above for why that column exists and what bounds it.
- **No forward secrecy — deliberate.** Static keys are what make "recover seed → recover history"
  possible; ratcheting would destroy that. This is a product choice, not an oversight.
- Search becomes a client-side index; automod is metadata-only; link previews are generated by
  the sender's client; mobile push is data-only + on-device decryption.

---

## 5. Voice, video & screenshare — [Implemented]

- Client asks its self-hosted server for a channel token (`get_channel_token`); the Edge Function
  mints a LiveKit JWT (room = channel id, identity = user id, 1 h TTL, `roomAdmin` for channel
  managers). Screenshare sessions use the same flow with an `_screenshare` identity suffix.
- **Media is end-to-end encrypted** (migrations 031–032). Frames are AES-GCM encrypted with the
  channel's **own key** — the same key the text keyring seals per member (§4) — so the SFU
  forwards packets it cannot open. DTLS-SRTP still protects the hop; this protects the room.
- This used to be the one place the server could read what members said to each other. The SFU sees
  frames by construction — that is how an SFU works — and the trade was written down as acceptable
  because the operator runs both. It is no longer taken: everything in Rift is now end-to-end
  encrypted, and voice was the exception.
- Verified between two real clients on Sep 2 2026 — one client's speech audible on the
  other, the SFU reporting the track as GCM throughout (`MANUAL_TESTING.md`). Worth saying
  because encryption that silently drops audio looks exactly like encryption that works.
- **A call cannot be joined without the key.** `_prepareE2EE` returning nothing fails the join
  rather than falling back, because an unencrypted call would connect, work, and sound completely
  normal. A room you cannot join gets reported; a room that is quietly readable does not.
- Key *version* maps onto LiveKit's fixed key ring as `version % 16`. Every client has to agree on
  that mapping — a sender encrypting into a slot its listeners do not read is a call where
  everybody connects and nobody hears anyone, with no error anywhere. It is frozen in WIRE.md §6.
- **A rotation reaches a call in progress.** Removing somebody rotates the channel key, and a client
  that stayed on the version it joined with would sit in a room where everybody is connected and
  nobody is audible. Each client holds the key-sweep doorbell for the length of a call, re-registers
  every participant's key at the new slot, and moves its frame cryptors onto it. The old key is left
  in its slot: the ring holds sixteen, and frames already in flight were sealed under the old one.
- The room runs in LiveKit's **per-participant** key mode rather than its shared-key mode, and only
  because of bots — see below and BOTS.md §6b. Members all use the channel key.
- Rotation is the text rules unchanged: `sweep_channel_keys` covers voice channels too, so a banned
  member's key is rotated away from them. It used to filter to text channels, which was harmless
  while voice held no keys and a hole the moment it did.
- **Screen share carries the same key.** It is a second connection into the same room, published
  from Rust, and LiveKit skips the frame cryptor for a track that declares no encryption — so an
  unencrypted share would not fail, it would hand the server the one stream nobody meant it to
  have. The Rust path refuses to connect without the key, and sets the key *index* on its cryptors
  by hand: the Rust SDK never does, so it would otherwise encrypt into slot 0 while the room reads
  `version % 16`.
- Screenshare capture (video + per-platform system audio) runs in Rust for performance and
  publishes directly to the LiveKit room.
- **A bot is audible and deaf**, and it takes two mechanisms because encryption removed the easy
  one. Its token is minted `canSubscribe: false` and never `roomAdmin`. And it is given a *different
  key*: `HMAC-SHA256(channelKey, "voicebot:v1:<botId>")`, sealed to it by a member. Members hold the
  channel key so they derive it and hear the bot; the bot cannot invert HMAC, so it cannot reach the
  channel key and cannot decrypt one member's audio.
  
  With a single room key this is not expressible — encrypting is what makes a bot audible, and the
  key that encrypts also decrypts (BOTS.md §2). Two keys and a one-way function are what buy it, and
  they are the whole reason the room runs in per-participant key mode.

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
