# BOTS.md — Bots, commands & webhooks

Design reference for third-party integrations. **Webhooks (§3, §7), bot identity (§1, §2, §9),
commands (§4), channel and ephemeral replies (§5) and the moderation grant (§6) are implemented** —
migrations 013 through 017, plus the Dart SDK (§11). Still **[Planned]**: panels (§5), the
server-wide grant and its UI (§6), and the TypeScript SDK (§11). Sections are marked as they land,
the same way `ARCHITECTURE.md` marks its own.

Read `ARCHITECTURE.md` §2 (auth) and §4 (chat encryption) first. This document assumes both, and
where it departs from them it says so.

---

## The rule this whole design exists to hold

> **A bot hears what you tell it, not what you say.**

Discord's model is the opposite: a bot joins a channel and receives every message in it. That is
the only thing it *can* do, because Discord can read every message anyway — handing a copy to a
bot costs nothing that was not already spent.

Here it would cost everything. A bot with a channel key is a permanent, machine-speed reader of a
room that was built so the server itself could not read it. So the default is that **bots never
hold channel keys**, and everything below is the machinery that makes bots useful anyway.

---

## 1. What a bot is — [Implemented]

**A bot is a user whose seed lives in a config file instead of on a phone.** There is no separate
bot API, no bot token format, no second auth path. It is the same `users` row, the same SIWS
login, the same JWT, the same RLS.

That is not a shortcut — it is what stops the bot surface drifting away from the app surface. A
capability the app has, a bot has, under the same policies.

`tool/headless_member.dart` (253 lines) is already a working proof: it joins a server, keeps its
keyring healed, and sends messages, using the app's own `CryptoRepository`.

### Adding one

Bots are added by invite, the same as people, because an invite already carries exactly the right
thing — a per-server grant of scoped permissions, revocable by the person who minted it.

```
admin creates an invite, ticks "this is for a bot"
  → pastes the link into the bot's own setup page / config
  → bot resolves the invite, does SIWS, registers
```

An invite link carries the server address and the code; `register` returns the anon key and
everything else the bot needs. So it is one paste, roughly the same effort as Discord's authorize
link.

### Identity is per server

`childSeed = HMAC(seed, "<host>:<serverId>:v1")`, unchanged. One bot deployment across N servers is
N keypairs and N sessions. Fine at a hundred servers, a fleet at a million — Discord's single
gateway wins at that scale, and that is an accepted difference rather than a problem to solve.

---

## 2. Why bots do not get channel keys — [Implemented]

Two reasons, and only the second is the real one.

**A key cannot be taken back.** RLS can be changed, tightened, audited, fixed after a mistake. A
wrapped key is arithmetic — once a bot holds it, every message under that key version is readable
by it forever, including anything it captured before someone noticed.

**"Write but not read" is not expressible with a key.** Writing into an encrypted channel requires
the channel key, and holding the key *is* read access. A policy that blocks `SELECT` looks like a
boundary and is really a promise.

Remove the encryption from the messages a bot touches and both problems dissolve. There is no key,
so "read only what is addressed to you" becomes a row-level rule — the kind of boundary the
database actually enforces.

The exception is moderation, which genuinely cannot work this way. §6.

---

## 3. Plaintext messages inside encrypted channels — [Implemented]

A bot's traffic is stored in the clear. **Not the channel — the message.** A channel does not have
a mode; individual messages do.

This matters. A CI feed belongs in `#dev` next to the conversation about the build it broke.
Forcing `#dev` to be a plaintext channel to get it there would make encryption something people
turn off for convenience, which is how it stops meaning anything.

| | Server reads | Bot reads | Members read |
|---|---|---|---|
| Normal message | no | no | yes |
| `/` command | yes | the addressed bot | yes |
| Bot reply in channel | yes | yes | yes |
| DM to a bot | no | **yes** | no |

The fourth row is the one people will get wrong. A DM to a bot is private *from the server*, not
from the bot — and an AI bot forwarding to an outside service takes it there either way. See §8.

### Storage

`key_version = 0` means "this body is not encrypted". The column already exists, every client
already branches on it, and the `CHECK (key_version >= 1)` becomes `>= 0`. Migration 013 does this,
along with four CHECKs that keep the two message shapes from blurring — `schema.md` lists them.

The `ciphertext` column then holds plain text, which makes its name a small lie. Worth a comment in
the migration rather than a second column and a two-way `CHECK` — the alternative loosens
`ciphertext NOT NULL` for every row to describe a minority of them.

**Signatures.** `ARCHITECTURE.md` §4 locks in that every message is Ed25519-signed and an
unverifiable message is never shown. That rule stays exactly as it is **for `key_version >= 1`**.

At version 0 there are two cases:

- **A bot's own message** is signed normally. It has a keypair; there is no reason not to.
- **A webhook message has no signer.** GitHub holds no Rift key. The row is attested by the server
  that accepted the POST and by nothing else.

So the client rule becomes: *a message at key_version ≥ 1 with a bad or missing signature is
dropped; a message at key_version 0 is rendered with its origin shown and never attributed to a
person.* A webhook message must be visibly a webhook message.

### In the UI

An unencrypted message is **badged**, always, with no way to turn the badge off. Whatever the
badge is, it must survive someone skimming — this is the one visual affordance the whole design
leans on.

---

## 4. Commands — [Implemented]

Two entry points, one mechanism.

**Typing `/` in the composer** is the fast path and the one people will use. The composer catches
it: `/` opens a list of the bots present and their commands, and sending writes a message tagged
for that bot.

**Right-clicking a bot in the sidebar** is the discovery path — it lists that bot's commands with
their arguments, for the person who does not yet know what exists.

Both produce the same row. Neither needs the bot online to compose.

### The composer has to say it out loud

The moment a message becomes a command, the composer changes — an open-lock marker, the word
plain, something unmissable — **before** it is sent.

`/roll 2d6` in the clear is nothing. Someone typing `/ask` and pasting something personal is a
different event, and they need to know while they can still stop.

### Only `/` is a command

A normal message that mentions a bot does **nothing**. No natural-language triggering, no
`@musicbot play x`.

Two messages that look identical must not have different protection. That is the kind of
distinction people get wrong at the worst possible moment, and the cost of the rule is that
Discord's `@bot` habit does not work here.

### Discovery

Each bot publishes a **command manifest** — name, description, arguments, and what it does with
what it is given. Plaintext, on the bot's own row; it is public information by definition.

Clients read it to fill the `/` list and the right-click menu, so neither costs a round trip to
the bot and both work while the bot is asleep.

---

## 5. Replies — [Channel + ephemeral implemented, migration 016; panels specified below, not built]

Three shapes, because bot output is three different things and Discord flattens them all into
chat messages for want of anywhere else to put them.

| Shape | Goes to | Use |
|---|---|---|
| **Channel message** | everyone, plaintext, badged | genuinely public output — a poll result, a dice roll |
| **Ephemeral reply** | only the person who asked | errors, confirmations, anything the room does not need |
| **Panel** | attached to a channel or a voice channel | living state — a music queue, a game score |

The third is the interesting one. *Now playing* is not a message; it is a piece of state that gets
edited. Discord posts it as a message every time because a message was the only surface available.
A player panel that updates in place is both better and cheaper.

### Bots do not ship their own interface

A bot describes what it wants shown — text, a button, a list, a progress bar — and **the app draws
it** with the app's own components.

The two alternatives are both bad. A web view means running a stranger's code inside the app, with
its own sandboxing story, its own security surface, and its own ideas about your theme. Arbitrary
client code is worse.

A declarative block set (Slack's Block Kit is the reference) means bots get real interfaces, the
app keeps control of how it looks, every accent palette keeps working, and phone and desktop
render identically for free.

Start with the smallest useful set and add on demand:

| Block | Draws |
|---|---|
| `heading` | a title line |
| `text` | a paragraph |
| `fields` | key/value rows |
| `progress` | a bar, `0.0`–`1.0` |
| `image` | one picture, by URL |
| `divider` | a rule |
| `actions` | a row of `button`s |
| `select` | a dropdown |

The bot sends that as JSON and the app draws each block with its own widget. The vocabulary is
fixed and versioned, because third-party bots make it public API — **anything not in the list
cannot be drawn**, which is the safety property rather than a shortcoming of the first version.

### The round trip

A panel is a message the bot keeps editing.

1. The bot posts a panel — a message row like any other, plaintext and badged, carrying blocks
   instead of a body.
2. Somebody presses a button. That writes a row addressed to the bot: the same `to_bot` path a
   command takes, carrying an `action` id instead of typed text.
3. The bot edits the panel in place.

**Step 3 already works.** `messages` has `edited_at` and `messages_update_own` lets a sender rewrite
its own envelope, so a bot editing its own panel needs no new policy. The work is the block schema,
the widgets, and the button-press row.

---

## 6. Moderation bots — the one real exception — [Grant implemented, migration 017; server-wide grant and UI planned]

A moderation bot has to read everything. There is no cryptographic middle ground: it either holds
the channel key or it does not.

So this is an **explicit, admin-only grant**, recorded in `bot_channel_keys` as
`(bot_id, channel_id, from_key_version)`. It is its own table rather than a flag on
`channel_keyring` because the grant has to outlive any one key version — it must survive the
rotations that are what make it forward-only.

Five rules make it safe enough to offer.

### Bots are excluded from the healing sweep — [Implemented as a refusal, migration 014]

`get_channel_key` returns `members_missing` — members with a published chat key and no entry at the
current version — and any member's client heals them. That is how people get keys without anyone
thinking about it.

**A bot with a published chat key would be swept up by that**, handed the key to every channel by
a helpful client, silently. The `members_missing` query must exclude bots, and a bot must only ever
be wrapped by an explicit grant.

This is the single implementation detail that, missed, undoes the entire document.

### Forward-only

Members get every historical key version — that is the full-scrollback decision in
`ARCHITECTURE.md` §4. A bot's grant records `from_key_version` as **one past the current one**, and
granting is itself a rotation signal: the next version is the first the bot can ever hold. It reads
nothing said before somebody chose to let it listen, and *we will rotate later* is not the same
promise.

### Revoking rotates

Revoking rotates the channel key, exactly as kicking a member does. The bot keeps what it already
saw — nobody can take back what has been unwrapped — and gets nothing further.

Both signals are shaped so they **clear themselves**: a granted bot whose grant starts above the
current version, and a revoked bot still sealed into the current one. The rotation makes each check
false again, so there is no flag to set, and an admin who grants and revokes twice in a minute
leaves nothing behind to reconcile.

### The channel says who is listening

The admin grants; **every member's future messages pay for it**. The people bearing the cost are
not the ones who clicked the button, so a warning in the admin's dialog reaches the wrong audience.

If a bot holds a key to a channel, the channel shows it — a standing marker in the header, like a
recording light, visible to everyone in the room. Not a one-time dialog.

A community-run bot on the operator's own machine and a public bot on a stranger's server are very
different grants. Those two cases should not look the same when you are clicking the button.

Three things carry the notice, not one:

- **A standing marker in the channel header**, for people who arrive later. Like a recording light:
  on for exactly as long as it is true, and not dismissible.
- **A system message in the channel** when the grant is made, for people already in the room. A
  header marker is easy to have never noticed; a line in the scrollback is not.
- **The bot's profile lists every channel it can read**, so *what does this thing see?* has one
  place to be answered instead of being discovered a channel at a time.

Granting is **admin-only**. Channel managers run their channels but do not hand out keys. And DMs
are never grantable — no path, no exception, no flag to get wrong.

### Private channels are never granted in bulk

Per-channel is the honest granularity and it is also unusable for the bots people actually want.
By server count the top of Discord's list is almost entirely the read-everything kind: MEE6
(~21M servers, XP per message), Carl-bot and Dyno (automod, logging), Pokétwo (spawns on chat
activity). An admin granting one of those a channel at a time, thirty times, will ask for a button.
Refusing to build it does not stop the button existing; it means the one somebody eventually builds
gets no thought.

So there is a **server-wide grant**, and one carve-out is what keeps it honest: it covers every
channel where `is_private` is false, and **never a private one**. A private channel is always an
explicit, individual decision.

`channels.is_private` therefore exists from the start, defaulting to false, **written before
private channels are built**. Today it excludes nothing. The alternative is a rule that lives in
somebody's head until the day private channels ship, and rules that live in heads are the ones that
ship without.

The server-wide grant is stored as intent, not as a snapshot:

- **A row in `bot_server_grants`** is what covers a channel created *next week*. Without it an
  admin grants a bot the server, adds a channel, and the bot silently does not work there.
- **Per-channel rows materialised from it** are the mechanism — they carry `from_key_version`,
  drive the rotation sweep, and drive the header marker. A new public channel materialises one; a
  new private channel does not.

**Revoking one channel out of a server-wide grant downgrades it to explicit rows:** materialise all
of them, drop the one. An exception list would also work, and would leave somebody a year later
asking why one channel is not covered by a grant that says *whole server*.

### What metadata-only moderation can still do

Most of what actually damages a server: posting rate, raid detection, mass-mention spam, brand-new
accounts posting immediately, join patterns. None of that needs plaintext.

What it cannot do is content — slurs, scam links, images. For that, the answer is the reader:
client-side checks on what has just been decrypted, plus user reports. `ARCHITECTURE.md` §4 already
says *automod is metadata-only*; this is that decision arriving.

---

## 7. Webhooks — [Implemented]

An incoming webhook is a URL an outside service POSTs to, which appears as a message. **No login,
no keypair, no running program.**

That last part is the whole point and a bot cannot replace it. GitHub is never going to implement
Rift's login, and a community should not have to run a process to receive build notifications.

Encryption was what made this hard. With plaintext bot messages it is small:

```
POST https://<server>/functions/v1/webhook/<secret>
  → look up the secret, find its channel
  → insert a key_version 0 message, attributed to the webhook
```

| Field | Note |
|---|---|
| `id`, `server_id`, `channel_id` | one webhook posts to one channel |
| `created_by` | who minted it, so it can be managed under RLS like an invite |
| `secret_hash` | the URL is the credential; store a hash, show the URL once |
| `name`, `avatar` | how it appears — never a person's name |
| `last_used_at` | so a dead integration is visible |

Rate-limited per webhook, because the credential is a URL and a URL leaks.

An edge function rather than PostgREST: it runs before any caller is authenticated, which is the
same reason `resolve_invite` and `register` are functions.

---

## 8. Telling people what a bot does

The strongest protection here is not cryptographic.

A bot declares what it does with what it is handed — *"messages you send this bot are forwarded to
an outside service"* — and that declaration is shown **at invite time and in its sidebar entry**,
the way phone apps declare permissions.

For an AI bot, that sentence is worth more than any amount of key management. The bot reads the
message either way; what the user needs is to know it before typing.

---

## 9. Where bots live in the UI — [Implemented]

A **separate section in the right sidebar, above people.**

Not decoration. A bot is not a member the way a person is — different trust, different
capabilities, different consequences for talking to it. Discord blurs that by listing bots among
members with a small tag; the separation should be structural.

Right-clicking one gives its commands, what it does with data, and (for admins) its channel
grants.

---

## 10. Schema sketch

Nothing here is final; it is the shape the sections above imply.

| Change | Why |
|---|---|
| `users.is_bot BOOLEAN NOT NULL DEFAULT false` | the type distinction, and the sweep exclusion in §6 |
| `users.manifest JSONB` | published command list + data declaration (§4, §8) |
| `invites.is_bot BOOLEAN NOT NULL DEFAULT false` | chosen when the invite is minted |
| `messages.key_version CHECK (>= 0)` | 0 means the body is not encrypted (§3) |
| `messages.to_bot UUID REFERENCES users(id)` | which bot a command is addressed to |
| `messages.webhook_id UUID` | origin for an unsigned row (§3) |
| `webhooks` table | §7 |
| `bot_channel_keys` table | the §6 grant: `(bot_id, channel_id, from_key_version)`, admin-gated |
| `bot_server_grants` table | a server-wide grant held as intent, materialised per public channel |
| `channels.is_private BOOLEAN NOT NULL DEFAULT false` | written before private channels exist, so the bulk carve-out cannot be forgotten |
| `messages.blocks JSONB` | a panel's body (§5); button presses come back through `to_bot` |

**The policy that carries the design:** a bot may `SELECT` a message only where
`to_bot = auth.uid()`, or where it is the sender, or where it holds a keyring entry for that
channel. Nothing else. That single rule is what "hears what you tell it" reduces to.

---

## 11. The SDK — [Dart implemented and text-only, `bot_sdk/`; TypeScript is the reference]

- Derive an identity from a seed, SIWS login, keep the session refreshed
- Join from an invite link
- Subscribe to commands addressed to it, and to its DMs
- Reply — channel, ephemeral, or panel
- Publish a manifest
- Publish audio into a voice channel (LiveKit; no crypto involved)

### The contract comes before the second implementation

A bot needs four primitives and no more: HMAC-SHA256 for the seed ladder, an Ed25519 keypair from
that seed, an Ed25519 signature, and base64. **No X25519, no AES-GCM, no Argon2id** — a bot never
holds a channel key, so it never opens anything. That is a couple of hundred lines in any language,
and all four are standard library everywhere.

Which makes the SDK the cheap half and the *format* the expensive one. Two implementations of
`chatmsg:v1:…` are two things that can disagree, and the disagreement does not look like an error:
the message stores fine, verifies as false, and renders as nothing.

So before there is a second SDK there is a **spec plus test vectors** — a fixed
`(seed, host, serverId)` with its expected public key, a fixed `(text, contextId)` with its expected
signature, in a JSON file any implementation proves itself against in one test. That is what makes
*an SDK in every language* safe to want, and it is a day of work rather than a policy.

### Why TypeScript is the reference

Dart came first because it could share `CryptoRepository` directly, and it proved the rest of the
design end to end. It cannot be the reference, for one hard reason: **it cannot publish audio.** The
only Dart LiveKit client needs Flutter and `flutter_webrtc`, so a headless Dart bot cannot join a
call — and music is the bot people ask for first.

- `@livekit/rtc-node` is a genuine headless client: it publishes and subscribes.
- Bot authors are, overwhelmingly, the discord.js population.
- The edge functions are already TypeScript, so wire types are shared rather than mirrored.

**Nothing on the Rift side blocks voice.** `get_channel_token` does not special-case bots — a bot
gets a `canPublish` token like anyone else — and `voice_roster` reads participants from LiveKit by
identity and never asks what they are. A bot in a call is a `users` row, so a mod can mute or
disconnect it with the tools that already exist. The gap was Dart's, not Rift's.

Python comes second, and only because LiveKit Agents is Python-first: an AI that listens and talks
in a voice channel is a different ecosystem, not a different opinion. Anything after that is a
community port, and the vectors are what make one trustworthy.

---

## 12. Accepted limitations

Documented honestly, not to be "fixed":

- **A bot cannot react to conversation.** No message that triggers on a keyword, no automatic link
  previews. Link previews are already a client-side job (`ARCHITECTURE.md` §4).
- **Content moderation needs an explicit key grant** or it does not happen.
- **Discovery is worse than Discord's.** Nobody learns a bot exists from watching it talk in a
  channel. `/` completion and the sidebar section are what recover that, which makes them part of
  the feature rather than polish on top of it.
- **A bot puts load on the community's server.** Realtime's default budget is ~100 events/second
  tenant-wide, counted as deliveries. On Discord a bot costs the community nothing; here it does.
- **Central has no bots.** Friend-gated, quota'd, 30-day TTL — that tier is first contact. Bots are
  a self-hosted feature, which matches the funnel/home split.
- **The bots people actually use want the §6 grant.** The read-everything shape is most of the top
  of Discord's list, so on a server running one the amber marker is the normal state rather than
  the exception. That is the honest price of hosting the category at all. The alternative is not a
  safer Rift; it is no leveling bot, ever, and a community that goes back to Discord for one.

---

## 13. Build order

**Webhooks first — done.** `key_version 0` + the badge + one edge function + a management UI.
It was the whole plaintext-message path, proven end to end, with no bot in sight — and it turned up
two bugs that the bot work would otherwise have inherited: the push trigger going silent against a
NULL sender, and the chat list grouping two different webhooks under one name and therefore one
badge. Both are fixed; both have tests.

**Then bots**, in this order:

1. ~~`is_bot`, bot invites, the sidebar section — a bot that exists and does nothing~~ **done**
   (migration 014). The sweep exclusion landed as a *refusal on the row* rather than only a
   filter in the three edge functions that walk the member list: filters are the half that gets
   forgotten, and the fourth thing to read `users` will not know it was supposed to have one.
2. ~~Commands: `to_bot`, `/` completion, the right-click menu, the composer marker~~ **done**
   (migration 015), except the right-click menu — the `/` list covers discovery for now and the
   sidebar entry is the next cheap win. One thing the design did not anticipate: a command is
   *signed* though not sealed, and the read path verifies it. A webhook's message cannot be
   verified and is never shown as a person; a command is attributed to one, so it has to be.
3. ~~Replies: channel message, then ephemeral~~ **done** (migration 016). Panels still planned.
4. ~~The Dart SDK, extracted from what the first three needed~~ **done** (`bot_sdk/`). Polls rather than subscribing: no reconnect logic to get wrong, and nothing spent from the server-wide event budget. Realtime, voice and DMs are listed in its README as not-yet.
5. ~~Moderation grants~~ **done** (migration 017). All four rules are enforced where the row is, not by clients agreeing: the refusal, forward-only, revoke-rotates, and the standing marker every member can see. What is *not* done is anything that calls them — `grant_bot_channel_key` and `revoke_bot_channel_key` appear only in the migration, so today an admin grants by writing SQL.

**Then, in this order.** Private channels come first, and not because bots need them — they are a
feature in their own right. But the server-wide grant in §6 is *defined* as "not private", and
building the carve-out before the thing it carves out means writing it once instead of remembering
to come back.

6. ~~Private text and voice channels~~ **server side done** (migrations 018, 020, 021). Granular
   permissions came with them rather than after: private channels need *who may create one* and
   *who may add members*, and building those against three booleans would have been doing the work
   twice. `get_channel_token` now checks membership, which it never did — harmless while every
   channel was public, a hole the moment one is not. The app has no UI for any of it yet.
7. ~~The wire spec and test vectors~~ **done** — `WIRE.md`, `test/wire_vectors.json` and
   `test/wire_test.dart`. The vectors were generated from the Dart implementation, so they catch
   *drift*, not original error: they cannot say the format was right the day it was written, only
   that it has not moved and that a second implementation agrees with the first — which is the
   failure that actually happens. Red-checked by changing the payload separator and the identity
   scope string; each is caught, and by nothing else in the suite, because everything else signs
   and verifies with the same changed code and agrees with itself.
8. ~~Panels~~ **done** (migration 029). Seven block types, `Bot.panel` / `Bot.editPanel`, and a
   press that is deliberately *not* a message: `is_interaction` keeps the row out of every view but
   the presser's and the bot's, wakes nobody's phone, and does not count as unread — so pressing
   skip forty times leaves the channel looking exactly as it did.

   `image` is not in v1, and that is a decision rather than an omission: a URL a bot chose makes
   every member's client fetch from it, which hands a third party the IP of everybody in the room
   and a per-member read receipt. It comes back pointing at this server's own attachment bucket.

   Two things found by pressing the button. A panel redraw rang `new_message`, which makes a client
   fetch what is *newer* than it has — and a panel being redrawn is not newer than anything, so it
   silently kept showing the state it had when the channel was opened. And the press rendered as a
   message to the person who pressed it: the policy hid it from everybody else, and "everybody
   else" was the wrong set.
9. ~~The grant UI~~ **done** (migrations 028, 030). "Bots reading this" on a text channel's menu, a
   confirm that says what a key costs before it is handed over, and the system message rule 4 asked
   for — which needed a `messages.is_system` column, because a system message and a webhook's are
   the same shape and badging one WEBHOOK says an integration somebody installed is involved when
   nothing outside the server is. The grant also moved from `app.is_admin()` to `MANAGE_BOTS`, and
   from "is this channel on my server" to `app.can_see_channel` — an administrator standing outside
   a private channel was able to key a bot into it.

   The server-wide grant landed in 030 with the `is_private` carve-out intact, and one thing the
   design had not anticipated: the downgrade cannot be a trigger on `bot_channel_keys`. Every
   deletion of that row looks the same to a trigger, and only one of them is somebody deciding — so
   closing a channel, which drops the bot's row for it, would have cancelled the grant on all the
   others. It lives in `revoke_bot_channel_key` instead. Red-checked by putting the trigger back.

   The bot's own page answers "what does this thing see?" in one place: the server-wide toggle and
   every channel it holds a key to. Before it, that was discoverable a channel at a time, which is
   not an answer somebody can act on.
10. ~~The TypeScript SDK~~ **done** (`bot_sdk_ts/`) — auth, commands, replies and panels. No build
    step and no dependencies: Node runs TypeScript by stripping types, and the four primitives a
    bot needs are all in `node:crypto`. It proves itself against `test/wire_vectors.json`, the same
    file the Dart implementation is checked against, reproducing one of its signatures byte for
    byte — which is the whole reason item 7 came first.

    Voice is still not wrapped, and the reason is now a choice rather than a limitation: a bot can
    already get a LiveKit token, and the media itself belongs to `@livekit/rtc-node` rather than to
    this package. A text bot should not pay for a media dependency it never loads.

    Found by running it: both SDKs delivered the same message twice under load. `setInterval` and
    `Timer.periodic` do not wait for the previous callback, so a slow handler lets two ticks run
    the same query before either advances the cursor. One press counted as two votes. Both are
    guarded now.

Games are not on this list. Discord's run in a browser already, Linux desktop has no usable web
view, and the sandboxing is a project of its own.
