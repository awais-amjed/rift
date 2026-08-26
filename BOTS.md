# BOTS.md — Bots, commands & webhooks

Design reference for third-party integrations. **Webhooks (§3, §7) and bot identity (§1, §2, §9)
are implemented** — migrations 013 and 014. Commands, replies, the SDK and moderation grants are
still **[Planned]**. Sections are marked as they land, the same way `ARCHITECTURE.md` marks its
own.

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

## 4. Commands

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

## 5. Replies

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

Start with the smallest useful set — text, key/value rows, buttons, a list, an image. Add on
demand.

---

## 6. Moderation bots — the one real exception

A moderation bot has to read everything. There is no cryptographic middle ground: it either holds
the channel key or it does not.

So this is an **explicit, per-channel grant**, and it needs no new tables — `channel_keyring` is
already keyed on `(channel_id, key_version, user_id)`. Granting one channel and not another is
already expressible.

Four rules make it safe enough to offer.

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
`ARCHITECTURE.md` §4. A bot gets the **current version only**. It has no business reading what was
said before it arrived, and the difference costs one `WHERE`.

### Removal rotates

Removing a keyed bot rotates the channel key, exactly as kicking a member does. It keeps what it
already saw and gets nothing further. This works today with no new code.

### The channel says who is listening

The admin grants; **every member's future messages pay for it**. The people bearing the cost are
not the ones who clicked the button, so a warning in the admin's dialog reaches the wrong audience.

If a bot holds a key to a channel, the channel shows it — a standing marker in the header, like a
recording light, visible to everyone in the room. Not a one-time dialog.

A community-run bot on the operator's own machine and a public bot on a stranger's server are very
different grants. Those two cases should not look the same when you are clicking the button.

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
| `grant_channel_key(bot, channel)` RPC | the only path to §6; forward-only, admin-gated |

**The policy that carries the design:** a bot may `SELECT` a message only where
`to_bot = auth.uid()`, or where it is the sender, or where it holds a keyring entry for that
channel. Nothing else. That single rule is what "hears what you tell it" reduces to.

---

## 11. The SDK

Small on purpose. Everything below already exists inside the app; the SDK is that code with the
Flutter taken out.

- Derive an identity from a seed, SIWS login, keep the session refreshed
- Join from an invite link
- Subscribe to commands addressed to it, and to its DMs
- Reply — channel, ephemeral, or panel
- Publish a manifest
- Optionally: publish audio into a voice channel (LiveKit; no crypto involved)

Dart first, since it can share `CryptoRepository` directly and `tool/headless_member.dart` is
already most of it. A second language only once the wire format is a stable, documented contract —
`chatmsg:v1:…`, `wrap:v1`, the `rift.msg` body. **Third-party bots make that format public API**,
and it should be written down before anyone depends on it.

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
2. Commands: `to_bot`, `/` completion, the right-click menu, the composer marker
3. Replies: channel message, then ephemeral, then panels
4. The Dart SDK, extracted from what the first three needed
5. Moderation grants — last, deliberately, because it is the only part that spends the trust model

Games are not on this list. Discord's run in a browser already, Linux desktop has no usable web
view, and the sandboxing is a project of its own.
