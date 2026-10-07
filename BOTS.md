# BOTS.md — Bots, commands & webhooks

Design reference for third-party integrations. **Everything here is implemented** — the bot
itself, panels, the grants and encrypted voice, plus the SDK (§10). What is left is in §11 and in
the SDK's README, and it is choices rather than a backlog: attachments, joining from an invite
link, and an `image` block that points at this server's own bucket. A bot reads over realtime — it
is told what it may hear on its own topic, and polls slowly behind that as a backstop.
Sections are marked as they land, the same way `ARCHITECTURE.md` marks its own.

The schema lives in `rift-self-host/migrations`, split by kind — tables, helpers, RPCs, triggers,
realtime, security — so a rule here is named by the table, policy or function that holds it rather
than by a file.

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

A headless member written against the app's own `CryptoRepository` was the working proof: it
joined a server, kept its keyring healed, and sent messages.

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
already branches on it, and the `CHECK (key_version >= 1)` becomes `>= 0`. `messages` in `001_schema.sql` carries this,
along with four CHECKs that keep the two message shapes from blurring.

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

So the composer never teaches it. `Mentions.among` drops bots from the `@` menu, from the names
that light up in a sent message, and from the roster a send resolves against — the same list, so
the surfaces cannot disagree. A menu offering a bot would be a promise the `messages_select`
policy then refuses in silence: the mention would be stored in the clear and wake nobody. `/` is
one key away and has its own menu.

### And `/` only reaches a bot that can see the channel

`messages_select` asks `app.can_see_channel` **before** it asks `to_bot`. In a public channel that
is always true, so any bot on the server can be addressed. In a private one it is true only for a
bot a role let in — `set_channel_members` refuses to seat one by name, so `channel_role_access` is
the only door.

Address a bot outside the room and the command is written, in the clear, to be read by nobody who
wanted it: the worst of both halves. `ChannelReach.botsIn` narrows the `/` menu, the unencrypted
warning and the send path to the bots this channel's audience actually contains, and an empty list
turns `/` handling off entirely. `BotCommands.parse` then returns null, so the line goes out
**sealed** like any other message rather than as plaintext addressed to nobody. A slash that
reaches no bot is just a slash.

### Discovery

Each bot publishes a **command manifest** — name, description, arguments, and what it does with
what it is given. Plaintext, on the bot's own row; it is public information by definition.

Clients read it to fill the `/` list and the right-click menu, so neither costs a round trip to
the bot and both work while the bot is asleep. A bot that publishes a new one rings `bots` on the
server's topic, and an open channel reads the lists again — so a verb added while somebody is
reading goes out as a command, not as sealed text the bot cannot open.

A command's `usage` (`<url>`, `<user> [reason]`) is also how the composer knows whether it takes
arguments. With the list open, Enter on a verb typed in full that has no `usage` sends it at once;
one with a `usage`, or a half-typed verb, is completed and waits for the rest. A bot that takes
arguments but declares no `usage` gets sent the bare verb.

---

## 5. Replies — [Implemented]

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
| `divider` | a rule |
| `actions` | a row of `button`s |
| `select` | a dropdown |

The bot sends that as JSON and the app draws each block with its own widget. The vocabulary is
fixed and versioned, because third-party bots make it public API — **anything not in the list
cannot be drawn**, which is the safety property rather than a shortcoming of the first version.
`WIRE.md` §5 freezes the seven, field by field.

**There is no `image` block, and that is a decision rather than an omission.** A URL a bot chose
makes every member's client fetch from it, which hands a third party the IP address of everybody
in the room and a per-member read receipt. It comes back when it can point at the server's own
attachment bucket.

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

## 6. Moderation bots — the one real exception — [Implemented]

A moderation bot has to read everything. There is no cryptographic middle ground: it either holds
the channel key or it does not.

So this is an **explicit, admin-only grant**, recorded in `bot_channel_keys` as
`(bot_id, channel_id, from_key_version)`. It is its own table rather than a flag on
`channel_keyring` because the grant has to outlive any one key version — it must survive the
rotations that are what make it forward-only.

Five rules make it safe enough to offer.

### Bots are excluded from the healing sweep — [Implemented as a refusal, `refuse_ineligible_keyring`]

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

Revoking rotates the channel key, exactly as kicking a member does: within the hour, since
removals share one key change an hour (`ARCHITECTURE.md` §4). The server stops serving the bot
at once. The bot keeps what it already saw — nobody can take back what has been unwrapped — and
gets nothing further.

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

### Reading it — [the `messages_select` policy, and `ChannelReader` in the SDK]

Everything above is about the **key**. None of it is what lets a bot read a message, and for a
long time nothing did: `messages_select` restricted every bot to what it was addressed and what it
wrote, from the day bots arrived, and the grant never touched that line. A fully granted bot, in a public
channel, holding the channel key, got zero rows — while `grant_bot_channel_key` posted *"It can
read every message sent here from now on"* into the channel. The grant machinery was complete and
the feature did nothing.

The policy now has the clause, and makes the boundary the same number in both directions:

```sql
AND (NOT app.is_bot()
     OR to_bot = auth.uid()
     OR sender_id = auth.uid()
     OR app.bot_reads_version(channel_id, key_version))
```

`from_key_version` is what `refuse_ineligible_keyring` already enforces on the way in, so
forward-only stopped being a policy promise on one side and arithmetic on the other. Revoking
deletes the grant row and the bot's keyring rows, so it stops reading in the same statement —
*it keeps what it already saw* is about what has been unwrapped, not a database it still queries.

**A granted bot still does not see** anything below `from_key_version`; anything with
`key_version` 0 — webhook posts, system notices, and commands addressed to *other* bots, none of
them ever sealed, and the third is the reason to be strict rather than generous; somebody else's
ephemeral reply; or another bot's button press. The last two clauses were already there and are
untouched.

**A private channel can be granted** — it is the *bulk* grant that never covers one. That was
doubly inert before: `can_see_channel` asks about membership and `set_channel_members` will not
seat a bot, so the grant bought neither the messages nor the bot's own wrapped key. Both now admit
a granted bot, scoped to its own rows. It reads without becoming a member, which means it also
**cannot speak there** — posting needs `can_see_channel`. Getting in far enough to speak is a role
with `channel_role_access`, the same door a `/` command comes through.

On the SDK side `bot.watchChannel(channelId, handler)` is the whole of it. It returns the grant's
`from_key_version`, or **null when there is no grant** — worth handling, because an ungranted bot
polls forever and receives nothing, which looks exactly like a quiet channel. It reads the bot's
own `channel_keyring` rows, unwraps them with `wrap:v1`, verifies every signature before handing
anything over, and **stops rather than skips** at a version whose key has not been sealed yet: a
rotation is sealed by the next member to open the channel, so a cursor that jumped the gap would
drop precisely the stretch a moderation bot was granted to see.

### Summoning one into a call — [`bot_voice_summons`]

The thing people most want a bot for, and it did not work in a private voice channel at all. Two
walls, both keyed on `channel_members`, which `set_channel_members` refuses to seat a bot into:
`channel_visible_to` said no, so `get_channel_token` answered `CHANNEL_NOT_FOUND`; and
`bot_voice_key_candidates` said no, so no member's client sealed it a media key and there was
nothing for it to speak with.

A **summon** is the third door and deliberately the smallest: one voice channel, publishing only,
until somebody dismisses it. `bot_voice_summons` is the row; `channel_joinable_by` is the only
thing that reads it, and only `get_channel_token` asks that — so a summoned bot still cannot list
the channel, read its roster, read its messages, or post in it. `app.sees_channel` is untouched.

That is what lets `SUMMON_BOTS` sit on `@everyone` (§036). A summoned bot's token carries
`canSubscribe: false` unless an admin separately granted listening, and its media key is
`HMAC(channelKey, 'voicebot:v1:<botId>')` — derived *from* the channel key rather than being it. A
summon adds a **speaker** to the room. It cannot be turned into a listener from there.

Dismissing deletes the summon and the media key in the same statement, the same shape as revoking a
listening grant. And the candidates view got narrower on the way: a summon is now what puts a bot
on the sealing list, so members' clients stop sealing media keys for bots that will never join.

**Dismissing disconnects.** Deleting the row takes away the media key and the right to a *new*
token, and does nothing to the connection the bot already holds, which is good for its hour — so
"Send away" removed the row, the client said the bot would leave, and the bot stayed in the call
playing music. `set_bot_voice_summon` pushes `removeParticipant` for the one channel, the same
shape and the same reason as `set_bot_voice_listen`'s push. Summoning pushes nothing: there is no
connection yet, and what brings it in is the command message itself, which the database announces
to the bot the moment it is written.

**A summon ends when its reason does** (`channels_drop_bot_voice_summons`). Closing a channel drops its summons, the
same as it does for listening grants — without it a bot called into a public call could still take
a token after the channel was closed. And an hour of nobody answering one drops it too: a summon is
a request to come and play *now*, and one left behind by a bot that was down would otherwise wait
for the next member to seal it a key and then turn up in a conversation nobody invited it to. The
sidebar draws the ones that have not arrived, from `voice_summons`, because "Send away" needs a bot
to be in the call and a summon that nothing answered would otherwise be invisible.

**A bot always encrypts in slot 0**, whatever version its media key is. Not a choice: a LiveKit
frame cryptor is created when its track is published and keeps the index it was born with, and
`@livekit/rtc-node` cannot move one — `FrameCryptor.setKeyIndex` builds an FFI request missing a
`track_sid` the native side requires, and throws. So the members read a bot's key from slot 0
(`livekit_e2ee.dart`) rather than from its version's slot. It costs nothing — the slot is only an
agreement about where to look, and the key at it is still per-bot and per-version — except across a
rotation, where slot 0 is overwritten rather than added beside and the frames in flight under the
old key are lost. That is the beat of silence already recorded above.

Getting this wrong looked like nothing at all: the bot published happily, its own log said it was
fine, and every member's client reported `FrameCryptorStateMissingKey` about a participant it could
see.

**How the bot learns where to go.** A command's manifest entry may carry `summon: true`, and its
mirror is `dismiss: true`. **Rift knows no verb names** — `/play` is not special and neither is
`/disconnect`. The bot's author says which of its commands mean *bring me in* and which mean *send
me out*, and a bot that marks neither is simply never summoned by typing.

Two flags rather than one because a command asks a bot in, or out, or neither, and most are
neither. Stopping whatever the bot is *doing* is the third thing and needs no flag at all: a
`/stop` that ends the track and stays for the next one is an ordinary command, and running it
together with leaving is the mistake — somebody who wanted quiet for a minute should not have to
summon the bot back.

The dismissal is acted on by the **client**, which is what makes it a backstop rather than a
courtesy: a bot that crashed mid-track, or one that ignores the verb it advertised, still loses its
media key and its connection. It lands *after* the message, so a bot that is running still gets its
chance to edit the panel and say it stopped. When somebody sends one of those from inside a call, their client writes the
summon alongside the message, and the bot reads its own rows (`bot.summons()`). It is the only
source that works for a private channel, where the roster cannot help because the bot cannot see it.
The flag is advertisement like the rest of the manifest: the summon is checked against
`SUMMON_BOTS` and is publish-only regardless, so a bot that lies about it gains a speaker's seat and
nothing else.

### What metadata-only moderation can still do

Most of what actually damages a server: posting rate, raid detection, mass-mention spam, brand-new
accounts posting immediately, join patterns. None of that needs plaintext.

What it cannot do is content — slurs, scam links, images. For that, the answer is the reader:
client-side checks on what has just been decrypted, plus user reports. `ARCHITECTURE.md` §4 already
says *automod is metadata-only*; this is that decision arriving.

---

## 6b. What a bot may hear in a call — [Implemented]

The rule at the top of this document was false in exactly one place, and it took
building the SDK's voice support to notice.

`get_channel_token` never asked what the caller was. `@everyone` carries
`CONNECT` and `SPEAK`, a bot holds `@everyone` like anybody else, and the token
was minted with `canSubscribe`. So any bot invited to a server could sit in a
call and receive every participant's audio, indefinitely, with nothing said in
any channel and nothing shown to anyone in the room.

Nobody built that on purpose. It is what happens when a rule is enforced in the
text path and the voice path is written by asking *what does a member need*.

### Publishing is not hearing — and encryption almost took that away

**A bot's token is minted with `canSubscribe: false`.** It can play into a call
and receives nothing back.

That was the whole mechanism for about an hour. Then voice became end-to-end
encrypted (`ARCHITECTURE.md` §5), and §2 arrived in the middle of a call: a bot
has to *encrypt* to be audible, the key that encrypts also decrypts, and with
one key per room "speaks but does not listen" stops being expressible. A music
bot would have had to be handed the ability to hear every word in the room.

So the two directions get different keys:

```
memberKey = channelKey
botKey    = HMAC-SHA256(channelKey, "voicebot:v1:<botId>")
```

Every member holds `channelKey`, derives `botKey`, and hears the bot. The bot is
sealed only `botKey` — by a member, since only somebody holding `channelKey`
can produce one — and HMAC does not run backwards. It cannot reach the channel
key, and two bots in one call cannot decrypt each other either.

This is the shape §2 says a key cannot have, and it is bought by giving the two
directions different keys rather than by trusting anyone. It is also why the
room runs in LiveKit's per-participant key mode instead of its simpler
shared-key mode: shared-key would put every participant on one key and take the
property away.

A bot with no key is refused a token rather than joined. A participant
publishing with `encryptionType: kNone` is one every member's client skips the
frame cryptor for — its audio would arrive in the clear, inside the room built
so that could not happen.

That is affordable precisely because of which bot people ask for first: a music
bot only ever publishes. It needs no grant and notices no difference. What
genuinely needs to hear — transcription, an AI that answers out loud, a recorder
— gets an explicit grant, one voice channel at a time, gated on `MANAGE_BOTS`
and on being able to see the channel.

A bot is also never `roomAdmin`, which it could previously become by holding a
moderator role for text reasons. Muting and removing people in a call is not
something to acquire as a side effect.

### Letting a bot listen is a key grant, like §6's

When this section was first written, voice was not encrypted, and it said the
listening grant was revocable in a way §6's key grant is not: subscription was a
permission, so revoking pushed `canSubscribe: false` onto the live connection
and the audio stopped mid-call.

**That is no longer the whole truth.** A bot that may hear needs `channelKey`
itself — there is no third thing to give it — so it is sealed the real key, and
a key that has been handed over cannot be taken back. Revoking now means what it
means in §6: rotate forward, and the bot keeps everything it already heard.

The live push still happens and is still worth doing — a token is good for its
hour no matter what the table says, which is why the grant is an edge function
rather than an RPC, the same lesson `moderate_user` learned about mutes. It just
is not the whole story any more, and the confirm dialog says so.

What is genuinely free is the other case, and it is the common one: **a music
bot needs no grant at all.** Speaking was never the half that had to be allowed.

### The room still says so

Rule 4 applies unchanged: the admin decides, and everybody who speaks in that
room pays for it. Two of the three carriers work here —

- **A standing marker on the channel**, on the sidebar tile at every size,
  including the plain row an empty voice channel gets. An empty channel is
  exactly the one nobody is looking at, and a marker that appears only once a
  call starts is one you notice after speaking rather than before.
- **The bot's own page**, which lists what it reads and what it hears as two
  separate lists, because they are two grants with two different consequences.

The third — a system message in the channel — has nowhere to go: a voice channel
holds no messages. It carries the columns and ignores them (§3).

### No server-wide form

§6 has a bulk grant because thirty channels one at a time produces a button
somebody else builds without thinking. That argument does not carry here. There
is no MEE6 of voice, listening to a room full of people is a larger decision than
reading a text channel, and *every call on this server, plus the ones made
later* is not a thing anybody should be able to click once. Per channel is the
only form.

A channel made private drops its listeners, the same re-decision the server makes for
text keys: whoever allowed this was looking at a room the whole server could walk
into.

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

## 10. The SDK — [Implemented, `rift-bot-sdk` repo]

Everything in this document that a bot has to *do* is in that package: identity
from a seed, SIWS login, joining from an invite link, commands, replies, panels,
DMs, publishing audio, and reading a channel it was granted. Its README is the
reference; what follows is why it exists in the shape it does.

### The contract comes before the second implementation

A text bot needs four primitives and no more: HMAC-SHA256 for the seed ladder, an Ed25519 keypair
from that seed, an Ed25519 signature, and base64. **No Argon2id ever** — a bot never holds a vault.
That is a couple of hundred lines in any language, and all four are standard library everywhere.

Voice adds two, and only two: X25519 and AES-GCM, to open the one thing a bot is ever sealed — its
own media key for an encrypted call (§6b). It still never holds a channel key. Both are standard
library too, and the whole of it is one file in each SDK.

Which makes the SDK the cheap half and the *format* the expensive one. Two implementations of
`chatmsg:v1:…` are two things that can disagree, and the disagreement does not look like an error:
the message stores fine, verifies as false, and renders as nothing.

So before there is a second SDK there is a **spec plus test vectors** — a fixed
`(seed, host, serverId)` with its expected public key, a fixed `(text, contextId)` with its expected
signature, in a JSON file any implementation proves itself against in one test. That is what makes
*an SDK in every language* safe to want, and it is a day of work rather than a policy.

### Why TypeScript, and why there is only one SDK

There was a Dart one first. It could share `CryptoRepository` directly, and it proved the rest of
this document end to end before any of it existed in another language. It is **deleted**, and the
reason is not that it stopped working:

- **It cannot publish audio.** The only Dart LiveKit client needs Flutter and `flutter_webrtc`, so a
  headless Dart bot cannot join a call — and music is the bot people ask for first. That gap was
  Dart's, not Rift's: `get_channel_token` never special-cased bots, and `voice_roster` reads
  participants by identity without asking what they are.
- **Everything after voice landed in TypeScript only**, so it fell a feature behind per session and
  the two READMEs started disagreeing about what a bot can do.
- Bot authors are, overwhelmingly, the discord.js population, and the edge functions are already
  TypeScript, so wire types are shared rather than mirrored.

Two SDKs at different depths is worse than one: it reads as a choice when it is really a trap. A
second implementation is still worth having — it is the only thing that makes "they agree" mean
anything — but the one that matters is the **app**, which is Dart, generates
`test/wire_vectors.json`, and is held to it by `test/wire_test.dart`. The SDK proves itself
against the same file. Nothing is lost by the deletion except a second copy of the easy half.

Python comes next if anything does, and only because LiveKit Agents is Python-first: an AI that
listens and talks in a voice channel is a different ecosystem, not a different opinion. The vectors
are what would make a community port trustworthy.

---

## 11. Accepted limitations

Documented honestly, not to be "fixed":

- **A bot cannot react to conversation.** No message that triggers on a keyword, no automatic link
  previews. Link previews are already a client-side job (`ARCHITECTURE.md` §4).
- **Content moderation needs an explicit key grant** or it does not happen.
- **Discovery is worse than Discord's.** Nobody learns a bot exists from watching it talk in a
  channel. `/` completion and the sidebar section are what recover that, which makes them part of
  the feature rather than polish on top of it.
- **A bot puts load on the community's server.** Realtime's default budget is ~100 events/second
  tenant-wide, counted as deliveries. On Discord a bot costs the community nothing; here it does.
- **A bot cannot hear a call unless somebody says so**, which makes a voice
  transcription or AI-companion bot a per-channel decision rather than something
  that works on install. Deliberate, and the affordable version of it: a music
  bot needs nothing, so the strict default costs the common case nothing (§6b).
- **A Dart bot cannot publish audio at all.** Not a policy — the only Dart
  LiveKit client needs Flutter. Music bots are TypeScript here (§10).
- **Central has no bots.** Friend-gated, quota'd, 30-day TTL — that tier is first contact. Bots are
  a self-hosted feature, which matches the funnel/home split.
- **The bots people actually use want the §6 grant.** The read-everything shape is most of the top
  of Discord's list, so on a server running one the amber marker is the normal state rather than
  the exception. That is the honest price of hosting the category at all. The alternative is not a
  safer Rift; it is no leveling bot, ever, and a community that goes back to Discord for one.

---
