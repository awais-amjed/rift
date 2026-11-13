# flutter_webrtc, kept here and patched

The Flutter WebRTC plugin, `flutter_webrtc` 1.6.3, as published on pub.dev
(MIT — see `LICENSE`). The example, tests and upstream's docs are left out. The app uses this copy through `dependency_overrides` in its own
`pubspec.yaml`, so `livekit_client` and `dart_webrtc` stay as they are.

## The patches

1. **WebRTC's `WebRTC-MediaTaskQueuePriorities` is always on**
   (`common/cpp/src/flutter_webrtc_base.cc`, marked `RIFT PATCH`). See
   *Thread priorities* below.

2. **Android's screen capture takes a size** (`GetUserMediaImpl.captureSize`,
   marked `RIFT PATCH`). Upstream always captures the whole screen and ignores
   the constraints, so a phone's share could not go out smaller. A constraint
   of Rift's own, `riftShortSide`, sets the short side, and the screen's shape
   is kept. Without it the capture is what it always was (`CALLS.md`, *A
   phone's share*).

3. **Android's screen capture repeats its last frame on a still screen**
   (`OrientationAwareScreenCapturer`, marked `RIFT PATCH`). Android delivers a
   frame only when the screen changes, so a viewer arriving at a still screen
   left the encoder nothing to start on and saw black until something moved.
   After a second with no frame it calls WebRTC's own
   `SurfaceTextureHelper.forceFrame`, once a second, and gives the repeat a new
   time (`CALLS.md`, *A phone's share*).

4. **`getStats` refuses a disposed connection** (`common/cpp/src/flutter_webrtc.cc`,
   marked `RIFT PATCH`). Disposing closes the connection and leaves it in the
   map for a later close, and a track's stats read its receivers through a
   pointer the close emptied. So a stats poll landing as a call ended took the
   whole app down with a segfault (seen Nov 6, Linux, leaving a call). It now
   answers with the error a missing connection gets, which the pollers ignore.

5. **A new libwebrtc in `libwebrtc_version.ini` is downloaded**
   (`third_party/CMakeLists.txt`, marked `RIFT PATCH`). Upstream caches the zip
   by its asset name and skips the download when that file exists, so a machine
   that had built before kept the old headers and DLL. Moving to `.07`, the
   Windows build failed on a header `.04` lacks (Nov 13 2026). The zip's name
   now carries the version, and `libwebrtc/.rift_binary_version` records what
   was extracted, so a change downloads and extracts again. Verified the same
   day on Linux: a fresh build downloaded `.07`, and a wrong stamp made the next
   build extract again.

Nothing else differs. The desktop builds take their libwebrtc from
`third_party/libwebrtc_version.ini`, upstream's, and build the plugin's C++
from `common/cpp`. Android and iOS take theirs from their own package managers,
and the web uses the browser's, so patches 1, 4 and 5 change Linux and Windows
only, and 2 and 3 Android only.

## libwebrtc and call keys

From m150, WebRTC prints its INFO lines to stderr in every build type unless
told otherwise, and `LibWebRTCLogging::setMinDebugLogLevel` no longer reaches
that setting. `.03` therefore printed, among much else, the frame cryptor's
`raw_key` and `derived_key` every time a call's key was set — the channel's key.
On Linux an app started from the desktop has its stderr in the journal, so each
call left its channel's key there for anyone who can read that user's journal.
`.04` makes release builds of libwebrtc silent on stderr again. Rift could not
do this from its own code: the libwebrtc shared library does not export
WebRTC's logging configuration.

Found Oct 20 2026. Verified Oct 21 2026 on Linux: a call's stderr held one
`raw_key` and one `derived_key` line per join on `.03`, and none on `.04`.
The Windows build on `.04` joined an encrypted call in the VM the same day;
its stderr shows no libwebrtc lines on either version, so there is nothing to
count there.

Until 1.6.3 a patch here pinned `.04`. 1.6.3 downloads `m150.7871.07`, which
has #153 and three later changes (desktop capturer options, video frame
processors, a missing include), and drops a compromised eMudhra root from the
TURN/TLS roots, so the pin went (Nov 13 2026). It also moves Android to
`io.github.webrtc-sdk:android` `150.7871.04`, whose `.01` had printed the keys
to logcat; a phone's call the same day printed none.

## Thread priorities

libwebrtc starts the queues that decode and render a received video at
`THREAD_PRIORITY_TIME_CRITICAL` on Windows, above every thread of a game played
beside the call. With the field trial on, each media queue gets a priority for
its job: video above normal, the mic's Opus encoder highest. The plugin already
passes field trials when it initialises libwebrtc; this adds one, always, on
Linux and Windows (on Linux it changes nothing, since libwebrtc's real-time
request is refused there). `CALLS.md` has the measurements.

Verified Oct 25 2026 in the Windows 11 VM, watching a stream:
`VideoDecoderQueue` and `IncomingVideoStreamQueue` at 15 without it and 1 with
it, `AudioEncoderQueue` 0 and 2.

## When this can go

Patch 1 goes when libwebrtc gives media
queues these priorities by default (the trial is due to end by April 2027), or
when the plugin lets an app pass its own field trials. Patches 2 to 4 go when
upstream does the same: a sized and a repeated screen capture on Android, and
a `getStats` that checks for a closed connection; patch 5 when upstream caches
libwebrtc by version. With all five gone, drop the
override and this folder. Whatever libwebrtc a new release brings, check a
call's stderr for `raw_key` once more.
