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
| Bot SDKs | TypeScript and Rust. Each a second implementation of the wire format, not a binding | `rift-bot-sdk-node`, `rift-bot-sdk-rust` |
| Directory moderation | A separate site with its own accounts for reviewing reports against central's public directory. Never part of the app | `rift-admin` |
| On-device models | The image classifier each device runs on pictures it has decrypted, to decide whether to show them plainly — the server never sees a picture, so this is the only place one can be judged | `rift-models` |

The schema and the endpoints for both servers are in their own repositories, so a
migration named here is a file there. They are the source of truth; this document
is the reasoning behind them.

Patched dependencies are kept until upstream releases each fix. LiveKit's
Rust SDKs come from a public fork, `awais-amjed/livekit-rust-sdks`: its `rift`
branch is a LiveKit release with our changes on top, `RIFT.md` there says what
and why, and `rust/Cargo.toml` pins one of its commits. The rest are kept in
this repository, with a `RIFT_PATCHES.md` beside each that lists the changes and
says when the copy can go back. All of them:
- supabase's Realtime client, in `third_party/realtime_client`. Its 2.13.0
  release could leave a topic stuck off the socket after a reconnect, so a
  server's live updates stopped until a restart. 2.13.2 fixed most of that;
  the copy is 2.13.2 with three changes, so a slow join after a reconnect is
  not cut short.
- LiveKit's `livekit`, from the fork. Its Rust SDK never told the server a
  track was stereo, so a share's sound, captured in two channels, went out in
  mono.
- LiveKit's Flutter SDK, in `third_party/livekit_client`. It never asked to
  decode a track in stereo, so a stereo track was heard in mono on the
  desktop and on phones. And it closed a call's connection before disposing
  it, which on Windows and Linux left the connection's tracks registered, so
  turning somebody down or muting them after a rejoin could reach a dead
  track and change nothing.

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

The sealing itself runs in the Rust library (`NativeBlobCipher`) on a desktop
or phone, off the UI thread: the Dart reference took about 4 s for 50 MB with
the window frozen, and Rust takes about 0.3 s for 500 MB (measured Oct 7 on the
Linux desktop). The web keeps the Dart path, which the browser runs on
WebCrypto. Both write the same bytes, and each checks itself against the same
GCM specification vector.

**A big file can go up unencrypted, if its sender chooses** [Implemented
October 2026]. In a self-hosted server's public channel, a staged file of 25 MB
or more has a lock on its chip; opening it uploads the bytes as they are, and the composer
says the server can see them before the message goes. The file's name, and the
message, are still sealed. With no key there is no tag, so the attachment
carries a SHA-256 of the bytes inside the sealed body, and a download that does
not match is not shown: the server can read the file but not swap it. The file
is badged NOT ENCRYPTED wherever it is drawn, with no setting. The body still
writes `key` and `nonce`, empty, beside `plain` and `sha256`, so a client from
before this fails to open the file and still shows the message. A forward
re-encrypts it, since the choice was made for one server's readers. Not in a DM
or a private channel: on a server from before `chat_attachments_select` asked
about the conversation, every member could fetch every stored file, so a plain
file there would have been open to the whole server, which nothing on the
screen said (found in the Oct 7 security review).

How big a file can be at all is the operator's: the console sets storage's
limit and records it, and no server's own cap goes past it
(`max_file_bytes`).

**A big file never has to fit in memory** [Implemented October 2026]. Up to
16 MB (`AttachmentStaging.inMemoryMaxBytes`) a file is read when it is staged
and sealed in one piece, as every file was before. A bigger one is only pointed
at, and is read, sealed and sent a chunk at a time:

- *Sealed under STREAM* (aead's `stream` module): 1 MiB chunks, each its own
  AES-GCM message under a nonce of a 7-byte prefix, the chunk's position and a
  last-chunk flag, so the server cannot reorder, drop or cut off chunks without
  a tag failing. The attachment carries `chunk` (the chunk size) and the prefix
  in `nonce`; the layout follows from those and the size (`ChunkedLayout`), so
  nothing is written into the blob. A client from before this fails the file's
  tag and shows the rest of the message. Rust, the Dart reference the web uses,
  and Python's AES-GCM agree on the same test chunks.
- *Uploaded over tus* (Storage's `/storage/v1/upload/resumable`), about 16 MB
  to a request, because a browser will not stream a request body. A request
  that fails is sent again from the offset the server reports, and the token is
  asked for before each one, so a session that expires partway is renewed
  rather than fatal.
- *Downloaded as one response, read as it arrives*, each chunk opened as it
  completes. Not ranged spans: Storage's file backend spends about 1.7 s
  starting each ranged reply (measured Oct 7). A dropped connection is taken up
  again with a range from the first chunk not yet opened. Saving writes beside
  the chosen name and renames into place only once everything has opened, so a
  tampered or truncated file leaves nothing behind.
- *Where it lands* differs by platform (`file_save/save_target.dart`): a
  desktop's own save dialog, a phone's after a scratch download (Android and
  iOS only hand out a place through their dialog), and a growing Blob on the
  web, which the browser holds whole until the download starts (a 2 GB save
  took Chrome about 2.4 GB, measured Oct 7). Picking on a phone goes through file_picker, which copies to a cache
  file natively; file_selector's Android side reads the whole file into memory.
  That copy, and the one a sandboxed macOS app makes of a dropped file, is the
  app's to delete (`PendingAttachment.temporary`): once read into memory, when
  its chip is removed, or when the send is over and the outbox is not holding
  it for a retry (`Outbox.settle`). A start clears whatever a closed app left.

A file sent unencrypted streams the same way and is hashed as it goes. On
the web both ends need care to stay a chunk at a time: a picked file is read
by fetching its blob URL as a stream, because `XFile.openRead` there reads the
whole file first, and the hash is the pure-Dart SHA-256, because WebCrypto can
only hash a buffer whole. A
forward of a big file goes through a scratch file in the app's cache directory
(not `/tmp`, which Linux often keeps in memory).

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

**Pictures too, in the clear** [October 2026]. Avatars and server and directory
icons are kept on disk between runs, so a restart draws them without downloading
each one again (`MediaDiskCache`, behind `MediaStore.images`). They are not
sealed: each is a picture every member of its server can already see. Together
they do say whom this device has seen, so a vault reset deletes them. Leaving a server does not; its pictures
go when nothing has drawn them for a month, or sooner when the folder passes its
size. A file is named by the SHA-256 of the host and the path, never the path
alone, since a server chooses its own paths and could repeat another's to leave
its bytes in that one's place. Attachments never go to disk: they are decrypted
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

**A call belongs to its server, not to the selection.** It carries on while
its member reads another server, so the call keeps its own
(`LiveKitState.currentServerId`), and everything it asks a server for names
that one: a rejoin's token, a share's, the key it loads and the rotations,
heals and bot seals that follow (`ChannelKeyring` keeps the server it loaded
from). A join that starts from a channel finds the server listing it
(`SessionRepository.serverWithChannel`), since a moderator's move or a resumed
call can arrive while another server is open. Following the selection was a
real bug: the call's key work went to the server being read, failed there, and
the call stayed on a key the rest of the room had rotated off — connected,
with no sound and no streams.

The same holds for what the call draws and plays, and for where it is seen.
`SessionRepository.callServer` names the call's server (published by
`LiveKitCubit`). What the app keeps live about a server — its roster,
presence, soundboard, voice listeners, reports and doorbell — is that server's
`ServerContext`, and `ServerHub` holds the call's server's context for as long
as the call lasts, beside the selected server's. So the call's tiles read the
call's roster for faces and names, and the call reads it to tell its bots
apart, whose key is a different one; a press is played from the call's
server's library; and our presence entry and voice location stay on the call's
server while another is open, since its presence cubit is alive. A context
nothing holds is shut at once. The call's surfaces sit under the call's
server's scope (`CallServerScope`), which its menus, profile and full-screen
stream carry with them, so a right-click on a tile moderates, moves, reports
and messages on the call's server. Every call to a server is bound to the server it
names (`ServerSession`); none falls back on the selection, so a surface that
forgets to name one fails to compile rather than acting on the server being
read. Before this, opening another server mid-call
turned every face in the call into a generated one, silenced the call's
soundboard, and showed everybody still on the call's server that the member
had left a call they were still talking in. Verified Oct 18 2026 with three web
clients on the local stack (`TESTING.md`).

Nothing below the server list reads the selection but `ServerHub`. The open
channel and the server DM list are the selected server's because the hub tells
them when it moves; each keeps the server it was told, and a channel opens on
the server the click names. So a send, a key sweep or a DM read begun on one
server finishes on it, and which server notifications count as "open" is the
one the chat and the DMs say they are on rather than whichever is selected by
the time they ask.

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
device's setting, kept like a mute for yourself (`AppState.voiceHiddenFrom`), and
nobody is told, not even them.

**The SFU enforces it, not their app.** Your app tells LiveKit who may subscribe
to your tracks (`VoicePrivacy`), and the server sends your microphone to nobody
else, so a modified app hears no more than a stock one. LiveKit has no "everyone
but these", so once anybody is hidden the call runs on an allow-list: everyone
present is named, a hidden person with every track of yours except the
microphone, and all of their connections (each device, each share) are covered,
since the list goes by user id. Somebody who joins later hears you once your app
has named them, about a fifth of a second after they arrive. A track you publish
is named only by the next list, which never names the microphone. While anybody
is hidden, the microphone is not published inside the connect: it waits until
the first list has gone, or it would reach everyone present before the list
could. Verified Oct 14 with the Linux app against a local LiveKit and scripted
listeners (`TESTING.md`): the hidden person, and their second device, received
nothing, including across a rejoin; somebody arriving later got the mic as they
joined; hiding mid-call cut them within a second; and un-hiding reconnected them.

A **full reconnect** is a new session on the server, which lets everybody
subscribe until told otherwise, and LiveKit publishes the microphone again
before the app hears the call is back. So while anybody is hidden, the
microphone sends silence from the moment the call drops until the list has been
sent for the new session. A hidden person may be subscribed for that moment, but
only to silence. Verified Oct 14 with three forced full reconnects
(`sendSimulateScenario`) while speech played into the test mic: the hidden
person was never subscribed, and everyone else had speech again within a
quarter of a second.

What it does not hide: they still see you in the call, and your speaking ring,
which comes from the server's active-speaker reports (*Speaking indicator*).
They also hold the room key, so it rests on whoever runs the server's LiveKit
forwarding as told.

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

### Which sound goes with a shared window — [Implemented October 2026]

Windows records a window's sound by its process. Linux has no such tie: a
window is the desktop's, a sound is a PulseAudio stream. So a window share on
Linux finds the window's app, guesses its stream (`ShareSoundMatch`: the
window's process or one it started, then the app's id word by word, then a
player naming its track in the title), and asks the user to confirm in a popup
after the window is picked. The popup can **remember** the answer per app, and
the next share of that app's window skips it while that app is playing. No good
guess means every app but Rift, which still carries the window's sound.

Finding the app is where the platforms differ. X11 says it outright
(`_NET_WM_PID`, `WM_CLASS`), so the window is picked in Rift's own dialog.
Under Wayland the ScreenCast portal tells an app nothing about the window
picked, and libwebrtc runs that portal itself. On **GNOME and KDE** Rift runs
the picker first, asking for the pick to be kept (`persist_mode` 2): the
desktop then saves the window's app id and title in the PermissionStore under
the pick's restore token, Rift reads them, and libwebrtc is handed the token
(`select_restore_token`, a patch in our LiveKit fork) and opens the same
window with no second picker. GNOME saves a D-Bus structure; KDE saves a Qt
`QDataStream` (`KdeSavedPick`). GNOME deletes the saved pick once it is used
and KDE keeps it, so Rift deletes it after every share. Both ask as the same
app: GTK registers the app's own connection with the portal, so Rift's picker
registers its connection too, or the pick is saved for an unnamed app that
libwebrtc's request cannot see. Other Wayland desktops save nothing by
default; there the app picks the sound in the share dialog as before.

### Encoding a share on the GPU — [Implemented October 2026]

LiveKit's Rust SDK has no hardware video encoder on Windows: every frame of a
share was encoded in software on the same CPU a game is using. So on Windows
Rift encodes H264 itself and hands LiveKit the finished frames on its
pre-encoded path (`rust/src/screenshare/encoder/`): through **FFmpeg's GPU
encoders**, NVENC on NVIDIA's GPUs, AMF on AMD's and Quick Sync on Intel's,
from the same library as Linux's VAAPI below, tried in that order. **Media
Foundation** is the fallback on AMD's GPUs only, where the library will not
load or AMF will not open; where neither opens, the share goes out as VP9.
Media Foundation is not the fallback for NVIDIA's and Intel's GPUs: NVIDIA's
encoder there crashed a 120 fps share twice in two runs.
Media Foundation reaches all three makers' encoders but runs past WebRTC's
target whenever the target is below what the picture costs: on a laptop's
Iris Xe and RTX 3070 Ti the rate gate had to leave out 200 to 1000 pictures
while WebRTC's estimate climbed at the start of a share (Oct 9 2026), and a
friend's 120 fps share on a 4070 Ti Super collapsed. FFmpeg's NVENC and Quick
Sync, on the same laptop, followed a rate moved from 20 to 5 to 12 Mbps
within a few percent, with no keyframe at a move, and so did FFmpeg's AMF on
an RX 9070 XT (Oct 11 2026), which left the rate gate under half of
Media Foundation's work there and held 98 to 116 fps on an upload capped at 8
to 30 Mbit where Media Foundation fell to 75 to 106. A PC with Intel graphics
beside an NVIDIA or AMD card gets the card's encoder, as on Linux; the
pictures reach the encoder from memory, so the GPU the screen is on does not
matter. Measured Oct 5 2026 through Media Foundation at 60 fps: 52
to 67% of a core, against VP9's 186 to 196% (`TESTING.md`).

On Linux an NVIDIA GPU is driven through **FFmpeg's NVENC encoder**, as on
Windows, and the frames go out on the same pre-encoded path. LiveKit has an
NVENC encoder too, but it is built from NVIDIA's Video Codec SDK samples, which
are under NVIDIA's licence and not one the GPL client can carry, so Rift's
build leaves it out (it only goes in when CUDA's headers are found, and the
release build has none). FFmpeg's reaches NVENC through nv-codec-headers: NVIDIA's
MIT-licensed API header and FFmpeg's loader, with the driver's libraries opened
at run time, the way OBS and Sunshine use NVENC. Measured Oct 16 2026 on an
RTX 3070 Ti Laptop: a moving 960x1000 window at 60 fps on 14% of a core, and
at 120 fps on 25% with nothing dropped (`TESTING.md`). Until then Rift drove
NVENC on Linux through the `shiguredo_nvcodec` crate; one encoder library for
both systems put the Windows fixes on Linux too: the
moved bitrate without a keyframe, the picture NVENC holds above 60 fps, the
colour tag. NVIDIA's encoder library waits on its threads for ever when the
process exits with an encoder open, so the library closes any still open at
exit (`ffenc.c`).

Intel's and AMD's GPUs on Linux are driven through **FFmpeg's VAAPI encoder**,
on the same pre-encoded path. LiveKit has a VAAPI encoder too, but on an AMD
RX 9070 XT (Mesa 26.2, Oct 9 2026) it stalled the viewer for 2 to 6 s every
8 to 25 s and made 34 of 60 frames a second; Rift's FFmpeg on the same GPU
was decoded at 56 of 60 and 115 of 120, one dip in two minutes. FFmpeg cannot be linked beside libwebrtc, which carries Chromium's
FFmpeg under the same symbol names, so it is built into a library of its own
(`native/ffenc`): FFmpeg 9.0.2 with nothing but `h264_nvenc` and `h264_vaapi`
on Linux (and `h264_nvenc`, `h264_qsv` and `h264_amf` on Windows), every
FFmpeg symbol hidden, opened by the Rust crate at run time
(`encoder/ffmpeg.rs`), and the first that opens an encoder is the one used:
NVENC, then VAAPI's render nodes in order. FFmpeg's VAAPI
encoder sends the bitrate to the GPU only with a keyframe, so the build patches
it to send WebRTC's every move with the next picture
(`third_party/ffmpeg/RIFT_PATCHES.md`); unpatched, an Intel GPU stayed at its
opening 8 Mbps while WebRTC asked for 2. It runs in variable bitrate capped at
the target, with the finest quantiser held at 18 as on Windows: in constant
bitrate Intel's GPU padded a still picture out to the full rate, and without
the floor it re-coded one at 4 Mbps of 20; a shared screen is mostly still.
FFmpeg's encoders, on both systems, say in the stream that its pictures are
BT.601 in limited range, which is how libyuv converts them (`ffenc.c`), so no
decoder guesses BT.709 for an HD picture and shifts its colours. Media
Foundation's fallback is left as it was, which leaves it to the decoder, whose
guess in libwebrtc is BT.601 anyway. NVENC comes first where both are
present. With neither, or without the library, H264 is not offered, and a
share asked for in H264 goes out as VP9.

- **H264 and AV1 are only ever encoded by the GPU or the OS, never by Rift.**
  The reason is patents: H264 is licensed through a pool the GPU makers belong
  to, so Rift ships no H264 encoder of its own (the FFmpeg it builds has only
  the encoders that drive a GPU's). VP8 and VP9 are royalty-free
  and stay as CPU codecs. Without a hardware encoder, or if one fails mid-share,
  the share goes out as VP9 and the user is told.
- **Auto, the default, picks the codec and the bitrate** (`ShareEncoding`):
  H264 where the GPU encodes it, VP9 where it does not or where sharpness was
  asked for, since it keeps text crisper at the same rate. The bitrate cap
  follows the picture's size and rate and the codec, with no ceiling of its
  own because it is only a cap (2K at 120 fps in H264 asks for 34 Mbps). The
  server's share limit holds it, like a chosen one, which can be up to 100.
  Either can still be picked by hand under the dialog's advanced settings.
- **Auto never drops to VP8 under load.** VP8 is the lighter codec only on an
  idle machine; on a busy one its encoder threads fight over the cores.
  Measured Oct 5 2026 on Linux (`bench_test.rs`, a moving 960x1000 window at
  60 fps): idle, VP8 took 43% of a core and VP9 67%; with every core busy,
  VP8 fell to 20 fps at 44 ms a frame while VP9 held 59 fps at 15 ms; pinned
  to one core, VP8 managed 4 fps. Under CPU pressure WebRTC already lowers
  the size or the rate, as the priority says.
- **120 fps is offered up to 2K, whatever encodes it**
  (`ScreenShareSettings.frameRatesAt`). WebRTC stops at 120, so there is no
  144. 4K at 120 is past what most viewers' hardware decoders take (H264's
  level 5.2 ends near 4K60), so it is never offered. A picture too big for
  120 goes out at 60, and the choice is kept for a smaller one. Whether the
  sharer's computer keeps up is the sharer's call. Measured Oct 6 2026
  (`bench_test.rs`, a moving window over X11, on a 20-thread laptop CPU):
  at 1920x1080 VP9 sent 119.8 fps at 147% of a core, 3.7 ms a frame; at
  2560x1440 VP9 sent 105 fps at 268%, 7.8 ms a frame against the 8.3 that
  120 allows, and the GPU's H264 112 fps at 86%. At 2K neither encoder was
  the limit: grabbing a window that size over X11 takes 7 to 9 ms. On
  Windows a share asks not to be power-throttled while it runs
  (`capture.rs`): Windows 11 slows a process it judges out of sight, as Rift
  is behind a game, and capture at 120 fell to about 92 pictures a second
  within seconds; unthrottled it held 119.8 (Oct 16 2026, a test process
  with no window, so the app's own case is inferred, not measured). FFmpeg's
  NVENC also holds one picture above 60 fps (`ffmpeg.rs`, `delay_frames`):
  waiting out each one at the idle clocks NVIDIA's driver drops to a few
  seconds into a share had kept it near 87 fps, and with it the viewer got
  118.7, at one more picture of delay (8 ms).
- **H265 is skipped**: too many viewers cannot play it.
- **AV1 is parked.** AMD's encoder makes AV1 that WebRTC carries, but no viewer
  gets it encrypted: LiveKit's Rust SDK does not negotiate what the server needs
  to find an encrypted AV1 keyframe, and its JS SDK refuses to encrypt AV1. The
  encoder keeps AV1, with a live test that says when that changes. The full
  notes, including the AV1 findings, are kept on the `gpu-encoding` branch.
- **GPU H264 stays constrained baseline**: LiveKit offers only that profile for
  pre-encoded tracks, and Firefox viewers cannot take High.
- **What LiveKit's encryption leaves readable has to be enough.** Its frame
  cryptor leaves an H264 frame's bytes up to the first slice in the clear and
  authenticates them, plus that slice's NAL header and the byte after it, and
  a receiver reads two things from there: the start codes, which it rebuilds
  in the four-byte form (`h264::with_long_start_codes`, Oct 4 2026), and the
  IDR's PPS id. FFmpeg's VAAPI encoder wrote slice types whose bits pushed the
  id one bit into the ciphertext, so about one keyframe in two named a PPS
  that did not exist; whoever was watching dropped it and the pictures after,
  for up to a second each time somebody joined. The build patches it to the
  short slice types NVENC writes (`third_party/ffmpeg/RIFT_PATCHES.md`). On
  Windows Intel's runtime writes the header itself, as type 7, for Quick Sync
  and Media Foundation alike, with no setting to change it, on Linux so
  does Mesa's encoder for AMD whatever FFmpeg hands it, and on Windows so do
  AMD's AMF and its Media Foundation encoder. So a share
  rewrites such a keyframe's header before LiveKit sees it
  (`h264::with_readable_pps_id`): the short type, and `idr_pic_id` made as
  many bits longer, so the slice data stays where it was. Measured Oct 16
  2026 on an Iris Xe, a viewer joining every 4 s: before, the one already
  watching fell to 36 fps with 45 keyframes asked for in a minute; after,
  60.0 fps and none; on an RX 9070 XT at 1440p60, 42.0 fps with 46 asked
  for, then 59.8 and none. A share logs a warning if a keyframe still puts the id
  past the readable byte (`h264::idr_readable_when_encrypted`); the GPU live
  test fails on one.
- **A GPU encoder is held to WebRTC's target before it encodes, not after.**
  WebRTC's frame dropper is off for pre-encoded frames (`webrtc-sys` 0.3.49),
  since a dropped H264 frame breaks every frame after it until the next
  keyframe. That leaves whatever an encoder makes beyond the target — variable
  bitrate on a fast game, or a moment's lag behind a falling estimate — waiting
  in WebRTC's send queue, and on a link that cannot carry it the picture falls
  behind its sound. So `RateGate` (`rate_gate.rs`) counts what the encoder makes
  against the target and leaves pictures out on the way in once it is 0.2 s
  ahead: a slow link gets fewer frames, never late ones. Measured Oct 9 2026
  (`bench_test.rs`, Linux NVENC at 120 fps on a 10 Mbit upload, the encoder
  made to ignore the target): without it every packet waited 1.1 s in the
  queue, the link lost them and the viewer decoded nothing; with it nothing
  waited or was lost and the viewer got 36 fps. An encoder that follows the
  target lost 56 pictures in 30 s, as the estimate fell, and held 120 fps.
  A keyframe, made whenever a viewer joins or loses packets, can cost a few
  pictures' worth at once, and what the gate leaves out after it is left out
  for every viewer; its log line counts those apart. Measured Oct 16 2026 at
  1440p60 and 8 Mbps with a viewer joining every 4 s: on a still screen of
  text Intel's VAAPI made keyframes of about 300 KB and left out about 12
  pictures after each, NVENC on Linux about 110 KB and 1 to 6; on a moving
  picture keyframes were 50 to 65 KB and nothing was left out. Halving the
  encoder's buffer took VAAPI's 12 to about 6 but left the keyframe of text
  softer (29.6 against 30.5 dB), and a still screen is what text is shared
  on, where a picture left out changes nothing on screen. So the buffer stays
  at one second.

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

### How a call is played out on the desktop — [Implemented October 2026]

On the desktop, everything a call plays — voices, a share's sound, a bot —
passes through WebRTC's audio processing module on its way out, not around
it. The library flutter_webrtc ships always installs a render
pre-processor (an empty one unless set), and with one installed WebRTC plays
the module's own copy of the audio instead of the audio. That copy runs at the
module's processing rate, and on Linux that is the capture rate, 16 kHz until the
microphone has recorded something. Somebody who joined muted and stayed muted
heard the whole call cut off just under 8 kHz; one unmute was enough to bring
it to the module's 32 kHz, and that held after muting again.

`PlayoutWarmup` closes that gap: joining without transmitting, the client
sends the microphone from one peer connection to another inside the process
for half a second, which is enough for the module to learn the rate, and closes
both. Nothing leaves the app and the call does not see the microphone open.
Once per session, since the rate holds until the app quits. Measured Oct 10
2026 on Linux: muted from the start went from a 7.3 kHz cut-off to 14 kHz, the
same as having unmuted.

**Linux only.** Windows uses the same library and measured differently in the
VM: about 14 kHz joined muted and unmuted alike, while the warm-up took it to
7.4 kHz and made Windows turn other apps down — recording there opens a
communications stream, which is what Windows ducks for.

**Still true:** nothing above about 15 kHz survives. It comes from the
library, and fixing it means building it without the render pre-processor.
That was done and measured on Oct 12 2026 (the same stereo test sound, Linux:
15.0 kHz with the shipped library, 20.1 kHz without the pre-processor) and
left out: the gain is above most people's hearing, and it means building and
hosting WebRTC for every desktop platform. The copy keeps both channels: a
stereo share reached a Linux listener with each ear's tone 94 dB below the
other (earlier notes calling it mono had measured a mono sender). Web,
Android and macOS use other WebRTC builds and are not affected (not
measured).

### Receiving a call's audio — [Implemented October 2026]

**Audio this client should not hear is held, never unsubscribed.** Deafened,
nothing is heard; a stream's sound only while it is watched; a share whose
owner has left, not at all (`hearsRemoteAudio`). The rest is turned off on the
device and the server is told to stop sending it (`disable()`), but the
subscription stays (`_AudioReceptionMixin`). Only your own share is dropped,
for good. A stream's picture is still unsubscribed while unwatched, so that
adaptive streaming keeps pausing the ones on screen nobody can see.

Unsubscribing is what turned calls to static. It hands the track's slot on the
subscriber connection back to LiveKit's server, which gives the slot to the
next track to arrive, and a slot keeps the id of the track it was first made
for. Subscribing to that first track again opens a second slot under the same
id, and flutter_webrtc fits each new track's frame cryptor to the *first* slot
with the id it is handed. The other slot is left without one and plays its
frames still encrypted: loud static on the stream, then on every voice that
passes through that slot — a push-to-talk member republishes on every press —
until the call is joined again. Watching, stopping and watching again, the
join-time drop of streams nobody watched, and deafening all did that. Reported
Oct 19 2026 after watching a stream on Windows and on Linux; reproduced Oct 21
on the local stack with LiveKit's Flutter SDK and bot members in 4 of 12 runs,
and in none of 12 holding instead (`TESTING.md`). The plugin's lookup is
unchanged upstream as of Oct 21 2026, and something other than this client can
still subscribe a track again (a member's voice hidden from you and shown
again). So each audio track's arrival also checks the subscriber connection
for two receivers under one id (`_checkReceivers`, desktop and phone; the web
fits a cryptor to the receiver itself) and joins the call again if it finds
them, at most once a minute. On the local stack the shared id was there about
fifteen seconds before the static, so the rejoin usually beats it. Pictures
sharing an id are only logged: they are still unsubscribed, so it can happen
often, and it costs one picture.

### Windows turning other apps down — [Implemented October 2026]

Windows lowers every other sound while an app has playback open through the
*communications* role ("ducking": 80% by default, set in the Sound window's
Communications tab). Measured Oct 10 2026 in a Windows 11 VM: such a stream
lowered a tone by 18 dB, the same speakers opened through the console role did
nothing, and a microphone alone did nothing. People notice it on their first
call and ask why their music went quiet.

Rift does not try to stop it. The setting is Windows', for every calling app,
and only takes effect when changed in that window (`WindowsSoundSettings`).
It says what happened instead. `rust/src/ducking.rs` registers for Windows'
duck notifications (`RegisterDuckNotification`, every session) and reads the
choice from the registry (`UserDuckingPreference`). `DuckingCubit` counts the
ducks while the choice lowers others, and `DuckingHintListener` shows a toast
during a Rift call: it explains what happened, offers "Fix it" (Settings →
Voice & audio, scrolled to the section and lit up) and "Don't show again"
(`AppState.showDuckingHint`). The section shows the choice live, re-read when
the window regains focus, and draws Windows' four options with the one to pick
marked. **A change applies from the next call.** Windows keeps a duck until the
stream that caused it closes, so the section says to rejoin when the person
fixes it mid-call. With "Do nothing" set, Windows sends no duck at all.

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

**What is in it is what a log line says**, and the log is something people
send. So a line never carries a secret or anything from a sealed message — a
link preview's failure names only the host. As a safety net, every line
passes through `redact` before it is written: anything shaped like a JWT, the
word after `Bearer`, and the value of `access_token`, `apikey`, `token`,
`password` and the like become `[redacted]`. What it does carry: the version
and system, server and room ids, error text, device names, and the title of a
window being shared.

**What goes to stderr is not this log, and libwebrtc puts nothing there.** On
Linux an app started from the desktop has its stderr in the journal, readable
long after the call. The libwebrtc flutter_webrtc 1.6.2 downloads
(`m150.7871.03`) printed its INFO lines there in every build, among them the
frame cryptor's `raw_key` and `derived_key`, so each call left its channel's
key behind; `setMinDebugLogLevel` no longer reaches that setting since m150.
The desktop builds therefore take `.04`, which is silent, through the copy in
`third_party/flutter_webrtc` (its `RIFT_PATCHES.md`). Verified Oct 21 2026 on
Linux by counting those lines in a call's stderr. The web uses the browser's
WebRTC, and its encryption worker logs nothing (its logger is off and nothing
turns it on): no key lines in the page's or the worker's console, Oct 21 2026.
**Android still prints them.** Its libwebrtc is a separate build
(`io.github.webrtc-sdk:android`, still `150.7871.01`, the newest there is) with
the same m150 default, and each key set puts both lines in logcat. Nothing
outside the library can turn that off: its Java API sets only the old level,
and the new setting is not exported. Logcat is readable by the app, the system
and a computer with USB debugging (adb, a bug report), and is not kept across
a restart, so this is far narrower than the journal, but it waits on a fixed
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

---

## Speaking indicator

Encrypted frames cannot be measured by anyone without the key, but the level
travels beside them: each audio packet carries it in an RTP header extension the
frame encryption does not cover, so LiveKit's active-speaker detection works on
an encrypted call. Other people's indicators come from that. Your own is decided
on the device from the microphone's raw level, because the server reports only
the loudest few speakers on an interval and ordinary speech often never lit it.
