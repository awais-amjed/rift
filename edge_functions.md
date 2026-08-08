# Rift server API

How a client talks to a self-hosted Rift server. There are two transports, and which one a call
uses is a deliberate line rather than an accident of history:

- **Direct PostgREST**, under the policies in `self_hosted_server_migrations/002_security.sql`.
  This is almost everything: reading and sending messages, editing your own, member lists,
  channels, invites, reactions, read cursors.
- **Edge functions**, in [`edge_functions/supabase/functions/`](edge_functions/supabase/functions/),
  for the nine things that genuinely can't be a table call.

The client mirror is `lib/data/repositories/server_repository.dart` (+ `server_db.dart`); keep
them in sync.

> **This used to be 29 functions.** Every read and write went through one, because clients
> weren't trusted with the database — which was never a decision, just the consequence of tables
> that had no policies on them. Two of them (`messages`, `dm_messages`) turned out to have no RLS
> at all, so the anon key that every member holds could read *and delete* every message on a
> server. Fixing that properly meant writing the policies; once written, most of the endpoints
> had nothing left to do.

## What stayed an edge function, and why

An endpoint earns its place only if it holds a secret, or runs before the caller is a member.

| Function | Auth | Why it can't be a table call |
|---|---|---|
| `login` | none (self-authenticating via the signature) | Proxies GoTrue's `grant_type=web3` with the service key, so the client needs no anon key. Returns the session (`access_token`, `refresh_token`, …). `Chain ID: solana:mainnet` |
| `register` | Bearer (SIWS JWT) | Claims an invite and creates the profile row **before** the caller is a member of anything. One atomic `register_user` RPC, so a failed register never burns an invite use |
| `resolve_invite` | none | Runs before the client has the server's anon key — it is what hands the key out. Maps an invite to `server_id` + `server_name` **without consuming it**, so the per-`(host, server_id)` SIWS identity can be derived before login |
| `is_username_available` | none | Same bootstrap window: asked while registering, before membership |
| `create_server` | `service_key` in body | Writes the LiveKit API secret. Returns `server_id`, `name`, `supabase_url`, `supabase_key`, `invite_code` (single-use admin invite) |
| `update_server` | Bearer + `is_server_admin` | Writes the LiveKit API key/secret into `server_secrets`, which has no grant and no policy. Name and icon ride along rather than splitting one dialog across two transports |
| `get_channel_token` | Bearer | Mints a LiveKit JWT with the API secret. Identity is `<userId>~<deviceId>`; `roomAdmin` for channel managers, 1 h TTL. **Moderation is enforced here** — muted users get no `microphone` in `canPublishSources`, deafened users get `canSubscribe: false` |
| `get_channel_key` | Bearer | Channel-key distribution (below) |
| `post_channel_keys` | Bearer | Channel-key distribution (below) |
| `sweep_channel_keys` | Bearer | Channel-key distribution (below) |

**The key-distribution trio is a deliberate deferral, not a rule.** `post_channel_keys` enforces
the `key_version ≤ current+1` race (first writer wins, losers refetch and re-wrap) and
`sweep_channel_keys` computes healing sets across channels. Both are expressible as RPCs, but
getting them wrong breaks decryption silently rather than loudly, so they were left on the
service role until they can be moved with care.

### Response format (edge functions only)

```jsonc
{ "success": true,  "data": { ... } }                                  // success
{ "success": false, "error": "Human message", "code": "machine_code" } // failure
```

`code` values live in `_shared/error_codes.ts`, mirrored in `lib/data/enums/error_code.dart`.
Direct calls return PostgREST errors instead; `ServerDb.run` maps them into the same
`APIResponse`, including turning a `PGRST301`/expired JWT into `token_expired` so the client's
silent re-login still triggers.

## What moved to the database

| Was | Now |
|---|---|
| `list_messages`, `list_dms` | `select` with the sender embedded (`users!messages_sender_id_fkey`) |
| `send_message`, `send_dm` | `insert`; a BEFORE trigger stamps `sender_id = auth.uid()` and `created_at`, so a client can't post as someone else or backdate |
| `edit_message`, `edit_dm`, `delete_message`, `delete_dm` | `update`/`delete` scoped by policy; the column grant limits an edit to the envelope |
| `list_users`, `get_server_details` | `select` on `users` / `servers` / `channels`, all scoped to your server |
| `create_channel`, `delete_channel` | `insert`/`delete` gated on `app.can_manage_channels()` |
| `create_invite` | `insert`; the code comes from a column default, and the policy refuses any permission the caller doesn't hold |
| `update_profile`, `publish_chat_key` | `update` on your own row — the column grant covers only `display_name`, `chat_public_key`, `avatar_path` |
| `toggle_reaction`, `list_reactions` | `insert`/`delete` keyed by `(message, user, emoji)`; a duplicate-key error *is* the "already reacted" answer |
| `moderate_user`, `set_user_permissions` | RPCs — RLS is row-level, so a policy allowing an admin to write another member's flags would also let them rewrite that member's identity |
| `list_dm_conversations` | `dm_conversations()` — `DISTINCT ON` instead of a thousand rows grouped in TypeScript |
| the `notifications` table | `unread_counts()` + `mark_read()` over `read_state` |

## Database schema

Defined by `self_hosted_server_migrations/`, run in order on a fresh instance. The central
project has its own set in `central_server_migrations/`.

1. **001_schema.sql** — types, tables, indexes, and the attestation triggers. Notable shapes:
   `server_secrets` split out of `servers` so the rest of that row is safe to read directly;
   envelope length limits as CHECK constraints (they used to be TypeScript in
   `_shared/chat.ts`, which is no validation at all once clients write directly); `read_state`
   as one cursor per conversation.
2. **002_security.sql** — `anon` revoked from everything, column-level grants for `authenticated`,
   RLS on every table, and every policy. The `app.*` helpers are `SECURITY DEFINER` on purpose:
   a policy that consults an RLS-locked table (say `messages` checking `channels`) evaluates
   false for everyone and silently denies — including every Realtime change it should have
   delivered.
3. **003_api.sql** — the RPCs: `register_user`, `moderate_user`, `set_user_permissions`,
   `unread_counts`, `mark_read`, `mark_all_read`, `dm_conversations`. Function EXECUTE is revoked
   from `PUBLIC` and handed back per function, so `register_user` isn't callable by a member.
4. **004_realtime.sql** — what may be subscribed to: `messages`, `dm_messages`, both reaction
   tables, `users`, `channels`. Realtime re-checks policies per subscriber, which is what allows
   badges without a fanout table.
5. **005_storage.sql** — `chat-attachments` (25 MB, E2E ciphertext), `avatars` (2 MB, **not**
   encrypted — same accepted trade-off as reactions), `servers` (public, fetched before login).
6. **006_jobs.sql** — one cron job, expiring invites. The old notification-retention job went
   with the table it existed to prune.

## Deployment

### Hosted Supabase project

```bash
cd edge_functions
supabase functions deploy --project-ref <ref>
```

Apply the migrations via the SQL editor or `psql`, in order.

### Self-hosted Docker stack

The docker-compose stack serves functions from its `volumes/functions/` directory via the
`main` router (path `/functions/v1/<name>` → `/home/deno/functions/<name>`):

```bash
cp -rf edge_functions/supabase/functions/. <stack>/volumes/functions/
docker restart supabase-edge-functions
```

Deleting a function from the repo does **not** remove it from a stack that already has it —
delete the directory in `volumes/functions/` too, or the old endpoint keeps answering.

Apply migrations with `docker exec -i supabase-db psql -U postgres -v ON_ERROR_STOP=1 -f - < <file>`.

Requirements for the stack's GoTrue config: enable the SIWS grant with
`GOTRUE_EXTERNAL_WEB3_SOLANA_ENABLED=true` (dev keeps signup on so SIWS auto-creates the
`auth.users` row; production sets `GOTRUE_DISABLE_SIGNUP=true` and provisions via `register`).
Keep `FUNCTIONS_VERIFY_JWT=false` — `login`, `register` and `resolve_invite` are invoked without
the runtime's own JWT gate (each self-validates).

### LiveKit

`get_channel_token` reads the credentials from `server_secrets`, so the `livekit_url` stored at
`create_server` time must be reachable **from the functions container as well as from clients** —
use a LAN IP (e.g. `ws://192.168.1.6:7880`), never `localhost`. When running
`livekit-server --dev` locally, start it with `--bind 0.0.0.0`.
