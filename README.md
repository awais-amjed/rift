# Rift

Chat, voice, video and screen sharing for a group of people who would rather not
hand their conversations to somebody else. Anyone can run a server, and messages
and calls are end-to-end encrypted, so the server stores ciphertext it cannot
open.

This repository is the **app**: the Flutter client for desktop, mobile and web,
the Rust crate behind screen capture, and `rift_crypto`, the reference
implementation of Rift's cryptography.

> **Status: in development.** No releases yet, and nothing is published.
> Linux, Android and the web are exercised regularly; Windows, macOS and iOS
> build but have no recorded test pass (see [`TESTING.md`](TESTING.md)).

## Features

- **Servers you run** — text and voice channels, private channels, roles, invites
- **End-to-end encrypted** messages, attachments, voice and video
- **Screen sharing** with native capture, and system audio on Linux and Windows
- **Direct messages** on a server, and between friends across servers
- **Calls in DMs**, encrypted with a key the server never holds
- **Replies, forwards, reactions, pins, polls, mentions and link previews**
- **Moderation** — reports, time-outs, bans, and control over who can DM you
- **Bots and webhooks**, through a public SDK
- **Your identity is yours** — one seed on your device, backed up only if you
  choose, encrypted before it leaves

## Building it

You need [Flutter](https://docs.flutter.dev/get-started/install) (stable,
3.41 or newer) and a [Rust](https://rustup.rs) toolchain.

```bash
flutter pub get
flutter run -d linux        # or windows, macos, android, chrome
```

The Rust crate builds itself through `flutter_rust_bridge` and Cargokit on the
first run; `build_rust_local.sh` builds it by hand.

On Linux, install the Ayatana AppIndicator library for the tray icon first
(`libayatana-appindicator3-dev` on Debian and Ubuntu, `libayatana-appindicator`
on Arch).

## A server to connect to

The app joins servers through invite links. To get one, run a server with
[`rift-self-host`](https://joinrift.app/docs/install/) — its console has a
local-testing mode for trying Rift on one machine — and paste the invite it
gives you into the app.

## Tests

```bash
flutter analyze
flutter test                 # pure logic, crypto and layout invariants
./scripts/style_check.sh     # size budgets, lazy lists, literals, layering
```

The databases have their own suites in the server repositories. Anything that
needs a live server — realtime delivery, key distribution, calls, layout at a
width — is driven by hand; [`TESTING.md`](TESTING.md) records what has been
checked and how to drive each client.

## Documentation

| Document | For |
|---|---|
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | the shape of the system, and the decisions behind it |
| [`WIRE.md`](WIRE.md) | the exact formats a second implementation must match |
| [`BOTS.md`](BOTS.md) | what a bot may see, hear and say |
| [`TESTING.md`](TESTING.md) | what has been verified live, what has not, and how to drive the app |
| [`AGENTS.md`](AGENTS.md) | the conventions this codebase follows |
| [`CODE_STYLE.md`](CODE_STYLE.md) | size budgets, one widget per file, where constants live |

What a client may call on a server, and over which transport, is `API.md` in
`rift-self-host`. Running a server is covered by the
[self-hosting guide](https://joinrift.app/docs/).

## Layout

```
lib/data/          models, repositories, enums — no Flutter widgets
lib/logic/         cubits and services; the only place that decides anything
lib/presentation/  widgets, screens, theme
rift_crypto/       the key ladder and message envelopes, Flutter-free
rust/              screen capture and the audio pipeline
test/              pure logic, crypto and widget invariants — no live server
```

`rift_crypto` is a package rather than a folder for two reasons: nothing headless
should need a Flutter SDK to sign a string, and it is the **reference
implementation** the wire vectors are generated from.

## Contributing

Read [`AGENTS.md`](AGENTS.md) and [`CODE_STYLE.md`](CODE_STYLE.md) first: they
are the rules this code actually follows, from state management to colours.
`flutter analyze` and `flutter test` must pass before a commit, and a change
that makes a doc untrue updates the doc in the same commit.

## Related repositories

Clone them side by side: `tool/gen_wire_vectors.dart` writes the bot SDK's copy
of the wire contract, and the docs refer to the others by name.

| Repository | What it is | Who runs it |
|---|---|---|
| **`rift`** | this: the app | — |
| `rift-self-host` | a server's schema, endpoints and console | anyone |
| `rift-central` | accounts, the server and bot directories, the push relay | the project |
| `rift-bot-sdk` | the TypeScript bot SDK | bot authors |
| `rift-admin` | the directory moderation dashboard | the project |
| `rift-models` | the on-device image classifier and the tooling that builds it | — |
| `rift-website` | joinrift.app and the self-hosting docs | the project |

## License

[GPL-3.0](LICENSE). Third-party notices ship with the app in
[`assets/licenses/`](assets/licenses/).
