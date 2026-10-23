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
| How calls and shares work underneath, and the measurements behind them | `CALLS.md` |

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
| Bot SDKs | TypeScript and Rust. Each a second implementation of the wire format, not a binding | `rift-bot-sdk-node`, `rift-bot-sdk-rust` |
| Directory moderation | A separate site with its own accounts for reviewing reports against central's public directory. Never part of the app | `rift-admin` |
| On-device models | The image classifier each device runs on pictures it has decrypted, to decide whether to show them plainly — the server never sees a picture, so this is the only place one can be judged | `rift-models` |

The schema and the endpoints for both servers are in their own repositories, so a
migration named here is a file there. They are the source of truth; this document
is the reasoning behind them.

Patched dependencies are kept until upstream releases each fix. LiveKit's Rust
SDKs come from a public fork, `awais-amjed/livekit-rust-sdks`, whose `rift`
branch is a LiveKit release with our changes on top (`RIFT.md` there says what
and why) and is pinned by commit in `rust/Cargo.toml`. The rest are copies in
`third_party/`, each with a `RIFT_PATCHES.md` that lists its changes and says
when it can go back.

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

These properties are load-bearing:

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
TypeScript and Rust bot SDKs are held to those vectors without reading a line of it.

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
behaviour, and the support burden is the price. The one exception is a device
still signed in: its seed is already unwrapped, so a forgotten password is
replaced there with the emailed reauthentication code alone, which GoTrue
checks before it takes the new verifier (it skips the check for a session
signed in under 24 hours ago). The seed is re-wrapped from memory and a new
recovery key is shown, since whoever forgot the password has probably lost
the key too.

**Deleting the account** (Settings → Account & backup) is central's
`delete_account`. It asks for the password again and signs in with it, because the
function refuses a session that did not begin with a password in the last ten
minutes: a phone left unlocked is not enough to destroy an account. Every central
row cascades from the Auth user, so the function empties the person's Storage
folders (the backup, DM files, bug-report logs, directory icons), then deletes the
user. The servers on the device are untouched, since they never belonged to the
account, and the device re-wraps its seed under the typed password, the one a
vault with no account opens with. The person's DM partners lose those
conversations too, because each one is a single shared record. An account
banned from publishing in the directory leaves a hash of its address and the
servers it listed, so deleting it does not lift the ban (`directory_ban_marks`,
described in `rift-central`'s `docs/DIRECTORY.md`).

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
versions are never discarded, and a member who joins after a rotation can open
the old versions too, so they read what was said before it. Two things are kept
back: what a channel said while it was private (everything up to
`rotate_from_key_version`), and anything before a bot's grant.

### The key chain [Implemented October 2026]

Sealing every version to every member does not last. A channel of 50,000 that
rotates once a day (a ban a day) grows by 50,000 keyring rows a day, and a
newcomer a year in is owed 365 of them. So a rotation also stores a **link**: the
outgoing key sealed under the incoming one, the way Keybase chains a team's key
generations.

```
linkKey = HMAC-SHA256(newerKey, "keylink:v1")
link    = AES-256-GCM(olderKey, linkKey, nonce,
                      aad: "keylink:v1:<channelId>:<newerVersion>")
```

Whoever holds version n opens n − 1 from it, and so on down. A link only reaches
backwards, so it gives a banned member nothing: they are never sealed the version
that would open it. Two rotations are never linked, because what came before them
is not the next person's to read: the one that ends a channel's **private
stretch**, and the one a **bot's grant** starts at (bots are forward-only). The
sweep says which rotations may be linked, and `store_channel_key_link` refuses the
rest again on the server, because a server holding such a link could hand it over.
It also takes a link only for the version just minted, since a revoked grant
leaves no record of where it began.

What a member is sealed is then the current version and the top of each linked
stretch, not every version. And a member's client, having opened a link and found
it agrees with a row it already holds, drops that row (`prune_channel_keys`), so a
member keeps about one row per stretch. A link is the minter's word, which the
server cannot check: a member who mints a bad one costs a newcomer the history
below it, never a member a key they hold, because a sealed row always wins over a
link and a row is only dropped once its link is checked against it
(`ChannelKeyChain`).

The work itself — who lacks what — is found in the database, 500 entries to a
batch, and a channel's work goes to one online member at a time
(`channel_key_work`, `API.md` in `rift-self-host`). A rotation in a channel of
50,000 is still 50,000 seals, about a minute for one member's desktop client;
the chain is what keeps that from piling up.

**A removal changes the key at most once an hour.** A ban, a kick, somebody
taken out of a private channel or a bot's grant revoked waits until the current
key is an hour old, so a busy server's bans share one change instead of paying
50,000 seals each. The server stops serving the person the moment they are
removed; what the change adds is that a server operator passing them ciphertext
anyway gets nothing past it, and that now holds within the hour rather than at
once. Additions are not held back — a bot's grant, a private channel opening —
since waiting only keeps somebody out longer. A job each minute
(`app.ring_due_rotations`) rings the server when a held-back change falls due,
so an online member makes it on time.

### Channels that are not encrypted [Implemented October 2026]

A public channel anybody can join protects little by being encrypted: the people
it hides messages from, the server's operator included, can join and read. And
encryption is what makes a big channel expensive (*The key chain*, above). So a
channel manager can turn it off for a public text channel
(`set_channel_encrypted`, in the channel's Access settings). Private channels and
voice stay encrypted; closing a channel turns it back on.

While it is off, members post their messages in the clear (`key_version = 0`) in
the same body they would have sealed, polls included, files uploaded as they are, and still
signed, so the server cannot put words under anybody's name. The key never
changes there, so bans cost nothing; members are still sealed the key, so what was
encrypted before the switch stays readable to whoever joins, and turning it back
on rotates past anybody removed meanwhile. A message that is only text goes as
bare text, so an older client shows the words rather than the body's JSON.

The danger is a server switching it off quietly, so every switch posts who did it
in the channel, and every client draws the channel as "Not encrypted" — an amber
chip in the header, a notice over the composer — from the flag the server sends.
Those stand in for the per-message badge, which would otherwise be on every row,
and for the NOT ENCRYPTED pill a file sent unencrypted carries elsewhere.
The client also holds the line the database does: a private or voice channel is
encrypted whatever the server says (`Channel.isEncrypted`), since whoever runs the
database can skip its own rule, and the system message with it.
Bots see what they saw before: plaintext rows addressed to them, nothing else.

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
bucket holds opaque bytes. A stored file is named for the conversation it was
sent in (a channel's id, or `dm_<a>_<b>`), and a member may fetch it only where
they can read that conversation (`chat_attachments_select`); a server from
before that let any of its members fetch any file. Deleting a message has to delete its blobs, and
storage refuses a direct delete — so that path goes through an endpoint holding
the Storage API rather than any database role.

The sealing runs in the Rust library (`NativeBlobCipher`) on a desktop or
phone, off the UI thread: the Dart reference froze the window for seconds on a
big file. The web keeps the Dart path, on WebCrypto. Both write the same bytes
and check themselves against the same GCM specification vector.

**A big file can go up unencrypted, if its sender chooses** [Implemented
October 2026]. In a self-hosted server's public channel, a file of 25 MB or
more can be sent as it is, and the composer says the server can see it before
it goes. The file's name and the message stay sealed, and the sealed body
carries a SHA-256 of the bytes, so the server can read the file but not swap
it. It is badged NOT ENCRYPTED wherever it is drawn, with no setting, and a
forward re-encrypts it. A client from before this fails to open the file and
still shows the message (`WIRE.md` §8). Never in a DM or a private channel: on a server from
before `chat_attachments_select` asked about the conversation, every member
could fetch every stored file, so a plain file there would have been open to
the whole server (found in the Oct 7 security review).

How big a file can be at all is the operator's: the console sets storage's
limit and records it, and no server's own cap goes past it (`max_file_bytes`).

**A big file never has to fit in memory** [Implemented October 2026]. Past
16 MB (`AttachmentStaging.inMemoryMaxBytes`) a file is only pointed at when it
is staged, and is read, sealed and sent a chunk at a time:

- *Sealed under STREAM*: 1 MiB chunks, each its own AES-GCM message under a
  nonce holding the chunk's position and whether it is the last, so the server
  cannot reorder, drop or cut off chunks without a tag failing. Nothing about
  the layout is written into the blob, so a client from before this fails the
  file's tag and shows the rest of the message (`WIRE.md` §8, and its vectors).
- *Uploaded over tus* (Storage's resumable upload), about 16 MB to a request,
  because a browser will not stream a request body; a failed request resumes
  from the offset the server reports.
- *Downloaded as one response*, each chunk opened as it completes, rather than
  in ranged spans, which Storage's file backend is slow to start (about 1.7 s
  each, measured Oct 7); a dropped connection resumes with a range from the
first chunk not yet opened. It is saved beside the chosen name and renamed into
  place only once everything has opened, so a tampered or truncated file
  leaves nothing behind. Each platform saves through its own dialog
  (`file_save/save_target.dart`), and a copy the app makes of a picked or
  dropped file is the app's to delete (`PendingAttachment.temporary`).

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
more, and that page is what gets saved. A conversation is left when another opens
over it, when it is closed or covered, and when the app quits, which hides the
window and gives the save up to three seconds (`BeforeQuit`). Measured Sep 28
with `pg_stat_statements` over the same scripted session: 83 statements before,
85 after, all of it that one read.

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
DMs; signing out of central removes central's; a vault reset removes everything;
a channel the server stops listing is pruned. File operations run in the order
asked, and a wipe refuses writes asked for after it, because leaving a server is
exactly what makes the chat cubits save the conversation that is closing. Not on
the web, whose storage is the browser's. Left out of Android's backup and
phone-to-phone transfer (`res/xml/backup_rules.xml`): it is only a cache, and
unreadable without the keystore's seed. On the desktops it stays out of the
Documents folder, which Windows often syncs to OneDrive
(`StorageNamespace.profileDirectory`). iOS backs it up, sealed but not yet
excluded. See `MessageCache` and `SavedConversation`.

**Pictures too, in the clear** [October 2026]. Avatars and server and directory
icons are kept on disk between runs, so a restart draws them without downloading
each one again (`MediaDiskCache`, behind `MediaStore.images`). They are not
sealed: each is a picture every member of its server can already see. Together
they do say whom this device has seen, so a vault reset deletes them. Leaving a server does not; its pictures
go when nothing has drawn them for a month, or sooner when the folder passes its
size. A file is named by the SHA-256 of the host and the path, never the path
alone, since a server chooses its own paths and could repeat another's to leave
its bytes in that one's place; the copy in memory is held the same way. Attachments never go to disk: they are decrypted
message content. In the app's cache folder, which the OS may empty and Android
and iOS leave out of backups; not on the web.

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
  options are sealed in the body (in the clear where a channel's encryption is off); the rules the server enforces (how many options, one pick or
  several, when it closes) are in the clear on the row (`messages.poll`). Members read a poll's
  totals only — `poll_votes` shows each member their own rows — which hides a ballot from the
  room, not from whoever runs the server.
- **A server's icon is public** [October 2026]. It sits in the project's public `servers`
  bucket, because the screen that opens an invite draws it before there is a session, so
  anybody holding its path can fetch it; avatars stay private. `servers.icon_url` holds that
  path and never an address: every member's app fetches what the column names, and
  `update_server` refuses anything but a path in the server's own folder (`ServerIcon`
  checks the same), so an admin cannot send every member to a host that logs them. The
  directory never fetches it: a listing carries central's copy (`DirectoryIconPublish`).
- **No forward secrecy — deliberate.** Static keys are what make "recover seed → recover history"
  possible; ratcheting would destroy that. This is a product choice, not an oversight.
- Search becomes a client-side index; automod is metadata-only; link previews are generated by
  the sender's client; mobile push is data-only + on-device decryption.

---

## 5. Voice, video & screenshare — [Implemented]

LiveKit, one room per channel, joined with a short-lived JWT minted by the edge
function that holds the API secret. A screenshare joins the same room under an
`_screenshare` identity suffix, so somebody sharing is two participants.

**A stream is part of being in the call, never on its own.** A share is a
connection of its own, so the app holds the two together from both ends: the
sharer's share follows every join, region change and rejoin of its call, or
ends, and everybody else's app silences any share whose owner is not in the
room (`sharesWithoutOwner`), whatever the sharer's app did.

**A call belongs to its server, not to the selection.** It carries on while its
member reads another server, so everything it asks for — tokens, the key and its
rotations — and everything it draws and plays — faces, the soundboard, presence
— is the call's server's (`LiveKitState.currentServerId`, `CallServerScope`).
Following the selection was a real bug: the call's key work went to the server
being read, and the call stayed on a key the room had rotated off, connected
with no sound and no streams.

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

### Hiding your voice from somebody — [Implemented October 2026]

"Hide my voice from them" is the other direction from a mute for yourself:
they stop hearing you, in every call, until you take it back. It is this
device's setting (`AppState.voiceHiddenFrom`), and nobody is told. **The SFU
enforces it, not their app**: your app hands LiveKit an allow-list of who may
subscribe to your tracks (`VoicePrivacy`), naming a hidden person for
everything but your microphone, so a modified app hears no more than a stock
one. The microphone waits for the first list, and across a full reconnect it
sends silence until the new session has one. They still see you in the call,
and your speaking ring, and it rests on the server's LiveKit doing as told.
Verified Oct 14 2026 (`TESTING.md`; the detail is in `CALLS.md`).

### Encoding a share on the GPU — [Implemented October 2026]

A share's picture is encoded on the GPU wherever it can be, because a game is
using the CPU. LiveKit's Rust SDK has no hardware encoder on Windows, and the
NVENC encoder it has on Linux is built from NVIDIA's samples, under a licence
the GPL client cannot carry. So Rift encodes H264 itself and hands LiveKit the
finished frames (`rust/src/screenshare/encoder/`): through FFmpeg's GPU
encoders — NVENC, AMF and Quick Sync on Windows, NVENC and VAAPI on Linux —
built into a library of its own (`native/ffenc`), since libwebrtc carries
Chromium's FFmpeg under the same symbol names. Media Foundation, which ran past
WebRTC's target whenever the picture cost more, is kept only as AMD's fallback
on Windows.

- **H264 and AV1 are only ever encoded by the GPU or the OS, never by Rift.**
  The reason is patents: H264 is licensed through a pool the GPU makers belong
  to. VP8 and VP9 are royalty-free and stay on the CPU. Without a hardware
  encoder, or if one fails mid-share, the share goes out as VP9 and the user
  is told. Auto, the default, picks H264 where the GPU encodes it and VP9
  otherwise, or where sharpness was asked for.
- **AV1 is parked**: no viewer gets it encrypted, because LiveKit's Rust SDK
  does not negotiate what the server needs to find an encrypted AV1 keyframe
  and its JS SDK refuses to encrypt AV1. A live test says when that changes.
- **What LiveKit's encryption leaves readable has to be enough.** Its frame
  cryptor leaves only an H264 frame's first bytes in the clear, and a receiver
  reads the keyframe's PPS id from them. Several encoders write it past that
  point, so a share rewrites such a keyframe's header before LiveKit sees it
  (`h264::with_readable_pps_id`); unrewritten, viewers dropped pictures each
  time somebody joined.
- **A GPU encoder is held to WebRTC's target before it encodes** (`RateGate`),
  since WebRTC drops no pre-encoded frames: on a slow link the picture would
  fall behind its sound. A slow link gets fewer frames, never late ones.

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

### In depth

`CALLS.md` holds the rest, with the measurements and bugs behind each choice:
what a share sends and to whom (dynacast, and one picture rather than
simulcast), how a shared window's sound is found on Linux, the GPU encoders
maker by maker, how the desktop plays a call out and its 15 kHz ceiling, why
audio this client should not hear is held rather than unsubscribed, Windows
turning other apps down, and the speaking indicator.

---

## 6. Threat model summary

| Adversary | Identity/seed | Backups | Group chat | DMs | Voice |
|---|---|---|---|---|---|
| Network observer | safe | safe | safe (TLS) | safe | safe (SRTP) |
| Central server / its host | safe (E2E) | safe (E2E) | n/a | n/a | n/a |
| Self-hosted server's hosting provider | safe | n/a | safe (E2E) | safe | safe (E2E) |
| Self-hosted server admin | safe | n/a | readable (they're a member anyway); in a channel with encryption off, readable without joining, which every member is shown | **safe** | channel calls: accessible · DM calls: **safe** |
| A member, later banned | safe | n/a | what they read while a member; nothing the server sends after the ban, and nothing under the next key, which a ban brings within the hour (§4, *The key chain*). A bad key link they mint costs newcomers the history below it (§4, *The key chain*) | safe | ends at the ban |
| Device thief (no password) | Argon2id + secure storage | — | newest page of each channel opened, sealed under the seed (§4, *Saved on the device*); the avatars and icons drawn in the last month, in the clear | same | — |

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
kicked member makes it permanent; nobody can kick an admin or someone who can kick
or ban. A bot is kicked the same way, and also loses the channels it could read and
the calls it could hear; only a new bot invite brings it back (`BOTS.md`). It is
offered wherever a ban is, a voice participant's menu and an
open report included, and a report closed by one is recorded as `kicked`.

**Leaving** a server is a kick by your own hand (`leave_server`), so it is enforced
the same way and lifted the same way: you drop off the member list and out of the
member cap, lose your roles and private seats, and any new invite brings you back
as yourself. `users.left_at` marks it yours, which keeps you off the banned list a
moderator reads and tells your other devices to drop the server rather than show it
shut. The owner cannot leave without handing the server on; for them, and on a
server too old to ask, leaving only forgets the server on the device.

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
The same site lists every Rift account, for the same moderators: handle, the
sign-up email, when it signed up and was last active (a sign-in or a session
refresh), and what it lists in the directory (`moderation_accounts`). That is
what central already holds about an account; nothing is collected for it.

---

## 8. Updates — [Implemented October 2026]

The Windows and Linux apps replace themselves with a newer release through
Velopack (`rust/src/updater`). The release workflow packs each platform with
`vpk`: an installer that puts Rift in the person's own folder (no administrator
prompt to install or update), an AppImage, and for each a full package, a
delta from the release before, and a feed, `releases.<channel>.json`, listing
every package with its size and SHA-256. Installed copies read the feeds of
the last ten GitHub releases, download the newest in the background, and
replace themselves when the person restarts, or at the next start. A check
the person makes in Settings only finds: the download waits for them. Rift
fetches the packages itself (`rust/src/updater/transfer.rs`) rather than
through Velopack's download, so the person can pause one — the connection is
let go and the rest asked for with a `Range` request — resume it, or cancel
it, which the background check then respects for that version.

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

## 9. The app's log and bug reports — [Implemented October 2026]

Every session writes a log, so that someone whose share stopped or whose app
closed can send what happened. **Rust owns the file** (`rust/src/logging.rs`):
its own `log::` lines, Dart's `HelperMethods.printDebug` lines (through
`write_log_line`), panics and the errors nothing caught (`AppLog.catchErrors`)
all go into it, each written the moment it arrives. A crash in native code
therefore loses nothing it had buffered, and the last lines before it are the
ones that survive. Until Dart names the folder at startup, lines wait in
memory. Rust's lines are kept from `info` up.

One file per session, `rift-<UTC time>-<pid>.log` in the profile's `logs`
folder (Local AppData on Windows, the XDG data folder on Linux, the app's
own folder on Android), the newest ten kept. A crash is reported from the
session after it, so the one before has to survive a restart. A file past
8 MB is moved to `.old.log` and started again, keeping a long session's
latest lines. The web has no file: its last lines stay in memory for the tab.
Rust's own lines on Android go to logcat only, because flutter_rust_bridge's
logger there is not ours to tee.

**A native crash writes nothing of its own, so Rift writes it down**
(`rust/src/diagnostics/`). A crash in a GPU driver, FFmpeg or libwebrtc ends
the process mid-line, and its log just stops; what tells a driver's crash from
Rift's is the module it died in, and finding that used to mean asking the
person to dig it out.

- **Windows** keeps its own record. Each session, as it starts, reads the
  Application log, which needs no elevation, for Rift crashing
  (`Application Error`, event 1000) over the last 14 days, and writes the
  newest five into its log: the faulting module and its version, the
  exception, the offset, and the process id, which names the crashed
  session's file.
- **Linux and Android** keep nothing every system has, so a signal handler
  writes the crash into the crashing session's own log: the signal, the
  faulting address, and the stack as far as it unwinds, each frame a library
  and an offset. Inside a handler it may take no lock and allocate nothing, so
  each line is made on the stack and written straight to the file's
  descriptor, with an alarm in case the unwinder hangs. Then the signal goes
  on to what had it before: the default action, which ends the process as
  before, or Android's debuggerd, which still writes its tombstone. ART's own
  faults (its null checks) never reach it. An offset in Rift's own library is
  read back with `addr2line` against the same build.
- **Android** also records why each run ended (`ApplicationExitInfo`, Android
  11 and up): killed for memory, an ANR, force-stopped, a native crash. Each
  session writes the recent ones into its log (`AppExitReasons`), since a
  call's service killed in the background looks like a crash to whoever it
  happened to.

The same start logs each GPU with its driver: from DXGI on Windows (with
NVIDIA's own version number), from sysfs on Linux.

**What is in it is what a log line says**, and the log is something people
send. So a line never carries a secret or anything from a sealed message — a
link preview's failure names only the host. As a safety net, every line
passes through `redact` before it is written: anything shaped like a JWT, the
word after `Bearer`, and the value of `access_token`, `apikey`, `token`,
`password` and the like become `[redacted]`. What it does carry: the version
and system, the GPUs and their drivers, recent crashes and how
Android ended the runs before (library paths and offsets, no memory contents), server and room ids, error text, device
names, and the title of a window being shared.

**What goes to stderr is not this log, and on the desktop libwebrtc puts no
keys there.** On Linux an app started from the desktop has its stderr in the
journal. The libwebrtc flutter_webrtc 1.6.2 downloads (`m150.7871.03`) printed
the frame cryptor's `raw_key` and `derived_key` there in every build, so each
call left its key behind, and nothing outside the library turns that off since
m150. The desktop builds take the silent `.04` instead, through
`third_party/flutter_webrtc` (verified Oct 21 2026); the web logs none.
**Android still prints them to logcat**: its libwebrtc is a separate build
(`io.github.webrtc-sdk:android` `150.7871.01`, the newest there is) with the same
default and no way to change it from outside. Logcat is readable only by the
app, the system and a computer with USB debugging, and is not kept across a
restart, so this is far narrower than the journal, but it waits on a fixed
Android build. iOS and macOS are not checked.

**Report a bug** (Settings → General → Help) sends it. The person writes what
happened; `BugReportRepository` files it on central (`submit_bug_report`, ten
a day per account, a Rift account required), then uploads the newest four log
files, gzipped, into `bug-reports/<uid>/<report id>/`. The bucket takes a file
only under the uploader's own report, within an hour of filing it and four
files to a report, so a report id is not somewhere to keep putting bytes. Only
a moderator with a second factor reads them, on `rift-admin`'s Bug reports
page; central deletes a report after 90 days and the nightly sweep its files.
The dialog says what goes with it before anything is sent. On a desktop,
Help also opens the logs folder, for someone sending them by hand.
