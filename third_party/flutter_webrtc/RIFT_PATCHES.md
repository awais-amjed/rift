# flutter_webrtc, kept here and patched

The Flutter WebRTC plugin, `flutter_webrtc` 1.6.2+hotfix.4, as published on
pub.dev (MIT — see `LICENSE`). The example, tests and upstream's docs are left
out. The app uses this copy through `dependency_overrides` in its own
`pubspec.yaml`, so `livekit_client` and `dart_webrtc` stay as they are.

## The patch

`third_party/libwebrtc_version.ini` downloads libwebrtc `m150.7871.04` instead
of `m150.7871.03`. Nothing else differs; `.04` is `.03` plus one change,
webrtc-sdk/libwebrtc#153.

The desktop builds take their libwebrtc from that file. Android and iOS take
theirs from their own package managers, and the web uses the browser's, so
this changes Linux and Windows only.

## Why

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

## When this can go

When a `flutter_webrtc` release on pub.dev downloads `m150.7871.04` or later
(upstream's main branch already pins `.05`). Drop the override and this folder,
and check a call's stderr for `raw_key` once more.
