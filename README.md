# Rift

Chat, voice and screen sharing for a group of people who would rather not hand
their conversations to somebody else. You run the server; messages are encrypted
before they leave the device, and the server stores ciphertext it cannot open.

This repository is the **client** — the Flutter app, the Rust crate behind screen
capture, and `rift_crypto`. The servers, the bot SDK and the website are their
own repositories.

> **In development.** No releases yet, and nothing is published. Migrations are
> still rewritten in place rather than superseded, because no real server has to
> be carried across.

## The repositories

| Repo | Holds | Who runs it |
|---|---|---|
| **`rift`** | this: the client, `rust/`, `rift_crypto/` | — |
| `rift-self-host` | a server's schema, endpoints and console | anyone |
| `rift-central` | accounts, the directory, the push relay | us |
| `rift-bot-sdk` | the TypeScript bot SDK | third parties |
| `rift-website` | joinrift.app and the self-hosting docs | us |

Clone them as siblings. Two things cross the boundary and expect it:
`tool/gen_wire_vectors.dart` writes the bot SDK's copy of the wire contract, and
`LOCAL_DEV.md` assumes `../rift-self-host` when it names a migration.

## Running it

```bash
flutter pub get
flutter run -d linux        # or windows, macos, android, chrome
```

Linux, Windows, Android and the web are the targets that get exercised; macOS and
iOS build but are unproven (see `MANUAL_TESTING.md`).

Two dependencies are not ordinary:

- **`livekit_client` is a fork**, pinned by commit in `pubspec.lock`. It carries a
  patch for a freeze when leaving a call on Linux. A blanket `flutter pub upgrade`
  will try to move off it; `FORK.md` in that repository covers rebasing onto the
  next upstream release.
- **The Rust crate builds itself** through `flutter_rust_bridge` and Cargokit on
  first run. `build_rust_local.sh` is for building it by hand.

You also need a server to talk to. `LOCAL_DEV.md` (gitignored, machine-specific)
describes the development stack; `rift-self-host` builds the packaged one.

## Tests

```bash
flutter analyze
flutter test                 # 1,283 cases across 147 files
./scripts/style_check.sh     # size budgets, lazy lists, literals, layering
```

The databases test themselves, in the repositories that own them:
`scripts/db_test.sh` in `rift-self-host` and in `rift-central`. Neither suite can
see whether the *app* works — realtime delivery, key distribution, presence,
LiveKit, layout at a given width — so that is driven by hand and written down in
`MANUAL_TESTING.md`.

## Reading order

| Document | For |
|---|---|
| `ARCHITECTURE.md` | the shape of the system, and the decisions behind it |
| `WIRE.md` | the exact formats a second implementation must match |
| `BOTS.md` | what a bot may see, hear and say |
| `AGENTS.md` | conventions this codebase actually follows |
| `CODE_STYLE.md` | size budgets, one widget per file, where constants live |
| `MANUAL_TESTING.md` | what has been driven through the real UI, and what has not |

`API.md` in `rift-self-host` documents what a client may call and over which
transport.

## Layout

```
lib/data/          models, repositories, enums — no Flutter widgets
lib/logic/         cubits and services; the only place that decides anything
lib/presentation/  widgets, screens, theme
rift_crypto/       the key ladder and message envelopes, Flutter-free
rust/              screen capture and the audio pipeline
test/              pure logic and crypto, no live server
```

`rift_crypto` is a package rather than a folder for two reasons: nothing headless
should need a Flutter SDK to sign a string, and it is the **reference
implementation** the wire vectors are generated from.
