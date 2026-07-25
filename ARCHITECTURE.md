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
4. **Authorization**: Edge Functions verify the JWT locally against the stack's JWKS (ES256, no
   GoTrue round-trip — `_shared/jwt.ts`) and load the `users` row for permissions + ban state on
   every call (ban / deleted-user is enforced instantly on the edge path). Simple per-user surfaces
   (the `notifications` table) are read directly via RLS `auth.uid() = user_id`.

**Permissions** are three user flags — `is_server_admin`, `is_channel_manager`,
`can_create_tokens` — with the delegation rule: *you can only grant what you hold*.

**Multiple servers per project:** identity is derived per `(host, server_id)` —
`childSeed = HMAC(seed, "<host>:<serverId>:<version>")` — so two servers sharing one Supabase
project yield **distinct** SIWS identities (distinct `auth.uid()`), and the same person can join
both. Username uniqueness is per-server (migration 010); `public_key` / `stable_id` already were.
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
| Limits        | per-sender daily quota; 30-day TTL; per-conversation history cap (oldest trimmed first) | none imposed by Rift — operator's hardware, operator's call |
| Media         | allowed; counts against quota, per-file size cap | allowed (operator's storage)         |

- Central limits are enforced **server-side** (the send path checks a daily counter; a
  scheduled job sweeps expired and over-cap rows) — a modified client can't bypass them.
  Default knobs (tunable constants): ~100 messages/day per sender, 30-day TTL, ~500 messages
  per conversation.
- Deletion is server-side: past the TTL/cap the ciphertext is gone from central; clients
  render what the server still has.
- The UI surfaces the remaining daily quota as it tightens and nudges long conversations
  toward a shared server ("Continue on <server>" when one exists).
- Privacy-mode users (no central account) simply have no central DMs; server DMs still work.

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

**Emoji reactions are deliberately NOT E2E.** Unlike message content, an emoji
tally is stored in the clear (`message_reactions` / `dm_message_reactions`, or
`dm_reactions` on central) — the server sees who reacted with which emoji. This
is the accepted metadata cost of a Discord-like reaction UX; message *content*
stays encrypted. Toggling is one call (add if absent, else remove); clients
fetch aggregated counts via `list_reactions` and refresh live off the same
Realtime doorbell used for messages (self-hosted) or on the next fetch (central).

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

---

## 6. Threat model summary

| Adversary | Identity/seed | Backups | Group chat | DMs | Voice |
|---|---|---|---|---|---|
| Network observer | safe | safe | safe (TLS) | safe | safe (SRTP) |
| Central server / its host | safe (E2E) | safe (E2E) | n/a | n/a | n/a |
| Self-hosted server's hosting provider | safe | n/a | safe once E2E chat ships | safe | SFU-accessible |
| Self-hosted server admin | safe | n/a | readable (they're a member anyway) | **safe** | accessible |
| Device thief (no password) | Argon2id + secure storage | — | — | — | — |
