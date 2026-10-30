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

4. **`clearEnabled()` takes back an `enable()` or `disable()`**
   (`lib/src/publication/remote.dart`). The SDK keeps the last of the two for
   good, over adaptive stream's view visibility, and has no way back to
   neither. Rift turns a watched stream's picture off while nobody can see
   the window and must then hand it back to adaptive stream, not hold it on
   (`_PicturePauseMixin`, `CALLS.md`). LiveKit's JS SDK has the same gap.

5. **A `disable()` is said again when the server reports the track sending**
   (`updateStreamState` in `lib/src/publication/remote.dart`). LiveKit's
   server clears a subscriber's `disabled` when it binds a video track under
   adaptive stream, to have the client say its visibility again
   (`SubscribedTrack.Bound`, livekit-server 1.13). The SDK only sends when
   its settings change, and `disable()` returns at once when already
   disabled, so a track disabled as it arrived played on. Rift disables a
   watched picture that arrives while nobody can see the window, as a stream
   watched again after it dropped out does (`CALLS.md`).

   Measured Oct 26 2026 on a laptop's Windows, Rift minimised while the
   sharer left and rejoined within 30 s: before, the stream came back at
   3.5–4 Mbit/s and was drawn 38 times a second until Rift was restored;
   with the patch, about 20 kbit/s and 4 frames a second.

6. **The web worker encrypts and decrypts a VP9 frame whole**
   (`getUnencryptedBytes` in `web/e2ee.frame_cryptor.dart`). It left a VP9
   frame's first 10 bytes in the clear on a keyframe and 3 on others, as for
   VP8. LiveKit's native frame cryptor (the libwebrtc of both the Rust SDK and
   `flutter_webrtc`) and its JS SDK leave none, so every frame of a desktop's
   VP9 share failed to decrypt in the browser and the stream stayed black.
   VP9 is a desktop share's codec without a GPU encoder, and wherever
   sharpness is asked for. Still the same on `main` on Oct 29 2026.

   Measured Oct 29 2026 on the local stack: a Linux desktop sharing a moving
   test pattern as VP9 at 720p60, watched on the web build. Before, headless
   Chrome decoded no frames, asked for a keyframe 158 times and the worker
   logged a decrypt error on every frame. After, Chrome decoded 2,080 frames
   in libvpx, moving, and Firefox 155 played it too, where a check of each
   frame found that only 0 clear bytes decrypted it, not 1, 3 or 10. Both
   played the same share in H264 on the unpatched worker, so their call keys
   were good; H264 and VP8 do not reach the changed line.

7. **The web worker escapes and unescapes a sealed H264 or H265 frame**
   (`encodeFunction` and `decodeFunction` in `web/e2ee.frame_cryptor.dart`).
   LiveKit's native frame cryptor passes everything after the frame's header
   (ciphertext, iv, trailer) through `WriteRbsp`, so that sealed bytes cannot
   look like a start code, and undoes it before decrypting. JS does too. This
   worker has the functions and never called them. So a frame from a desktop
   whose sealed bytes held two zeros and a byte up to 3 failed to decrypt in
   the browser, about one in every 4 MB, and the picture froze for 3 s until
   Chrome's keyframe request was answered: on a busy share at 15 Mbit/s, a
   freeze every 6 s. A frame from the browser went out unescaped, which a
   native viewer can misread the same way. Still the same on `main` on Oct 30
   2026.

## When to remove it

Patch 1 goes when a `livekit_client` release answers a stereo track with
`stereo=1`, patch 2 when a release disposes before it closes or the
`flutter_webrtc` it pins includes #2180, patch 3 when a release sends an
unsubscribe without holding the track, patch 4 when a release can go back
to letting visibility decide, patch 5 when a release keeps a disable
through the server's bind, patch 6 when a release's web worker leaves no
VP9 bytes in the clear, patch 7 when it passes H264 through the RBSP functions. With all seven gone, bump, delete this
folder and its `dependency_overrides` entry. Until then, a `livekit_client` upgrade needs this copy replaced with the
new version and the changes put back.
