# Rift Architecture — Identity, Auth & Encryption

Reference for how authentication and encryption work across the system. Each section is marked
**[Implemented]** or **[Planned]**. Update this file when the design changes.

## Components

| Component | Role |
|---|---|
| Flutter app | UI on all platforms; all cryptography runs client-side (`CryptoRepository`) |
| Rust core (`rust/`) | Screen capture + audio pipeline, publishes to LiveKit via flutter_rust_bridge |
| Self-hosted server | One Supabase project (Postgres + Edge Functions) + one LiveKit server. Anyone can run one; holds users, channels, tokens — and later, messages |
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
   ├─ HMAC-SHA256(seed, "<host>:<version>") ──► child seed ──► Ed25519 keypair (per server)
   ├─ HMAC-SHA256(seed, "<host>:identity")  ──► stable_id (permanent, survives key rotation)
   └─ HMAC-SHA256(seed, "vault:v1")         ──► vault blob key (AES-256-GCM)
```

- `<host>` is the hostname of the self-hosted server's Supabase URL, so identities are
  **per-server**: servers cannot correlate a user across servers by key material.
- `<version>` (`v1`, `v2`, …) supports key rotation: bumping it yields a fresh keypair from the
  same seed; `stable_id` is version-independent and never changes.
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

Session tokens are **intentionally excluded** — they're 1-hour credentials re-minted on import via
challenge-response. Restore = enter password → decrypt seed → derive everything → re-authenticate
everywhere. Storage providers only ever see ciphertext.

---

## 2. Self-hosted server auth — [Implemented]

Public-key challenge-response; no passwords ever reach self-hosted servers.

1. **Register** (once, invite code required): client sends `public_key` + `stable_id` + username.
2. **Login**: client requests a challenge → server upserts a 60-second nonce for that public key
   (`auth_challenges`, one active per key) → client signs `"<nonce>@<host>"` with Ed25519 →
   server verifies and issues a session token (1 h TTL, `tokens` table).
   Binding `<host>` into the signature prevents a malicious server replaying the login elsewhere.
3. **Key rotation**: client signs `"rotate:<newPubKeyB64>@<nonce>@<host>"` with the **old** key;
   server swaps `public_key`, `stable_id` unchanged. Client bumps `<version>` in the vault.
4. **Session refresh**: all API calls flow through `ServerCubit._callWithAutoRefresh` — expired
   tokens trigger a silent re-login and one retry.

**Permissions** are three token/user flags — `is_server_admin`, `is_channel_manager`,
`can_create_tokens` — with the delegation rule: *you can only grant what you hold*.

**Known limitation (to fix):** `tokens.user_id` is UNIQUE — one live session per user per server.
Two devices logged in simultaneously invalidate each other's tokens in a refresh ping-pong.
Fix: drop the constraint so each device holds its own token row. LiveKit identity collision
(two devices in the same voice channel) is a separate, deferred issue.

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

## 4. Chat encryption — [Planned — chat is not built yet]

All messages E2E encrypted. Encryption keys are X25519, derived from the master seed exactly like
the Ed25519 identities (per-host, versioned) — **the backup format needs no changes**.

### DMs — "Design 1": encrypt to identity
Diffie-Hellman between sender private key and recipient public key → shared secret → AES-GCM.
Only the two identities can ever decrypt. Seed recovery restores full history; true seed loss
makes history permanently unreadable (accepted).

### Group channels — "Design 2": wrapped channel key
- Each channel has a random symmetric **channel key**; every message encrypted once with it.
- The server stores a **keyring**: the channel key encrypted separately for each member's public
  key. The server can't read any entry.
- **Join**: an existing member's client wraps the key for the newcomer → full history readable
  (decision: wrap **all** historical key versions — full scrollback, Discord expectation).
- **Kick/ban**: rotate to a new channel key version for subsequent messages.
- **Seed-loss recovery**: re-invite + re-wrap restores history access without touching messages.

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
