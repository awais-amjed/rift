# rift_bot

Write a Rift bot.

```dart
final session = BotSession(
  url: serverUrl, anonKey: anonKey, serverId: serverId, seed: seed,
);
final bot = Bot(session);

await session.login();
await bot.listen((message) async {
  if (message.command == 'echo') await bot.reply(message, message.arguments);
});
```

`example/echo_bot.dart` is a complete one, in about sixty lines.

## What a bot is

**A user whose seed lives in a config file instead of on a phone.** Same
Sign-in-with-Solana login, same JWT, same row in `users`, same row-level
security. There is no bot API, no bot token format, and no second auth path —
which is the point: a capability the app has, a bot has, under the same
policies, so the two cannot drift apart.

The seed is the whole identity. Treat it like an SSH key: 32 random bytes, kept
out of the repo, and whoever holds it *is* the bot. Nothing is ever sent to the
server except signatures.

```
RIFT_BOT_SEED=<base64 of 32 random bytes>
```

## What a bot can hear

**Only what it is addressed.** Not the message before it, not the one that
mentions it, not the rest of the channel it is sitting in.

That is not this package being careful. It is `messages_select`:

```sql
AND (NOT app.is_bot() OR to_bot = auth.uid() OR sender_id = auth.uid())
```

A bug in your bot cannot widen it, and neither can a bug in this SDK.

The reason is that Rift channels are end-to-end encrypted and a bot can never
hold a channel key — a wrapped key *is* read access, it is arithmetic rather
than a rule, and unlike a rule it cannot be taken back. So a bot is not given
one, and the database refuses to record one for it even if every client asked.

Which means:

- **A bot cannot react to conversation.** No keyword triggers, no automatic
  link previews, no reading the room. If that is what you are building, it
  cannot be built here, and that is deliberate.
- **Commands and replies are not encrypted.** They are addressed to something
  that could not open them otherwise. The app badges them, and warns the person
  typing *before* they send.

## Adding your bot to a server

An admin makes an invite with "this invite is for a bot" ticked, and you join
with it. That is the whole authorisation model — the same invite that carries a
person's permissions carries the bot's, minus admin, which a program that joined
from a config file does not get.

Identity is derived per `(host, serverId)`, so one deployment across N servers
is N keypairs and N sessions. The same seed on two servers is two unrelated
bots, and neither server can correlate them.

## Replying

| Call | Who sees it | For |
|---|---|---|
| `bot.reply(m, text)` | everyone in the channel | genuinely public output — a poll result, a dice roll |
| `bot.replyPrivately(m, text)` | only whoever asked | errors, confirmations, anything the room does not need |

A private reply is private from the *channel*, not from the server: it is
stored unencrypted like everything else a bot touches. It is enforced by RLS
rather than by clients agreeing to hide it, so no member ever receives the row.

Panels — living state like a queue or a score — are the third shape and are not
built yet. They need a declarative block set so the app draws them with its own
components rather than a bot shipping its own interface.

## Publishing a manifest

```dart
await session.publishManifest({
  'description': 'Plays music',
  'data_use': 'Track names are sent to an outside music service.',
  'commands': [
    {'name': 'play', 'description': 'Play a track', 'usage': '/play <song>'},
  ],
});
```

Two reasons this is worth doing even for a one-command bot. The command list is
how a client offers `/play` while your process is **asleep** — a menu that costs
a round trip per keystroke is not a menu. And `data_use` is shown to somebody in
the composer *before* they type: for a bot that forwards anywhere, that sentence
protects them more than any amount of key management, because the bot reads the
command either way.

It is an advertisement, not evidence. Nothing is authorised by what it claims.

## What this package does not do yet

- **Realtime for *reading*.** `Bot.listen` polls, every two seconds by default.
  Replies do ring the channel's doorbell, so an answer appears immediately for
  anyone with the channel open — a bot that only polled in both directions
  answered correctly and invisibly until somebody reopened the room. No reconnect
  logic to get wrong, and nothing spent from the server's shared event budget
  (~100/second, which every member's unread badges also draw on). Realtime
  belongs here eventually; it did not belong in the version that had to prove
  the rest works.
- **Voice.** A music bot publishes to the server's LiveKit like any participant,
  and `get_channel_token` already mints the JWT. Not wrapped here yet.
- **Attachments.** A bot's reply is text.
- **DMs.** A bot can be DM'd, and this SDK does not read them yet.

## Depending on the app package

`rift_bot` has a path dependency on the Flutter app, which looks odd for
something that runs headless. It is deliberate: everything under
`lib/data/repositories/crypto_repository*.dart` is **Flutter-free**, and the
alternative is a second implementation of the signing format. Two
implementations of a canonical payload is two things that can disagree, and the
disagreement shows up as messages silently not rendering.

The right long-term shape is a `rift_crypto` package both sides depend on. Until
then this costs a Flutter SDK on the machine running the bot.

## The wire format

Third-party bots make this a public contract, so it is written down rather than
implied:

- messages are signed over `chatmsg:v1:<contextId>:<keyVersion>:<nonce>:<ciphertext>`
- a bot's messages use `keyVersion` 0 and an empty nonce, and are **signed but
  not sealed**
- clients drop what they cannot verify, so an unsigned reply is an invisible one

`Bot.reply` does all of that. Reach past it only if you mean to.
