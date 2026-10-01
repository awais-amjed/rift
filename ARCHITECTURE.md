# Rift Architecture

How the pieces fit and why they were chosen that way. **An overview, not a
reference** — this used to be the document the project was built from, and grew
into a deep dive on everything at once. The detail has better homes now:

| For | Read |
|---|---|
| The exact formats a second implementation must match | `WIRE.md`, frozen by `test/wire_vectors.json` |
| What a server stores, and who may read it | the migrations in `rift-self-host` and `rift-central`, split by kind — tables, helpers, RPCs, triggers, realtime, storage, jobs, security |
| What a client may call, and over which transport | `API.md` in `rift-self-host` |
| What a bot may see, hear and say | `BOTS.md` |

What stays here is the shape of the system and the decisions behind it — the part
you cannot reconstruct from the code, because it is largely about what was *not*
built.

## Components

| Component | Role | Repository |
|---|---|---|
| Flutter app | UI on all platforms; all cryptography runs client-side (`CryptoRepository`) | `rift` |
| Rust core (`rust/`) | Screen capture + audio pipeline, publishes to LiveKit via flutter_rust_bridge | `rift` |
| Self-hosted server | One Supabase project (Postgres + Edge Functions) + one or more LiveKit servers. Anyone can run one; holds users, channels, messages, and E2E keyring material | `rift-self-host` |
| Central Supabase | Optional convenience service run by the project: account (email+password) + encrypted vault backups. Never required — privacy mode works without it | `rift-central` |
| Bot SDK | TypeScript. A second implementation of the wire format, not a binding | `rift-bot-sdk` |
| Directory moderation | A separate site with its own accounts for reviewing reports against central's public directory. Never part of the app | `rift-admin` |
| On-device models | The image classifier each device runs on pictures it has decrypted, to decide whether to show them plainly — the server never sees a picture, so this is the only place one can be judged | `rift-models` |

The schema and the endpoints for both servers are in their own repositories, so a
migration named here is a file there. They are the source of truth; this document
is the reasoning behind them.

One dependency is kept in this repository and patched: supabase's Realtime
client, in `third_party/realtime_client`. Its 2.13.0 release could leave a topic
stuck off the socket after a reconnect, so a server's live updates stopped until
a restart. `RIFT_PATCHES.md` there lists each change, and says when the copy can
go back to pub.dev.

Where the two schemas hold the same idea they use the same names — `users`,
`dm_messages`, `read_state`. Central's account row was `dm_profiles` until it was
written down as migrations: it is the account, and it holds more than a directory
profile.

The trust model in one line: **self-hosted server admins are trusted with membership and (plaintext
metadata of) their own server; the central server and hosting providers are trusted with nothing** —
everything they store is encrypted client-side.

---

## 1. Identity & vault — [Implemented]

Every user's identity derives from a single **256-bit master seed**, generated
on-device at vault creation. Nothing about identity is created server-side, so
there is no account to take away and no escrowed key to compel.

```
password ──Argon2id(salt, 64 MiB, 2 iter)──► vault key (256-bit)
                                                │
master seed (random 32 B) ◄──AES-256-GCM decrypt┘        (EncryptedSeed blob)
   │
   ├─ HMAC-SHA256(seed, "<host>:<server_id>:<version>") ──► Ed25519 keypair (SIWS login + signing)
   ├─ HMAC-SHA256(seed, "<host>:<server_id>:identity")  ──► stable_id (permanent per-server identity)
   ├─ HMAC-SHA256(seed, "<host>:chat:<version>")        ──► X25519 keypair (sealing: DMs, channel keys)
   ├─ HMAC-SHA256(seed, "vault:v1")                     ──► vault blob key (AES-256-GCM)
   └─ HMAC-SHA256(seed, "local-cache/messages:v1")      ──► saved-conversations key (this device only)
```

Four properties are load-bearing:

- **Identities are per server.** `<host>` is the hostname and `<server_id>` the
  server, so two servers cannot correlate a member by key material — and two
  servers sharing one Supabase project still get distinct `auth.uid()`s.
- **The chat keypair is per *host*, not per server, and pinned at `v1`.**
  Everything ever sealed to somebody is opened with it, so rotating it would make
  all of that unreadable. The signing key above carries a version; this one
  deliberately does not.
- **`stable_id` outlives keys**, so rotating a keypair cannot launder a ban.
- **A server's address is therefore permanent.** Everything above is keyed on
  the host, so moving a server to a new address makes every member a stranger
  and their history unreadable. A DNS name is the indirection that makes this a
  non-issue: repoint the record and the host never changed. `rift-self-host`
  states it as a rule.
- **A client stores that address once and never asks again.** `supabaseUrl` is
  captured when the invite is resolved, and every HTTP address — the API,
  attachments, avatars — is built from it. The one address a client takes
  *from* the server are its LiveKit nodes (`livekit_nodes`, §5), which is why
  voice is the only thing a server can move without moving its members.
- **Argon2id runs off the UI thread**, and the seed lives in platform secure
  storage — never in HydratedBloc state. On Windows that is a DPAPI-sealed file
  in the profile's folder under Local AppData (`ProfileSecureStorage`), not the
  plugin's own file in Roaming AppData, which a domain copies to every PC the
  person signs in to.

`rift_crypto` implements all of it, with no Flutter in it, and is the
**reference implementation**: the wire vectors are generated from it, and the
TypeScript bot SDK is held to those vectors without reading a line of it.

A **backup file** is portable JSON carrying three client-side-encrypted blobs.
Losing both the password and the recovery key loses all of it, and that is the
trade being made rather than a gap.

---

## 2. Self-hosted server auth — [Implemented]

Members authenticate with a **signature, never a password**: the client signs a
Sign-In-With-Solana message using the Ed25519 key derived above, GoTrue's web3
grant verifies it, and what comes back is an ordinary Supabase session.
Everything after is standard — PostgREST under row-level security, with edge
functions only where a secret or a pre-membership step is genuinely involved.

The SIWS message names `localhost` as its domain and URI on **every** server.
That is a constant, not a placeholder: GoTrue refuses most real addresses, and
those two fields exist so a *wallet* can say which site is asking. Rift has no
wallet, and the key is derived per `(host, server_id)` and posted only to the
host it was derived for. `WIRE.md` §4 freezes the template.

There is no key rotation. It was removed deliberately: a rotating identity is a
ban that launders itself, and the recovery story is the seed.

---

## 3. Central account & cloud backup — [Implemented]

Optional, and genuinely so — privacy mode contacts nothing but the servers you
join. What an account buys is a backup of the vault, and a way to be found.

**One password, split two ways.** It stretches into two independent values: one
becomes the credential GoTrue stores, the other never leaves the device and is
what encrypts the vault blob. Central holds a password verifier and a ciphertext
it cannot open, and neither half yields the other.

A **recovery key**, shown once at vault creation, is the second door. Central
cannot reset a password into a readable vault — resetting the credential half
leaves the ciphertext exactly as unreadable as before. That is the honest
behaviour, and the support burden is the price.

Central also runs the **public server directory** (opt-in, each listing proved by
a token the server's admin mints) and the **push relay**, which exists because an
FCM token is scoped to the app's Firebase project, so a self-hosted server cannot
wake its own members' phones. Relaying teaches central a device token and a
moment: not the sender, not the text, not the server or the channel.

---

## 4. Chat encryption — [Implemented]

Two designs, because two shapes of conversation have different key problems.

**Design 1 — encrypt to identity (DMs).** The conversation key falls out of an
X25519 exchange between the two chat identities, so there is nothing to
distribute and nothing for a server to hold. Both ends derive the same bytes from
opposite halves.

**Design 2 — wrapped channel key (channels).** One symmetric key per channel,
sealed individually to each member and stored as a keyring row. Adding a member
is a wrap; removing one is a rotation. Scrollback stays readable because old
versions are never discarded.

### DM topology — two tiers

Same Design-1 crypto in both; different hosts, different policies. Central is a
**funnel, not a home** — the project runs on no revenue, so central hosting cost
has to stay flat. People meet there and move real conversations to a server they
share.

|               | Central DMs                            | Server DMs                                     |
|---------------|----------------------------------------|------------------------------------------------|
| Purpose       | discovery + first contact              | real conversations                             |
| Storage       | central Supabase                       | a self-hosted server both users are members of |
| Identity keys | X25519 derived for the central host    | X25519 derived for that server's host          |
| Delivery      | GoTrue RLS + native Realtime           | Edge Functions + Realtime Broadcast            |
| Limits        | per-sender daily quota; 30-day TTL; per-conversation history cap (oldest trimmed first) — fixed, Rift's call | no message quota, but a cap on *new* conversations an hour (10 by default); a TTL and a history cap the admin sets, **off by default** |
| Media         | allowed; counts against quota, per-file size cap | allowed; per-file size cap the admin sets, and blobs swept with their messages |
| Unread badges | `read_state` cursors + `unread_counts()` | the same, for channels and DMs alike |

Central's limits are enforced server-side, so a modified client cannot bypass
them. Privacy-mode users simply have no central DMs; server DMs still work.

### Signatures

Every message is Ed25519-signed by its sender over a canonical payload
(`WIRE.md` §3). Without it a shared channel key would let any member — or the
server — forge a message from anybody in the room.

### Safety codes [Implemented September 2026]

A published key is only somebody's key if the server handing it over is
honest, so a pair can check for themselves: `SafetyCode` (in `rift_crypto`)
hashes both chat public keys with both user ids — 5200 rounds of SHA-256, the
two halves sorted by their own digits — into sixty digits both devices
compute identically, read off each person's profile and compared aloud or
side by side. Digits only: nothing scans a QR, so drawing one was decoration
on the screen that exists to be read.

Marking somebody verified stores **the code that was seen**, per device, in
`AppState.verifiedCodes` and nowhere else. A key that changes afterwards no
longer matches what was stored, and the profile says so rather than going on
claiming they are verified — which is the half that catches an interception
that starts later.

It covers the key a message is *sealed to*, not yet the key it is signed
with: a member row carries `chat_public_key` and no signing key, so adding
that means a column and a migration first.

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
the clear (§4, *metadata is visible*). Showing them reveals nothing a member without the key could
not read off the table directly, and without them the row says nothing about whose history this is.

### Attachments

Encrypted under their own key, carried inside the sealed message body, so the
bucket holds opaque bytes. Deleting a message has to delete its blobs, and
storage refuses a direct delete — so that path goes through an endpoint holding
the Storage API rather than any database role.

### Saved on the device [Implemented September 2026]

Each conversation this device opens — a channel, a server DM, a central DM —
keeps its newest page (`ChatMessageOps.pageSize`) in a file, so the next open
draws it before asking the server anything, and a conversation can still be read
with no connection. Before this, the only thing kept locally was the outbox,
for as long as the app was open.

**A head start, never the answer.** Every open still fetches the newest page and
replaces the drawn copy outright, never merges into it. A saved copy cannot know
what was deleted, edited or reacted to since, and merging would keep a message a
moderator removed. The cost is that a deleted message can show for the moment
the fetch takes. While the copy is on screen nothing on it can be acted on, and
the composer takes typing but holds the send until the fetch lands. When the
fetch fails, the copy stays up and a notice above the composer says what it is.
The composer is kept, still holding the send, so whatever was typed survives the
retry.

**What it costs the server: nothing to open, one read to leave.** Drawing a
copy asks the server nothing, and the open that follows makes the same requests
it always did. The one addition is for your own messages: a send answers with an
id, not a row, so leaving a conversation you sent in reads its newest page once
more, and that page is what gets saved. The read is the same query an open makes.
Measured Sep 28 with `pg_stat_statements` over an identical scripted session (open
three channels, open a DM, send three messages, close it): 83 statements before,
85 after, all of it that one read. On the device, a copy is opened with the
same verification as a fresh page, so an open decrypts two pages instead of one.

**Rows, not messages.** What is saved is the rows exactly as the server sent
them, so a saved row goes back through the same open-or-lock-or-drop path as a
fresh one (*Three things a client can do with a row*, above). A channel's keys
come from the server, so its copy carries the key versions it was sealed under.
A DM's key is worked out on the device and is not stored.

**Sealed as a whole**, AES-256-GCM under a key from its own rung of the ladder
(§1), with file and folder names that are HMACs under the same key. The rows are
mostly ciphertext already, but not all of it: webhook messages, author names,
times and reactions are in the clear on a row. The file is exactly as readable
as the seed that can already open the conversations, and no more.

**Wiped with whatever could open it.** Leaving a server removes its channels and
DMs; signing out of central removes central's; a vault reset removes everything.
A channel the server stops listing is pruned. Every file operation runs in the
order it was asked for, and a wipe refuses writes asked for after it. That is
because the chat cubits save the open conversation the moment they notice it
closing, and leaving a server is exactly what makes them notice, just after the
wipe. Not on the web, whose storage is the browser's rather than the platform's
secure store. Left out of Android's backup and phone-to-phone transfer
(`res/xml/backup_rules.xml`, `data_extraction_rules.xml`): a copy there would be
unreadable, because the key comes from the seed in the keystore, and it is only
a cache. On the desktops, everything the app stores stays out of the person's
Documents folder, which on Windows is often synced to OneDrive. On Windows it
lives in Local AppData, which never roams or syncs, and on Linux in
`~/.local/share` (`StorageNamespace.profileDirectory`). iOS backs up the Documents folder
these live in; they are sealed there too, but not excluded yet. See
`MessageCache` and `SavedConversation`.

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
  August 2026, **who a message named** (`messages.mentions`). E2E covers content only. That
  column exists so the server can ring somebody whose channel is set to mentions-only without
  reading the message; the operator learns who was addressed, not what was said.
- **Reactions, pins and poll votes are visible** to the server: who reacted with what, which
  messages are pinned, and who picked which option *number* of a poll. The question and the
  options are sealed in the body; the rules the server enforces (how many options, one pick or
  several, when it closes) are in the clear on the row (`messages.poll`). Members read a poll's
  totals only — `poll_votes` shows each member their own rows — which hides a ballot from the
  room, not from whoever runs the server.
- **No forward secrecy — deliberate.** Static keys are what make "recover seed → recover history"
  possible; ratcheting would destroy that. This is a product choice, not an oversight.
- Search becomes a client-side index; automod is metadata-only; link previews are generated by
  the sender's client; mobile push is data-only + on-device decryption.

---

## 5. Voice, video & screenshare — [Implemented]

LiveKit, one room per channel, joined with a short-lived JWT minted by the edge
function that holds the API secret. A screenshare joins the same room under an
`_screenshare` identity suffix, so somebody sharing is two participants.

**Media is end-to-end encrypted** with the channel's own key — the same key the
text keyring seals per member — so the SFU forwards frames it cannot open. DTLS
protects the hop; this protects the room.

A **bot is audible and deaf at the same time**, which one shared room key cannot
express. Its key is `HMAC-SHA256(channelKey, "voicebot:v1:<botId>")`: every
member derives it and hears the bot, and the bot cannot run the HMAC backwards to
reach the channel key. Hearing the room is a separate grant, made per channel and
enforced by minting the bot's token without `canSubscribe`.

Two questions, two transports. **Who is in the room** is LiveKit's, because it
already knows. **What they may do** is the database's, because that is where
permissions live. Muting somebody for yourself is local state; muting them for
everybody is a row.

### Regions — [Implemented September 2026]

A server may run several LiveKits (`livekit_nodes`) so a call is held near the
people in it. **A room lives on exactly one node** — the open-source server has
no cross-node media — so this is never "each person connects to their nearest".
It is one decision, made when the room opens: the live room if there is one, else
the channel's pin, else the region the opener's client measured as fastest, else
the default. Everyone after goes where the call already is. `servers.livekit_url`
survives as the default node's mirror, so nothing written before regions changed.

### 1:1 calls in server DMs — [Implemented September 2026]

Two members who can already message each other can call. The room is the call
(`dm-<callId>`, named apart from channels so it never shows up where rooms are read
as channels), and it reuses everything a channel call has: controls, sharing,
regions.

**Its media key comes from the pair's DM key** — `HMAC-SHA256(dmKey,
"dmcall:v1:<callId>")` — which the server never holds. So unlike a channel call,
where the admin can hold the key like any member, **a DM call is private from the
server's operator.** What the server does keep is the call record — who called
whom, when, whether it was answered, how long — because that is what rings the
other side and draws "Missed call" in the conversation. That is metadata, and
visible like the rest.

A call follows the DM rules exactly: only an open conversation (a request has to
be accepted first), never across a block, not while timed out, not without
`CONNECT`, and at most five unanswered calls to one person an hour. The client
rings for 30 seconds; the server allows 45 so an answer given at the last moment
still lands. Central (friends) DMs have no calls, because central has no LiveKit.

### Soundboard — [Implemented September 2026]

A press is a data message on the call's LiveKit channel, not audio and not a row.
Every listener fetches the clip once, caches it and plays it locally — so the
audience is exactly the call, and "turn their soundboard down" is a real control
rather than a request. The cooldown and length cutoff are applied by the
*listener*, because a limit the sender honours is one a modified client deletes.

---

## 6. Threat model summary

| Adversary | Identity/seed | Backups | Group chat | DMs | Voice |
|---|---|---|---|---|---|
| Network observer | safe | safe | safe (TLS) | safe | safe (SRTP) |
| Central server / its host | safe (E2E) | safe (E2E) | n/a | n/a | n/a |
| Self-hosted server's hosting provider | safe | n/a | safe (E2E) | safe | safe (E2E) |
| Self-hosted server admin | safe | n/a | readable (they're a member anyway) | **safe** | channel calls: accessible · DM calls: **safe** |
| Device thief (no password) | Argon2id + secure storage | — | newest page of each channel opened, sealed under the seed (§4, *Saved on the device*) | same | — |

---

## 7. Moderation — [Implemented September 2026]

Two kinds, run by different people, and kept apart on purpose.

**On a server, by its own moderators, in the app.** A member can report a message
or a member. A message report copies the **sealed envelope** — ciphertext, nonce,
key version, signature, author — never the text, so the database still holds no
plaintext; a moderator's client opens it with the channel key it already holds and
checks the signature. That makes a report unforgeable, and it survives the author
deleting the message. The reporter is never named to the reported. Server DMs
cannot be reported as messages, because their key belongs to the pair; the person
can be, with a note.

A report ends in one of: delete the message, a **time-out** (no posting, editing,
reacting, pinning or starting calls, up to 28 days, and it ends by itself), a ban,
or dismissal. Review and time-outs are permissions of their own (`REVIEW_REPORTS`,
`MUTE_MEMBERS`), and nobody can ban an admin or someone who can ban.

**DM spam** is the member's own call. Each member chooses, per server, who may
start a conversation with them: everyone, *ask me first* (a first message waits as
a request — no ring, no push, one message until accepted), or nobody new. Existing
conversations are never affected. A block is silent: the blocked member can no
longer message or call you, and a call already ringing between you ends. The
server also caps how many *new* conversations one member may open an hour. These
rules are enforced by the database, so a modified client cannot step round them;
`API.md` lists what each refusal says.

**Central's public directory is moderated elsewhere.** Reports against listed
servers and bots are reviewed on a separate site with its own accounts and
two-factor sign-in (`rift-admin`). Admin tools never ship in the app: a client
anyone can download is the wrong place for a door only moderators should see.

---

## Speaking indicator

Encrypted frames cannot be measured by anyone without the key, but the level
travels beside them: each audio packet carries it in an RTP header extension the
frame encryption does not cover, so LiveKit's active-speaker detection works on
an encrypted call. Other people's indicators come from that. Your own is decided
on the device from the microphone's raw level, because the server reports only
the loudest few speakers on an interval and ordinary speech often never lit it.
