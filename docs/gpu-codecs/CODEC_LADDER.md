# Codec switch-down and back up — design (parked; comes back with step 4 of PLAN.md)

Oct 29 2026. Agreed with the owner in conversation; the outline was first agreed
Oct 19 (TODO.md, "Automatic codec switch-down").

## Why

A desktop share now goes out as H264 High from the GPU (Oct 28). Some viewers
cannot play what the sharer sends at all: Firefox plays only constrained
baseline H264; a Firefox without its OpenH264 plugin, or a Chromium built without
H264, plays no H264; an older iPhone browser may play no VP9. Today such a viewer
gets a black or broken picture and no explanation. The share should move, by
itself, to something every watcher can play, and move back when that watcher is
gone.

One stream, never a second encode. LiveKit's backup codec (a second encode for
viewers who need it) was turned down on Oct 19, because a weak PC cannot afford a
second encode on its CPU.

## Goals

- Every watcher of a desktop share can play it, whatever browser or device.
- The share drops at once when a watcher needs it to, and climbs back about 30 s
  after the last watcher who needed it has stopped watching or left, so joins and
  leaves do not flip it.
- The sharer sees a small note each time it moves.

## Non-goals

- A viewer whose PC struggles to decode (High costs a software decoder about a
  third more CPU, measured Oct 28 on Windows). Not the focus now (owner, Oct 29).
- Phone and web shares. They go through LiveKit's SDK in VP8, which every viewer
  plays. When they move to VP9 (TODO, "Phone and web shares in VP9") they will
  need the same treatment; that is later.
- AV1 and H265. H265 was ruled out for sending; AV1 joins the ladder once
  LiveKit's encryption carries it. The design leaves room for it, nothing more.
- Asking the sharer first. The owner chose automatic in every case, even H264 →
  VP9, which moves the encode from the GPU to the CPU (about 1.5 cores at
  1080p60) and may cost a game frames.

## Anti-goals

- A viewer who is in the call but not watching must not pull the share down.
- An old Rift that does not say what it plays must not pull the share down.
- The share must never go above what the sharer picked, and never back onto a
  GPU encoder that already failed this share (`fall_back` latches VP9 today).

## How it works

### Each viewer says what it plays

Every client publishes one more participant attribute beside `watching`
(`VoiceAttributes`): `plays`, a JSON list of tokens from this set:

| Token | Meaning |
|---|---|
| `h264-high` | H264 High profile |
| `h264` | H264 constrained baseline |
| `vp9` | VP9 |
| `vp8` | VP8 |

(`av1` later.) It is a set, not an order: the sharer's ladder decides the order.
It is published from the call's start in `forSelf`, always, like `watching`, so
the sharer knows before the viewer opens the stream.

Where the list comes from (owner, Oct 29):

- **Codec families (H264, VP9, VP8, later AV1) are asked of WebRTC on every
  platform**: `getRtpReceiverCapabilities('video')` on desktop and Android (the
  vendored flutter_webrtc implements it in `common/cpp` and the Android plugin),
  `RTCRtpReceiver.getCapabilities('video')` on the web. A build or device without
  a whole codec then says so.
- **High vs baseline is a variation inside H264, and no list names High.** In
  Rift's desktop and Android apps, any H264 at all means `h264` and `h264-high`.
  On the web, a browser that lists any H264 profile above constrained baseline
  (Main `4d…`, High `64…`, or High 4:4:4 `f4…`) plays High; one that lists only
  baseline (`42…`) gets `h264`. That puts Chrome on High and Firefox on baseline.
- **What the lists said (Oct 29, read with a temporary log at start):**

  | Receiver | VP8 | VP9 | AV1 | H265 | H264 profiles listed | Plays High? |
  |---|---|---|---|---|---|---|
  | Rift, Linux (libwebrtc) | yes | 0, 2 | yes | no | `42001f`, `42e01f`, `4d001f` | yes (Oct 28) |
  | Rift, Android, SM-A566B (Exynos) | yes | 0, 1, 3 | yes | yes | `42e029` only | yes, in hardware (Oct 28) |
  | Chrome 155, Linux | yes | 0–3 | yes | no | `42001f`, `42e01f`, `4d001f`, `f4001f` | yes (Oct 28) |
  | Firefox 155, Linux | yes | yes | yes | no | `42e01f`, `42001f` | no |

  So asking works for the families, and the High rule above follows the lists.
- **Firefox plays High after all (Oct 29, driven).** No list names High
  because libwebrtc offers only profiles every decoder must play
  (`modules/video_coding/codecs/h264/h264.cc`), not because decoders lack it.
  Firefox 155 on Linux watched a High NVENC share on the web build live at
  ~60 fps through both its decoders: the system FFmpeg (its default there) and
  OpenH264 2.6 (with the FFmpeg path turned off), though it lists only
  baseline. `mediaCapabilities.decodingInfo({type: 'webrtc'})` was tried too:
  Chrome answers sensibly, Firefox says no to baseline and yes to High, so it is
  not usable. **So no viewer tried needs High → baseline.** Proposed: drop the
  `h264-high` rung and the in-place switch; the ladder is `h264` → `vp9` →
  `vp8` (`av1` later), and `plays` holds families only, all asked of WebRTC.
  Firefox on Windows/macOS and Safari are not driven; if one is ever found that
  refuses High, the rung comes back then. **Owner to rule.**
  Windows is not read yet (same libwebrtc as Linux, expected the same); read it
  on the next Windows boot.
- **Aside, out of scope:** Firefox caps VP8 and VP9 at `max-fs=12288`
  macroblocks (about 3.1 megapixels), below 1440p. A 1440p share that drops to VP9
  for a Firefox watcher may be refused or scaled; check it when the app is driven.
- **A client that publishes no `plays`** (any Rift before this) counts as
  playing all four. Every Rift app already plays High (beta.9 on Windows, Oct 28).
  The web app is redeployed with each release, so an old web build is rare.

### The sharer picks the best rung everyone can play

The ladder, best first: `h264-high`, `h264`, `vp9`, `vp8`. The sharer's top
rung is what it picked (or Auto chose): H264 means it starts at `h264-high`; VP9
picked by hand starts at `vp9`; VP8 at `vp8`. A share whose GPU failed has VP9
as its top rung for the rest of the share.

The share runs on the first rung, from its top down, that every **watcher**
plays. Watchers are `ParticipantRoster.watchersOf(roster, shareIdentity)`: never
the sharer, never someone in the call who is not watching. VP8 is the floor: every
WebRTC viewer must play it.

- **Down** happens as soon as the watchers change so that the current rung is no
  longer playable by all of them.
- **Up** waits 30 s with no watcher needing the lower rung. A watcher who needs
  it again inside the 30 s cancels the climb.

### Moving the share

- **H264 High ↔ baseline: in place.** Reopen the GPU encoder on the same track
  with `h264_high` off (or on) and a keyframe, the way a size change already
  re-encodes on the same track. The track was published offering High
  (`profile-level-id=640032`); baseline is a subset, so High's viewers keep
  playing. The SFU already forwards a High-offered track to a connection that only
  answered baseline under baseline's name (seen Oct 28 with the Rust viewer), so a
  Firefox viewer receives a stream it can decode once the picture is baseline.
  **To prove first** — if Firefox refuses it, fall back to republishing.
- **H264 ↔ VP9 or VP8: republish.** The same path the GPU-failure fallback
  takes today (`VideoSession::republish` after changing `settings.codec`): unpublish,
  publish the new codec, viewers stay subscribed and see the picture blink for
  about a second. The bitrate, size and frame rate the sharer picked stay as
  they are.

### Who decides, and where

Dart decides; Rust moves. Dart already has the roster, the watchers, the share's
identity and people's names, and the note is Dart's. A pure function takes the
sharer's top rung, whether the GPU failed, and the watchers' `plays`, and
returns the rung plus who needed it; it is unit-tested. The cubit that runs the
share follows the roster (through the existing listener pattern, not a new
cubit-to-cubit dependency, `BEST_PRACTICES.md` §3), holds the 30 s climb timer,
and asks Rust through a new bridge call to set the rung. Rust keeps the GPU
latch: a request for H264 after the GPU failed is ignored and answered with
what it is actually sending.

### The note

A small `Notice.info` for the sharer each time the rung moves, naming who it is
for when going down:

- Down: "Sharing as VP9 so Sam can watch." / "Sharing as plain H264 so Sam can
  watch." With several: "so Sam and Ana can watch", three or more "so 3 people
  can watch".
- Up: "Sharing as H264 again."

The running share's codec in `ScreenshareState` follows the rung, so the share
menu and stats show what is really sent.

## Testing

- **Unit (Dart):** the rung choice — watchers vs non-watchers, a missing
  `plays`, the top rung capping, the GPU latch, the floor; the climb timer
  (down at once, up after 30 s, cancelled by a return); the web capability
  parsing from sample `getCapabilities` outputs (Chrome, Firefox, Safari).
- **Rust live test** (`gpu_live_test.rs`): on the same track, High → baseline in
  place (SPS profile 100 then 66, same track sid, the viewer keeps recognising
  pictures, encryption intact), and back; H264 → VP9 by republish and back.
- **The app, driven:**
  - A Linux sharer on NVENC, a real **Firefox** on the web build watching: the share
    drops to baseline, Firefox plays, the note shows; Firefox stops watching, back
    to High 30 s later.
  - H264 → VP9 and VP9 → VP8: a test-only override of a desktop client's `plays`
    (an environment variable on a debug build), since a browser without H264 or
    VP9 is hard to come by.
  - A watcher in the call who is not watching changes nothing.
- Windows sharing is not needed for the first pass (same Rust path); note it as
  not driven in `TESTING.md`.

## Docs

`CALLS.md` (how a share picks its codec, the `plays` attribute), `TESTING.md`
rows, `TODO.md` item ticked, `ARCHITECTURE.md` §5 only if it describes the
share's codec as fixed.

## Calls I made (the owner has not ruled on these)

- The viewer's list is a set and the sharer's ladder sets the order, since only
  the sharer knows what is cheap on its machine.
- Never above what the sharer picked; a hand-picked VP9 only ever drops to VP8.
- No `plays` means "plays everything".
- Dart decides, Rust moves.
- The size, frame rate and bitrate stay as picked when the codec moves.
- Note wording as above, and a note on the way back up too.
- 30 s for the climb back.

## Left to the builder

The bridge call's name and shape, where the climb timer sits in the cubit, the
exact `getCapabilities` interop on web, and the name of the test override.

## Oct 29: High turned off

The owner turned High off entirely (app 345d5132, `encoder::SEND_H264_HIGH`),
so shares go out as constrained baseline and the `h264-high` rung is gone.
What remains is H264 → VP9 → VP8 for a viewer without H264 or VP9; none of
the players tried lacks either. Build it small, or park it until one turns up:
the owner's call.
