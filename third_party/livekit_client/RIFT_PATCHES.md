# livekit_client, kept here and patched

LiveKit's Flutter SDK, `livekit_client` 2.13.1 as published on pub.dev (from
[livekit/client-sdk-flutter](https://github.com/livekit/client-sdk-flutter),
Apache-2.0 — see `LICENSE` and `NOTICE`). Kept is what an app builds with:
`lib/`, the platform folders and `pubspec.yaml`; the example, tests and docs
are left out. `pubspec.yaml` at the root swaps it in with
`dependency_overrides`.

Each change is marked `RIFT PATCH`; `git diff` against the commit that brought
the copy in shows them.

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

2. **A peer connection is disposed before it is closed** (`onDispose` in
   `lib/src/core/transport.dart`). The SDK closed, then disposed. On Windows
   and Linux, `flutter_webrtc`'s `peerConnectionClose` drops the connection
   from its map, and `peerConnectionDispose` then finds nothing and returns
   without removing the connection's observer, which keeps every remote track
   it received. A volume or mute is sent by track id, and the plugin answers
   with the first registered track that has it. A track keeps its id when the
   same person is received again, after leaving a call and coming back while
   they stayed, so the change could go to the dead track and nothing in the
   call changed. Reported Oct 17 2026 by two Windows testers who could not
   turn someone down or mute them until they rejoined. On Android and Apple
   platforms, and in the browser, a close after a dispose does nothing. The
   plugin's side is flutter-webrtc/flutter-webrtc#2180, open and unreleased as
   of Oct 17 2026; the order has been the SDK's on `main` throughout.

   Measured Oct 17 2026 on Linux with `flutter_webrtc` 1.6.2+hotfix.4: one
   audio track received, its receiver closed then disposed, the same track id
   received again on a new one. Volume 0 and then disabling it left it playing
   at −20 dBFS. Disposed then closed, volume 0 brought it to −49 dBFS and
   disabling it to silence.

3. **`unsubscribe()` asks the server even when no track is here**
   (`lib/src/publication/remote.dart`). The SDK returned early unless it
   held the track. LiveKit's server subscribes a joining participant to every
   track twice, at the join and again once its connection is up, and the
   second pass undoes an unsubscribe sent between the two, often without the
   track arriving at the client again. The SDK then believed it had dropped a
   track the server was still sending, and had nothing to ask with. LiveKit's
   JS SDK sends the request whatever it holds; asking about a track the
   server is not sending changes nothing. Rift asks again once it is told
   its connection is active (`_dropUnwatchedPictures`, `CALLS.md`).

   Measured Oct 25 2026 on the local stack with the server's debug log: a
   member rejoining a call with a stream running, unwatched, left it flowing
   in about one rejoin in four, until the call ended; with the patch and the
   second ask, in none of sixteen.

## When to remove it

Patch 1 goes when a `livekit_client` release answers a stereo track with
`stereo=1`, patch 2 when a release disposes before it closes or the
`flutter_webrtc` it pins includes #2180, patch 3 when a release sends an
unsubscribe without holding the track. With all three gone, bump, delete this
folder and its `dependency_overrides` entry. Until then, a `livekit_client` upgrade needs this copy replaced with the
new version and the changes put back.
