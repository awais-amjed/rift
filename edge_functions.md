# Rift Edge Functions API

Reference for the Supabase Edge Functions that power a self-hosted Rift server.
Source lives in [`edge_functions/supabase/functions/`](edge_functions/supabase/functions/) —
one directory per function plus `_shared/` helpers. The Flutter client's mirror of this API is
`lib/data/repositories/server_repository.dart`; keep the two in sync.

## Base URL

```
<supabase-url>/functions/v1/<function_name>
```

All requests are `POST` with a JSON body. Session-protected endpoints take the GoTrue session
JWT (obtained from SIWS `login`) as `Authorization: Bearer <jwt>`.

## Response format

Every function returns HTTP 200 with a JSON envelope:

```jsonc
{ "success": true,  "data": { ... } }                                  // success
{ "success": false, "error": "Human message", "code": "machine_code" } // failure
```

`code` values are defined in `_shared/error_codes.ts` and mirrored in
`lib/data/enums/error_code.dart` — keep both lists identical. The client switches on `code`
(e.g. `token_invalid` / `token_expired` / `token_unlinked` trigger silent re-authentication).

## Auth model

- **Sign-in-with-Web3 (SIWS / Solana).** The client signs a Sign-in-with-Solana message with its
  per-host Ed25519 key and posts it to `login`, which proxies GoTrue's `grant_type=web3`
  server-side and returns a session (access JWT + refresh token). No passwords; the private key
  never leaves the device (see ARCHITECTURE.md §1–2 and `auth.md`).
- **Invites, not open signup.** After SIWS login, new users call `register` (JWT in the header)
  with an invite code + their Ed25519 public key and stable ID to create the profile row, bound to
  the GoTrue identity (`users.id = auth.uid()`).
- **JWT verification.** Session-protected functions verify the JWT (`auth.getUser`) and load the
  `users` row for permissions + ban state on every call — ban is enforced instantly on the edge
  path even though the JWT is stateless.
- **Permissions** live on the user row: `is_server_admin`, `is_channel_manager`,
  `can_create_tokens`. Discord-style management: invites are plain (everyone joins with
  baseline permissions — no admin/manager, but invite-creation allowed by default), and
  server admins promote/demote members afterwards via `set_user_permissions`. The only
  permission-carrying invite is the hidden bootstrap invite from `create_server`.

### Shared "server context" payload

`register` and `get_server_details` both return the same shape
(built by `_shared/server_context.ts`) — no session token, since the client already holds the JWT:

```jsonc
{
  "server_id": "uuid",
  "name": "…",
  "icon_url": "… | null",
  "livekit_url": "…",
  "supabase_key": "…",       // this instance's anon key
  "user": {
    "id": "uuid", "username": "…", "display_name": "…",
    "permissions": { "is_server_admin": false, "is_channel_manager": false, "can_create_tokens": false },
    "is_muted": false, "is_deafened": false
  },
  "channels": [ { "id": "uuid", "name": "…", "channel_type": "voice" | "text" } ]
}
```

## Functions

| # | Function | Auth | Input (body) | Returns (`data`) |
|---|---|---|---|---|
| 1 | `create_server` | `service_key` in body must equal the instance's service_role key | `name`, `livekit_url`, `livekit_api_key`, `livekit_secret_key`, `icon_url?` | `server_id`, `name`, `supabase_url`, `supabase_key`, `invite_code` (single-use admin invite: all three permissions) |
| 2 | `login` | none (self-authenticating via the signature) | `message` (SIWS text), `signature` (b64 Ed25519 over the message) | GoTrue session: `access_token` (JWT), `refresh_token`, `expires_at`, … Proxies `grant_type=web3` server-side so the client needs no anon key. `Chain ID: solana:mainnet` |
| 3 | `register` | Bearer (SIWS JWT) | `invite_code`, `public_key` (b64, 32 B), `stable_id` (b64, 32 B), `username`, `display_name` | server context (no token — the client already holds the JWT). Binds `users.id = auth.uid()`; invite claim + identity/username checks + profile insert run in one atomic `register_user` RPC, so a failed register never burns an invite use (migration 009) |
| 4 | `is_username_available` | none | `username` | `username`, `available` |
| 5 | `create_invite` | Bearer + `can_create_tokens` | `max_uses?` (null = unlimited, default 1), `expires_in_seconds?` (null = never) | `invite_code` (short base58, ~10 chars, retried on the `code` UNIQUE constraint). Plain invite — carries no permissions. The client shares it as a combined link `<server-url>#<invite_code>` |
| 6 | `get_server_details` | Bearer | — | server context (no token) |
| 7 | `update_server` | Bearer + `is_server_admin` | any of `name`, `icon_url`, `livekit_url`, `livekit_api_key`, `livekit_secret_key` | `name`, `icon_url`, `livekit_url` (key/secret are write-only, never returned) |
| 8 | `create_channel` | Bearer + `is_channel_manager` | `name` (unique per server), `channel_type` (`voice` \| `text`) | channel row |
| 9 | `delete_channel` | Bearer + `is_channel_manager` | `channel_id` (must belong to the caller's server) | confirmation |
| 10 | `get_channel_token` | Bearer | `channel_id`, `screen_share?`, `device_id?` | `token`: LiveKit JWT + `identity`. Identity = `<userId>~<deviceId>` (client-supplied `device_id`, sanitised; userId prefix is always server-set so it can't be spoofed), with a `_screenshare` suffix when screen sharing. The device segment lets one user join from multiple devices without a LiveKit identity collision kicking the earlier connection. `roomAdmin` for channel managers, 1 h TTL. The function pre-creates the LiveKit room server-side; client grants never include `roomCreate`. **Moderation is enforced here**: muted users get no `microphone` in `canPublishSources`, deafened users get `canSubscribe: false`, and the flags ride along as participant metadata |
| 11 | `moderate_user` | Bearer + (`is_channel_manager` or `is_server_admin`) | `user_id`, `is_muted?`, `is_deafened?` (at least one) | `user_id`, `is_muted`, `is_deafened`, `applied_live`. Persists the flags on the users row and, if the target is currently in a voice channel, live-applies via LiveKit `updateParticipant` (permissions revoked + metadata broadcast). Server admins cannot be moderated |
| 12 | `list_users` | Bearer (any member) | — | `users`: array of `{id, username, display_name, created_at, permissions{…}, is_muted, is_deafened, is_banned, chat_public_key}` |
| 13 | `set_user_permissions` | Bearer + `is_server_admin` | `user_id`, `is_server_admin?`, `is_channel_manager?`, `can_create_tokens?` (at least one) | `user_id`, `permissions{…}`. Callers cannot edit their own permissions (last-admin lockout guard) |
| 14 | `publish_chat_key` | Bearer | `chat_public_key` (b64, 32 B X25519) | `chat_public_key`, `newly_published`. Idempotent upsert of the caller's chat identity (deterministic per seed+host); called after login. `newly_published` tells the client to ring the key-sweep doorbell |
| 15 | `send_message` | Bearer | `channel_id`, `ciphertext` (b64, ≤16384 chars), `nonce` (b64), `signature` (b64 Ed25519 over `"chatmsg:v1:<channel_id>:<key_version>:<nonce>:<ciphertext>"`), `key_version` | `id` (bigserial), `created_at`, `channel_id`, `sender_id`. Server stores the E2E envelope opaquely and attests sender + timestamp. Fans out one `notifications` row per other member. Clients broadcast a Realtime ping (`chat:<channel_id>`) after success; the row is the source of truth |
| 16 | `list_messages` | Bearer | `channel_id`, `before_id?` (history, newest-first) \| `after_id?` (catch-up, oldest-first), `limit?` (default 50, max 100) | `messages`: array of envelope rows + `sender_name`, `sender_public_key` (server-attested, for signature verification), and `has_more` |
| 17 | `get_channel_key` | Bearer | `channel_id` | `current_version` (0 = bootstrap needed), `my_keys` (caller's sealed entries, all versions), `members_missing` (`{user_id, chat_public_key}` of keyed members lacking a current-version entry — any client may heal them) |
| 18 | `post_channel_keys` | Bearer | `channel_id`, `key_version` (≤ current+1), `entries`: `[{user_id, ephemeral_public_key, ciphertext, nonce}]` | `entries_stored`. One INSERT, no ON CONFLICT: on 23505 returns `keyring_conflict` — first writer wins, losers refetch and re-wrap |
| 19 | `sweep_channel_keys` | Bearer | — | `work`: per text channel the caller can help — `key_version: 0` + all keyed members (bootstrap), or the current version + caller's sealed `my_key` + `members_missing` (healing). Clients run it on launch/server-select and on the `keysweep:<server_id>` Broadcast doorbell |
| 20 | `send_dm` | Bearer | `recipient_id`, envelope (`ciphertext`, `nonce`, `signature`, `key_version`) | `id`, `created_at`. Design-1 DM envelope; recipient must be a keyed, non-banned member. Signature context is `"dm:<lowerUserId>:<higherUserId>"`. Sender rings the recipient's `dm:<server_id>:<user_id>` Broadcast topic after the ack |
| 21 | `list_dms` | Bearer | `peer_id`, `before_id?` \| `after_id?`, `limit?` | `messages` (both directions of the pair, sender name + Ed25519 key attested), `has_more` |
| 22 | `list_dm_conversations` | Bearer | — | `conversations`: one per peer — peer identity material (display name, Ed25519 + X25519 keys) and the latest envelope for the client-decrypted preview |
| 23 | `resolve_invite` | none | `invite_code` | `server_id`, `server_name`. Maps an invite to its server **without consuming it**, so the client can derive its per-`(host, server_id)` SIWS identity before login/register (needed when several servers share one project). Registration still validates + atomically claims the invite |

## Database schema

Defined by `self_hosted_server_migrations/` (run in order on a fresh instance):

1. **001_initial_schema.sql** — tables `servers`, `users`, `channels`, `tokens`, `invites`,
   `auth_challenges`; RLS enabled with no policies (all access via service_role in functions);
   pg_cron cleanup jobs; `claim_invite` + `create_user_with_token` RPCs (service_role-only);
   public `servers` storage bucket for icons. *(The token/challenge tables it creates are dropped
   by 007; `create_user_with_token` is dropped by 009.)*
2. **002_per_server_identity_uniqueness.sql** — `public_key` / `stable_id` unique per
   `(server_id, …)` instead of globally.
3. **003_per_device_tokens.sql** — drops `tokens.user_id` UNIQUE (historical — the `tokens`
   table itself is removed by 007).
4. **004_moderation_flags.sql** — `users.is_muted` / `users.is_deafened`, the persistent
   source of truth for server-side moderation.
5. **005_chat_messages.sql** — E2E chat: `messages` (opaque envelopes), `channel_keyring`
   (sealed channel keys, unique `(channel_id, key_version, user_id)`),
   `users.chat_public_key` (X25519, published by clients).
6. **006_dm_messages.sql** — E2E server DMs: `dm_messages` (opaque pair envelopes, no
   keyring — Design-1 pairwise DH; pair + per-side indexes).
7. **007_jwt_siws_auth.sql** — SIWS/JWT auth: drops `tokens` + `auth_challenges`; binds
   `users.id → auth.users(id)` (so `users.id = auth.uid()`); adds the `notifications` table
   (RLS `auth.uid() = user_id`, added to the `supabase_realtime` publication for authenticated
   Postgres-Changes delivery). Assumed one server per Supabase instance — lifted by 010.
8. **008_notifications_retention.sql** — bounds `notifications` growth: hourly
   `cleanup-notifications` pg_cron job prunes rows read >1 day ago or older than 7 days,
   plus `idx_notifications_created_at`.
9. **009_register_atomic.sql** — folds invite-claim + identity/username checks + profile
   insert into one transactional `register_user` RPC (invite consumed only on success, so a
   failed register never burns a use); drops the orphaned `create_user_with_token`.
10. **010_multi_server_per_project.sql** — allows multiple servers per Supabase project:
    username uniqueness → per-server (`(server_id, username)`), and `register_user`'s username
    check scoped to the server. Pairs with the client deriving identity per `(host, server_id)`
    and the new `resolve_invite` function.
11. **011_attachments_storage.sql** — creates the private `chat-attachments` storage bucket
    (25 MB cap) with authenticated insert/select RLS, for E2E-encrypted attachment blobs. No
    edge-function change: attachments ride *inside* the existing message envelope (structured
    `MessageBody`), and blobs move over the Storage REST API. The central project needs an
    equivalent `central-dm-attachments` bucket (10 MB, own-folder insert) — see LOCAL_DEV.
12. **012_reactions.sql** — `message_reactions` + `dm_message_reactions` tables (NOT E2E —
    server-visible emoji tallies). Served by two new functions: **`toggle_reaction`**
    (`{scope: "channel"|"dm", channel_id?/peer_id?, message_id, emoji}` — flips the caller's
    reaction, returns `{reacted}`) and **`list_reactions`** (`{scope, …, message_ids[]}` →
    `{reactions: {id: [{emoji,count,mine}]}}`, membership-filtered). The central project uses a
    `dm_reactions` table with participant-scoped RLS instead (direct client ops) — see LOCAL_DEV.
13. **013_message_edit_delete.sql** — adds `edited_at` to `messages` and `dm_messages`, served
    by four new functions: **`edit_message`** / **`edit_dm`** (`{message_id, …envelope}` —
    overwrites the envelope in place and stamps `edited_at`; **sender only**, so a moderator can
    remove a message but never rewrite it under its author's name) and **`delete_message`** /
    **`delete_dm`** (`{message_id}`). Deletion is a **hard** delete: in an E2E app "deleted" must
    mean the ciphertext is gone, not hidden behind a flag; reactions cascade with the row.
    `delete_message` also allows a channel manager / server admin. Authorship is enforced by
    scoping the write itself (`.eq(sender_id, …)`), so there is no read-then-write gap, and the
    "not found" and "not yours" cases deliberately return the same error rather than leaking
    which. The central project needs `edited_at` plus own-row update/delete RLS — see LOCAL_DEV.
14. **014_profiles_avatars.sql** — adds `users.avatar_path` and a **private** `avatars` bucket
    (2 MB), served by **`update_profile`** (`{display_name?, avatar_path?}`). Self only: there is
    no target parameter, so it can't be aimed at another member even by an admin — renaming
    someone else is a moderation action and doesn't belong on the endpoint people call to set
    their own name. `display_name` is per-server (each server is its own identity).
    `avatar_path` must start with the caller's own user id, so a row can't be pointed at someone
    else's object; passing it as explicit `null` clears the picture. **Avatars are NOT E2E** —
    the image is stored in the clear, the same accepted trade-off as reactions, because a picture
    every member renders gains nothing from per-member wrapping. The bucket is private rather
    than public-read so avatars aren't fetchable by the unauthenticated internet.
    `list_users`, `list_messages` and `list_dms` now return `avatar_path` / `sender_avatar_path`.

## Deployment

### Hosted Supabase project

```bash
cd edge_functions
supabase functions deploy --project-ref <ref>
```

Apply the migrations via the SQL editor or `psql` in order.

### Self-hosted Docker stack

The docker-compose stack serves functions from its `volumes/functions/` directory via the
`main` router (path `/functions/v1/<name>` → `/home/deno/functions/<name>`):

```bash
cp -rf edge_functions/supabase/functions/. <stack>/volumes/functions/
docker restart supabase-edge-functions
```

Apply migrations with `docker exec -i supabase-db psql -U postgres -v ON_ERROR_STOP=1 -f - < <file>`.

Requirements for the stack's GoTrue config: enable the SIWS grant with
`GOTRUE_EXTERNAL_WEB3_SOLANA_ENABLED=true` (dev keeps signup on so SIWS auto-creates the
`auth.users` row; production sets `GOTRUE_DISABLE_SIGNUP=true` and provisions via `register`).
Keep `FUNCTIONS_VERIFY_JWT=false` — `login` and `register` are invoked without the runtime's own
JWT gate (each function self-validates: `login` by the signature, everything else via
`auth.getUser`).

### LiveKit

The functions read LiveKit credentials from the `servers` row, so the `livekit_url` stored at
`create_server` time must be reachable **from the functions container as well as from clients**
— use a LAN IP (e.g. `ws://192.168.1.6:7880`), never `localhost`. When running
`livekit-server --dev` locally, start it with `--bind 0.0.0.0`.
