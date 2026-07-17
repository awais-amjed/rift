# Rift Edge Functions API

Reference for the Supabase Edge Functions that power a self-hosted Rift server.
Source lives in [`edge_functions/supabase/functions/`](edge_functions/supabase/functions/) —
one directory per function plus `_shared/` helpers. The Flutter client's mirror of this API is
`lib/data/repositories/server_repository.dart`; keep the two in sync.

## Base URL

```
<supabase-url>/functions/v1/<function_name>
```

All requests are `POST` with a JSON body. Session-protected endpoints take the Rift session
token (an opaque 64-char hex string, **not** a JWT) as `Authorization: Bearer <token>`.

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

- **Invites, not passwords.** New users register with an invite code plus their Ed25519 public
  key and stable ID (both derived client-side from the master seed — see ARCHITECTURE.md §1–2).
- **Challenge-response login.** `get_challenge` issues a 60-second nonce; the client signs
  `"<nonce>@<host>"` and calls `verify_challenge`, which returns a fresh 1-hour session token.
- **Per-device sessions.** Every successful `verify_challenge` inserts its own token row
  (migration 003), so multiple devices hold independent sessions. Expired tokens, challenges,
  and invites are cleaned up by pg_cron jobs.
- **Permissions** live on the user row: `is_server_admin`, `is_channel_manager`,
  `can_create_tokens`. Delegation rule: an invite can only grant permissions its creator holds.

### Shared "server context" payload

`register`, `verify_challenge`, and `get_server_details` all return the same shape
(built by `_shared/server_context.ts`):

```jsonc
{
  "token": "…",              // session token (register / verify_challenge only)
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
| 2 | `register` | invite code | `invite_code`, `public_key` (b64, 32 B), `stable_id` (b64, 32 B), `username`, `display_name` | server context + `token`. Atomic: user + first token created in one transaction (`create_user_with_token` RPC); invite claimed atomically (`claim_invite` RPC) |
| 3 | `get_challenge` | none (key must belong to a registered, non-banned user) | `public_key`, `server_id` | `nonce` (60 s TTL, one active per key — upsert replaces) |
| 4 | `verify_challenge` | signature | `public_key`, `nonce`, `signature` (b64 over `"<nonce>@<host>"`), `host`, `server_id` | server context + fresh `token` (1 h). Nonce is burned before verification |
| 5 | `rotate_key` | signature by **old** key | `old_public_key`, `new_public_key`, `nonce`, `signature` (b64 over `"rotate:<newPubKeyB64>@<nonce>@<host>"`), `host`, `server_id` | success only. Replaces the user's key, deletes **all** their session tokens (old key may be compromised) |
| 6 | `is_username_available` | none | `username` | `username`, `available` |
| 7 | `create_invite` | Bearer + `can_create_tokens` | `is_server_admin?`, `is_channel_manager?`, `can_create_tokens?`, `max_uses?` (null = unlimited, default 1), `expires_in_seconds?` (null = never) | `invite_code`. Can only grant permissions the caller holds |
| 8 | `get_server_details` | Bearer | — | server context (no `token` refresh) |
| 9 | `update_server` | Bearer + `is_server_admin` | any of `name`, `icon_url`, `livekit_api_key`, `livekit_secret_key` | updated fields |
| 10 | `create_channel` | Bearer + `is_channel_manager` | `name` (unique per server), `channel_type` (`voice` \| `text`) | channel row |
| 11 | `delete_channel` | Bearer + `is_channel_manager` | `channel_id` (must belong to token's server) | confirmation |
| 12 | `get_channel_token` | Bearer | `channel_id`, `screen_share?` | `token`: LiveKit JWT (room = channel id, identity = user id, `_screenshare` suffix when screen sharing, `roomAdmin` for channel managers, 1 h TTL). The function pre-creates the LiveKit room server-side; client grants never include `roomCreate`. **Moderation is enforced here**: muted users get no `microphone` in `canPublishSources`, deafened users get `canSubscribe: false`, and the flags ride along as participant metadata |
| 13 | `moderate_user` | Bearer + (`is_channel_manager` or `is_server_admin`) | `user_id`, `is_muted?`, `is_deafened?` (at least one) | `user_id`, `is_muted`, `is_deafened`, `applied_live`. Persists the flags on the users row and, if the target is currently in a voice channel, live-applies via LiveKit `updateParticipant` (permissions revoked + metadata broadcast). Server admins cannot be moderated |

## Database schema

Defined by `self_hosted_server_migrations/` (run in order on a fresh instance):

1. **001_initial_schema.sql** — tables `servers`, `users`, `channels`, `tokens`, `invites`,
   `auth_challenges`; RLS enabled with no policies (all access via service_role in functions);
   pg_cron cleanup jobs; `claim_invite` + `create_user_with_token` RPCs (service_role-only);
   public `servers` storage bucket for icons.
2. **002_per_server_identity_uniqueness.sql** — `public_key` / `stable_id` unique per
   `(server_id, …)` instead of globally.
3. **003_per_device_tokens.sql** — drops `tokens.user_id` UNIQUE so each device holds its own
   session token.
4. **004_moderation_flags.sql** — `users.is_muted` / `users.is_deafened`, the persistent
   source of truth for server-side moderation.

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
cp -r edge_functions/supabase/functions/{_shared,create_server,register,get_challenge,verify_challenge,rotate_key,is_username_available,create_invite,get_server_details,update_server,create_channel,delete_channel,get_channel_token,moderate_user} \
      <stack>/volumes/functions/
docker restart supabase-edge-functions
```

Apply migrations with `docker exec -i supabase-db psql -U postgres -v ON_ERROR_STOP=1 -f - < <file>`.

Requirements for the stack's `.env`: `FUNCTIONS_VERIFY_JWT=false` (Rift session tokens are not
JWTs, and `register`/`get_challenge` are called with no Authorization header at all).

### LiveKit

The functions read LiveKit credentials from the `servers` row, so the `livekit_url` stored at
`create_server` time must be reachable **from the functions container as well as from clients**
— use a LAN IP (e.g. `ws://192.168.1.6:7880`), never `localhost`. When running
`livekit-server --dev` locally, start it with `--bind 0.0.0.0`.
