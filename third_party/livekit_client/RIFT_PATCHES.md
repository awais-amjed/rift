# livekit_client, kept here and patched

LiveKit's Flutter SDK, `livekit_client` 2.13.0 as published on pub.dev (from
[livekit/client-sdk-flutter](https://github.com/livekit/client-sdk-flutter),
Apache-2.0 — see `LICENSE` and `NOTICE`). Kept is what an app builds with:
`lib/`, the platform folders and `pubspec.yaml`; the example, tests and docs
are left out. `pubspec.yaml` at the root swaps it in with
`dependency_overrides`.

The change is marked `RIFT PATCH`; `git diff` against the commit that brought
the copy in shows it.

## Why

A share's sound is published in stereo (`../livekit/RIFT_PATCHES.md`), and the
server's offer to every listener says so with `sprop-stereo=1`. WebRTC sizes
its Opus decoder from the listener's own answer, though, and this SDK answers
the server's offer unchanged, without `stereo=1`, so the track was decoded
into one channel. LiveKit's JS SDK writes `stereo=1` into its answer for every
section the offer marks (`ensureAudioNackAndStereo`); this SDK has no
equivalent, up to 2.13.1.

Measured Oct 12 2026 on the local stack, Linux: a sound share of a test signal
with a tone in one ear, then the other. Before, the listener's answer had no
`stereo=1` and both ears carried the same signal; after, the tone in one ear
was 94 dB above the other, and noise played separately into each ear arrived
uncorrelated.

## The patch

1. **The subscriber's answer gets `stereo=1` on Opus wherever the offer has
   `sprop-stereo=1`** (`lib/src/support/stereo_answer.dart`, called from the
   `SignalOfferEvent` handler in `lib/src/core/engine.dart`). A mono track's
   section is left alone.

## When to remove it

When a `livekit_client` release answers a stereo track with `stereo=1`: bump
to it, delete this folder and its `dependency_overrides` entry. Until then, a
`livekit_client` upgrade needs this copy replaced with the new version and the
change put back.
