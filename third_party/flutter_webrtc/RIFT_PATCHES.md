# flutter_webrtc, kept here and patched

The Flutter WebRTC plugin, `flutter_webrtc` 1.6.2+hotfix.4, as published on
pub.dev (MIT — see `LICENSE`). The example, tests and upstream's docs are left
out. The app uses this copy through `dependency_overrides` in its own
`pubspec.yaml`, so `livekit_client` and `dart_webrtc` stay as they are.

## The patches

1. **`third_party/libwebrtc_version.ini` downloads libwebrtc `m150.7871.04`**
   instead of `m150.7871.03`; `.04` is `.03` plus one change,
   webrtc-sdk/libwebrtc#153. See *Why the libwebrtc version* below.

2. **WebRTC's `WebRTC-MediaTaskQueuePriorities` is always on**
   (`common/cpp/src/flutter_webrtc_base.cc`, marked `RIFT PATCH`). See
   *Thread priorities* below.

Nothing else differs. The desktop builds take their libwebrtc from that file
and build the plugin's C++ from `common/cpp`. Android and iOS take theirs from
their own package managers, and the web uses the browser's, so both patches
change Linux and Windows only.

## Why the libwebrtc version

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

Patch 1 goes when a `flutter_webrtc` release on pub.dev downloads
`m150.7871.04` or later (upstream's main branch already pins `.05`); check a
call's stderr for `raw_key` once more. Patch 2 goes when libwebrtc gives media
queues these priorities by default (the trial is due to end by April 2027), or
when the plugin lets an app pass its own field trials. With both gone, drop the
override and this folder.
