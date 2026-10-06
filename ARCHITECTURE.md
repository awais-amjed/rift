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

Two dependencies are kept in this repository and patched, each until upstream
releases its fix. `RIFT_PATCHES.md` beside each lists the changes, and says when
the copy can go back:
- supabase's Realtime client, in `third_party/realtime_client`. Its 2.13.0
  release could leave a topic stuck off the socket after a reconnect, so a
  server's live updates stopped until a restart.
- LiveKit's `webrtc-sys`, in `third_party/webrtc-sys`, with one line changed.
  Without it WebRTC dropped frames a Windows share's GPU encoder had already
  made, and the viewer's picture broke until the next keyframe.

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
it cannot open, and neither half yields the other. A vault made in privacy mode
keeps its own password until the device signs in; from then on its seed is
wrapped by the account password like any other, so a new device restores with
nothing else typed. And a device signing in to a backup of its own vault — the
same seed — combines the two rather than asking which identity to keep.

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

Most people never compare codes, so a change is also caught without one.
Each device remembers the chat key it last saw for everybody it has a DM
with or a profile open on (`AppState.seenKeys`, a `SeenKey` per person):
trust on first sight, so the first key says nothing and any later one is a
change. A change draws a line in the DM at the moment it was noticed and
turns the header's "Encrypted" chip into an amber "Key changed", which stays
— on a phone too — until the safety code has been opened. For somebody you
had verified it stays until the new code is marked as matching or the
verification forgotten — and until then nothing is sent to them: the DM's
composer gives way to a notice offering the code (`KeyCheckGate`), and the
forward list leaves them out. Verifying said this key was theirs, so a new
one is not sealed to until somebody looks; "Forget" is the way to send
anyway. Everybody else is only told. The record is public keys and is never
uploaded; another device of yours keeps its own.

A server DM hears a new key while it is open. The `users` row moving rings
`members` on the server topic, and `DmCubit` reads its conversation list again,
which carries each peer's key; a changed one is derived anew and the open page read
again under it, so what was sealed to the old key shows as locked at once. A Rift
DM notices at its next list read — an arriving message or a launch — because
central rings nothing when a profile's key changes. Either way a derived DM key is
only reused while the peer key it came from is still the one listed.

It covers the key a message is *sealed to*, not yet the key it is signed
with: a member row carries `chat_public_key` and no signing key, so adding
that means a column and a migration first.

### Three things a client can do with a row [Implemented August 2026]

Reading a message has three outcomes, and for a long time two of them shared a line.

| Outcome | When | What the reader sees |
|---|---|---|
| **Opened** | decrypted and verified, or never sealed (a webhook, `key_version 0`) | the message |
| **Locked** | sealed under a key version this device does not hold, or signed correctly but not opening under the key it does hold | a placeholder row: author, time, and a lock |
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

The same holds when the key this device has is the wrong one: a DM key derived from a peer key
that has since changed, a channel key wrapped wrong. The signature is checked first and covers the
ciphertext, so a row that verifies and then fails to open is genuine and simply unreadable here —
locked, not dropped (`openSealed`). Dropping those was what emptied a DM the moment the other
person's key changed. Channels, server DMs and Rift DMs all take this path, and a DM with no key
at all shows its rows locked too.

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
A conversation is left when another opens over it, when it is closed, when another
surface takes the screen with it still open behind (a channel clicked from Server
DMs), and when the app quits — the window hides first and the save gets up to three
seconds (`BeforeQuit`). A killed app saves what it had; the next online open fills in.
Measured Sep 28 with `pg_stat_statements` over an identical scripted session (open
three channels, open a DM, send three messages, close it): 83 statements before,
85 after, all of it that one read. On the device, a copy is opened with the
same verification as a fresh page, so an open decrypts two pages instead of one.

**Rows, not messages.** What is saved is the rows exactly as the server sent
them, so a saved row goes back through the same open-or-lock-or-drop path as a
fresh one (*Three things a client can do with a row*, above). A channel's keys
come from the server, so its copy carries the key versions it was sealed under.
It also carries the display names its `@mentions` resolved to, which come from a
member lookup that fails offline. A DM's key is worked out on the device and is
not stored.

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

**A stream is part of being in the call, never on its own.** Being a connection
of its own, a share does not go where the call goes, so the app holds the two
together from both ends. The sharer's app follows every change of its call in one
place (`LiveKitCubit.onChange`, `LiveKitState.leftCall`) rather than at each way
out, and a share that finishes starting after its call has gone ends at once.
Everybody else's app leaves out, and silences, any share whose owner's connection
is not in the room (`sharesWithoutOwner`), whatever the sharer's app did, and
brings it back when the owner is. A region change or a rejoin puts the call in a
new room, so after every join the share follows it (`ScreenshareCubit.followCall`): on a desktop its connection is
replaced and the picture published again, keeping the capture, so a Wayland
portal is not asked a second time; a shared app's sound is started again; on the
web and on a phone, where a share can start only from a click or fresh consent,
it ends and the sharer is told. A share left in another call ends, and so does
one whose call failed to come back: it can reconnect with the token it holds
when the call cannot get a new one, and would stream on to a room the sharer is
not in. Viewers keep
watching a stream that drops out and is back within half a minute
(`WatchResume`), whoever's connection it was that dropped.

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

### What a share sends, and to whom — [Implemented October 2026]

A viewer receives a share only after pressing Watch, so most shares spend
time with nobody watching. The share's connection turns on LiveKit's
**dynacast**: the server tells the sharer to stop sending a picture nobody
receives, and libwebrtc stops encoding it (a GPU share's encoder carries on,
and WebRTC drops its frames). It pauses about 10 s after the last
viewer goes. The next viewer's first picture comes within a second. Calls had
it already, for cameras.

A share sends **one picture**, not simulcast's two or three sizes. Tried Oct
6 2026: on VP8 a second, half-size picture let a viewer on 2.5 Mbps watch at
30 fps where one picture gave them nothing, and stopped their requests for a
fresh picture costing everybody else full frames. But it does not reach what
Auto picks. libwebrtc turns VP9 simulcast into layers inside one stream and
holds it to its camera bitrates: a share set to 6 Mbps sent 2. Real VP9
simulcast needs a setting LiveKit's Rust SDK does not expose. And the path
the GPU's H264 goes through carries one picture.

### Encoding a share on the GPU — [Implemented October 2026]

LiveKit's Rust SDK has no hardware video encoder on Windows: every frame of a
share was encoded in software on the same CPU a game is using. So on Windows
Rift encodes H264 itself through **Media Foundation**, which reaches NVIDIA's,
AMD's and Intel's encoders alike, and hands LiveKit the finished frames on its
pre-encoded path (`rust/src/screenshare/encoder/`). Measured Oct 5 2026 at 60
fps: 52 to 67% of a core, against VP9's 186 to 196% (`TESTING.md`).

On Linux an NVIDIA GPU is driven by Rift itself, through NVENC, and the frames
go out on the same pre-encoded path as on Windows. LiveKit has an NVENC encoder
too, but it is built from NVIDIA's Video Codec SDK samples, which are under
NVIDIA's licence and not one the GPL client can carry, so Rift's build leaves it
out (it only goes in when CUDA's headers are found, and the release build has
none). Rift's goes through `shiguredo_nvcodec` (Apache-2.0): NVIDIA's
MIT-licensed API header, with the driver's libraries opened at run time, the
way OBS and Sunshine use NVENC. Measured Oct 5 2026 on an RTX 3070 Ti Laptop: a
moving 60 fps window at 15% of a core against VP9's 67%, held at 60 fps with
every core busy; a still one at 0.18 Mbps.

Intel's and AMD's GPUs on Linux go through LiveKit's VAAPI encoder, which falls
back to OpenH264 on the CPU without a word when it does not work. So without
NVENC, H264 is offered only where LiveKit lists VAAPI, the share asks for a
hardware encoder, and once its first frames are out a share whose encoder
WebRTC names as anything else goes to VP9. On a machine with neither (Intel's
VAAPI driver is a separate package) H264 is simply not offered.

- **H264 and AV1 are only ever encoded by the GPU or the OS, never by Rift.**
  The reason is patents: H264 is licensed through a pool the GPU makers belong
  to, so Rift ships no H264 encoder of its own. VP8 and VP9 are royalty-free
  and stay as CPU codecs. Without a hardware encoder, or if one fails mid-share,
  the share goes out as VP9 and the user is told.
- **Auto, the default, picks the codec and the bitrate** (`ShareEncoding`):
  H264 where the GPU encodes it, VP9 where it does not or where sharpness was
  asked for, since it keeps text crisper at the same rate. The bitrate cap
  follows the picture's size and rate and the codec, generous because it is
  only a cap, and held to the server's share limit like a chosen one.
  Either can still be picked by hand under the dialog's advanced settings.
- **Auto never drops to VP8 under load.** VP8 is the lighter codec only on an
  idle machine; on a busy one its encoder threads fight over the cores.
  Measured Oct 5 2026 on Linux (`bench_test.rs`, a moving 960x1000 window at
  60 fps): idle, VP8 took 43% of a core and VP9 67%; with every core busy,
  VP8 fell to 20 fps at 44 ms a frame while VP9 held 59 fps at 15 ms; pinned
  to one core, VP8 managed 4 fps. Under CPU pressure WebRTC already lowers
  the size or the rate, as the priority says.
- **120 fps is offered up to 2K on the GPU and up to 1080p on the CPU**
  (`ScreenShareSettings.frameRatesAt`). WebRTC stops at 120, so there is no
  144. 4K at 120 is past what most viewers' hardware decoders take (H264's
  level 5.2 ends near 4K60), so it is never offered. A picture too big for
  120 goes out at 60, and the choice is kept for a smaller one. Whether the
  sharer's computer keeps up is the sharer's call. Measured Oct 6 2026
  (`bench_test.rs`, a moving 960x1000 window): VP9 sent 119.6 fps at 114% of
  a core, the GPU's H264 119.9 fps at 26%, the viewer dropping nothing.
- **H265 is skipped**: too many viewers cannot play it.
- **AV1 is parked.** AMD's encoder makes AV1 that WebRTC carries, but no viewer
  gets it encrypted: LiveKit's Rust SDK does not negotiate what the server needs
  to find an encrypted AV1 keyframe, and its JS SDK refuses to encrypt AV1. The
  encoder keeps AV1, with a live test that says when that changes. The full
  notes, including the AV1 findings, are kept on the `gpu-encoding` branch.
- **GPU H264 stays constrained baseline**: LiveKit offers only that profile for
  pre-encoded tracks, and Firefox viewers cannot take High.

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

An update is code that runs with everything above, so it has its own guard
(§8): the GitHub releases it comes from are not trusted, only the release
key's signature.

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

A **kick** (`KICK_MEMBERS`) is a ban that the member's next invite lifts. The
server enforces it exactly as a ban — the same flag, so the same policies, key
rotation and call teardown — and takes their roles and private-channel seats, so
they come back as a newcomer under their old name, with their messages. Banning a
kicked member makes it permanent; nobody can kick an admin, a bot, or someone who
can kick or ban. It is offered wherever a ban is, a voice participant's menu and an
open report included, and a report closed by one is recorded as `kicked`.

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

## 8. Updates — [Implemented October 2026]

The Windows and Linux apps replace themselves with a newer release through
Velopack (`rust/src/updater`). The release workflow packs each platform with
`vpk`: an installer that puts Rift in the person's own folder (no administrator
prompt to install or update), an AppImage, and for each a full package, a
delta from the release before, and a feed, `releases.<channel>.json`, listing
every package with its size and SHA-256. Installed copies read the feeds of
the last ten GitHub releases, download the newest in the background, and
replace themselves when the person restarts, or at the next start.

**The feed is the trust boundary.** Velopack refuses a package that does not
match the feed, so whoever writes the feed chooses the code — and GitHub, or
anyone who gets into the account that publishes there, could write both. So a
feed counts only with `releases.<channel>.json.sig` beside it: an Ed25519
signature over `rift-update-feed-v1\n<channel>\n` and the feed's bytes, by a
key in `RELEASE_KEYS` (`rust/src/updater/signature.rs`). The private half is
kept in the release manager's keyring and nowhere else; `scripts/sign_release.sh`
signs a published release's feeds there, and until it has, no copy is offered
that release. The channel is in the message so one platform's feed cannot be
passed off as another's. Losing the key means no copy can be updated again
without a reinstall, so it has an offline, passphrase-sealed backup
(`scripts/release_key.sh export`); a replacement key is added to
`RELEASE_KEYS` beside the old one, and only used once enough copies carry it.

A copy not installed by Velopack — a build run from its folder, the
`.tar.gz`, the Program Files copy the old Inno Setup installer made — cannot
update itself and says so in Settings. On Windows the first start of a
Velopack copy offers to remove that old copy, behind one administrator
prompt (`windows/runner/velopack_hooks.cpp`).

---

## Speaking indicator

Encrypted frames cannot be measured by anyone without the key, but the level
travels beside them: each audio packet carries it in an RTP header extension the
frame encryption does not cover, so LiveKit's active-speaker detection works on
an encrypted call. Other people's indicators come from that. Your own is decided
on the device from the microphone's raw level, because the server reports only
the loudest few speakers on an interval and ordinary speech often never lit it.
