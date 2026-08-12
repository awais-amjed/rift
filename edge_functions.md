# Rift server API

How a client talks to a self-hosted Rift server. There are two transports, and which one a call
uses is a deliberate line rather than an accident of history:

- **Direct PostgREST**, under the policies in `self_hosted_server_migrations/002_security.sql`.
  This is almost everything: reading and sending messages, editing your own, member lists,
  channels, invites, reactions, read cursors.
- **Edge functions**, in [`edge_functions/supabase/functions/`](edge_functions/supabase/functions/),
  for the twelve things that genuinely can't be a table call.

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
| `create_server` | `service_key` in body | Writes the LiveKit API secret. Also seeds a `general` text channel and a `voice` voice channel — they differ in name because `(server_id, name)` is unique. Returns `server_id`, `name`, `supabase_url`, `supabase_key`, `invite_code` (single-use admin invite) |
| `update_server` | Bearer + `is_server_admin` | Writes the LiveKit API key/secret into `server_secrets`, which has no grant and no policy. Name, icon and the operator limits ride along rather than splitting one dialog across two transports. It does **not** touch storage: each server owns a `chat-<serverId>` bucket and a trigger moves that bucket's `file_size_limit` when the column changes (migration 008), in the same statement |
| `sweep_attachments` | Bearer (any member) | Needs the **Storage API**, not a secret: `storage.protect_delete()` refuses a direct DELETE on `storage.objects`, so no database role can free an attachment blob. Applies the server's retention settings via the `sweep_attachments` RPC (service-role only) and removes the blobs whose messages are gone. Safe for any member — it removes only unreferenced objects |
| `get_channel_token` | Bearer | Mints a LiveKit JWT with the API secret. Identity is `<userId>~<deviceId>`; `roomAdmin` for channel managers, 1 h TTL. **Moderation is enforced here at join time** — muted users get no `microphone` in `canPublishSources`, deafened users get `canSubscribe: false` |
| `moderate_user` | Bearer + `is_admin` (checked by the RPC) | Mute/deafen/ban. Calls the `moderate_user` RPC with the caller's JWT — the rules stay in the database — then uses the LiveKit API secret to push the new permissions and metadata onto every live connection the target holds. See below |
| `delete_channel` | Bearer + `channels_delete_managers` (checked by the policy) | Deletes the row with the caller's JWT, and the LiveKit room with the API secret. Rooms are named by channel id, so without the second half everyone carries on talking in a room whose channel is gone. Deleting a room disconnects its participants — that **is** the kick |
| `move_user` | Bearer + `is_server_admin` / `is_channel_manager` (checked here — nothing is written down, so there is no RPC to defer to) | Pulls a member from the call they're in into another voice channel, by sending their connections a "join this channel" packet with the API secret. See below |
| `voice_roster` | Bearer | Who is in which voice channel right now, `{userId: channelId}`, read off LiveKit. The snapshot a client starts from before the `voice:<serverId>` broadcasts can tell it anything — see ARCHITECTURE.md §5 |
| `get_channel_key` | Bearer | Channel-key distribution (below) |
| `post_channel_keys` | Bearer | Channel-key distribution (below) |
| `sweep_channel_keys` | Bearer | Channel-key distribution (below) |

### Moderation has to reach the live room

A mute is two writes, and for a long time only the first one happened. The flag
went into `users`, and `get_channel_token` refused the `microphone` source *the
next time a token was minted*. Nothing touched the call that was already in
progress, so a moderator watched a muted member keep talking — and the client
caches LiveKit tokens for 55 minutes, so even leaving and rejoining handed back
the old grant. In practice the mute landed somewhere up to an hour later.

`moderate_user` therefore does three things after the row is written:

1. `updateParticipant` on **every** connection the target holds — each device,
   plus their screenshare — replacing permissions and metadata. Rooms are named
   by channel id, so the search is scoped to this server's channels rather than
   every room on a shared LiveKit deployment. Revoking the microphone source
   makes LiveKit unpublish the track outright.
2. `mutePublishedTrack` on a live microphone, so audio already flowing stops now
   rather than at their next publish. Un-muting deliberately does *not* unmute
   their track — it restores the permission and leaves the mic to them.
3. `removeParticipant` instead of the above, when the action is a ban.

**A server deafen takes the microphone as well as the ears** — you can't hold up
your end of a conversation you can't hear, and every client already drew it that
way. `micDenied(muted, deafened)` is where that lives, so the grant and the live
permission agree on it.

**Moderation never overwrites what the member chose.** `LiveKitState` keeps
`isMicEnabled`/`isDeafened` as the member's own toggles and `isServerMuted`/
`isServerDeafened` as what was imposed; `isMicOn` is the conjunction. Lifting a
mute therefore needs no guesswork — the member's own choice was still recorded,
so someone who had muted themselves stays muted and someone who hadn't comes
back on. The client reacts to its own metadata changing by republishing the mic
(a revoked source makes LiveKit unpublish the track, so releasing it has to
publish again) and by resubscribing to remote audio when a deafen lifts.

The permission encoding is a trap worth knowing: `canPublishSources` on an
**AccessToken grant** uses `undefined` for "all sources", while the same field on
a live **ParticipantPermission** uses an **empty list**. `_shared/moderation.ts`
holds both forms as separate functions so the two enforcement points cannot
drift, and neither can be passed the other's encoding.

The client half is `TokenCubit.invalidateServerTokens`, called when
`ServerMembersCubit` sees the local user's own `is_muted`/`is_deafened` change —
otherwise the cached token would outlive the moderation that revoked it.

### Moving someone is a signal, not a server-side move

LiveKit can relocate a participant between rooms itself, and `move_user`
deliberately doesn't. Rift's channels are end-to-end encrypted and the **client**
is what holds the keys: a connection dragged sideways underneath it would land in
a room whose key it never fetched — deaf in the call, with the sidebar, presence
and chat all still pointing at the old channel, and a token minted for somewhere
else. So the target is *told* to join, and takes the ordinary path: fetch a
token, fetch the channel key, connect, publish. Everything that makes a normal
join correct stays in one place.

The instruction goes out over the LiveKit data channel, addressed to the target's
own identities, topic `rift.move`. **A packet sent through the API arrives with no
sender**, and no peer in the room can imitate that — which is the client's
authenticity check, and the reason a member can't move anyone. `VoiceSignal` on
the Flutter side refuses anything with a sender, a different topic, or a version
it doesn't know, and returns null rather than throwing on the arbitrary bytes a
public data channel carries.

Every device they're joined from is moved, the same rule moderation uses. Their
screen share is not: switching channels stops it client-side, which is the honest
outcome — a share belongs to the call it was started in. Someone who isn't in
voice at all gets `user_not_in_voice`; there is no connection to tell, and no way
to make a client join from nothing.

### How a structural change reaches everyone

There are two paths, and the second is the one that has to be right.

`server_events` is a **Broadcast doorbell**: whoever makes a change pings
`server_events:<serverId>` and every subscriber re-reads `get_server_details`.
It is a courtesy — it only rings if the actor remembered to ring it, and it
reaches nobody who was offline at the time.

`channels` and `users` are in the **realtime publication**, and `ServerTableWatcher`
subscribes to each on the selected server. That is the authoritative half: a
rename, a deletion, a join or a ban lands whatever the actor did. The row event
is used as a doorbell rather than a delta — Realtime re-checks the migration-002
policies per subscriber, so what arrives is only what that member could have
selected anyway, and the real read is the refetch it triggers.

**Deleting a channel evicts whoever is in it, twice over.** LiveKit does the
real work: `delete_channel` drops the room, which disconnects every device in
it. The client then tidies up locally — `ChannelEviction` compares what we are
still pointed at against the refreshed list, so a call we're no longer allowed
to be in is left properly and a chat whose channel is gone is closed. It never
acts on a *failed* refresh, or the first network blip would evict everyone from
everything.

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
| `create_channel` | `insert` gated on `app.can_manage_channels()` |
| `rename_channel` | `update`; the column grant covers only `name`. A LiveKit room is named by the channel's **id**, so renaming a voice channel doesn't touch the call inside it |
| `delete_channel` | still policy-gated, but back behind an edge function — it is the only thing that can drop the LiveKit room (above) |
| `create_invite` | `insert`; the code comes from a column default, and the policy refuses any permission the caller doesn't hold |
| `update_profile`, `publish_chat_key` | `update` on your own row — the column grant covers only `display_name`, `chat_public_key`, `avatar_path` |
| `toggle_reaction`, `list_reactions` | `insert`/`delete` keyed by `(message, user, emoji)`; a duplicate-key error *is* the "already reacted" answer |
| `moderate_user`, `set_user_permissions` | RPCs — RLS is row-level, so a policy allowing an admin to write another member's flags would also let them rewrite that member's identity. `moderate_user` kept the RPC but regained an edge function in front of it, which is the only thing that can reach LiveKit (above) |
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

Central's set is smaller and has no edge functions behind it at all. Its RPCs are `claim_handle`,
`send_dm`, `dm_quota`, `unread_counts`, `mark_read` and `dm_conversations`. Two of those exist
purely because **a PostgREST upsert cannot be used against a column-granted table**: the generated
`ON CONFLICT DO UPDATE` writes every payload column, conflict key included, and the privilege
check happens at plan time — so it is refused whether or not the row exists. `claim_handle` and
`mark_read` do the same upserts without touching the key.

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
