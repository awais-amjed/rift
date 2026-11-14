# audioplayers_linux, kept here and patched

The Linux side of `audioplayers`, `audioplayers_linux` 4.3.0 as published on
pub.dev (from [bluefireteam/audioplayers](https://github.com/bluefireteam/audioplayers),
MIT — see `LICENSE`). Kept is what an app builds with: `linux/` and
`pubspec.yaml`, the latter without the workspace resolution and the dev
dependencies. `pubspec.yaml` at the root swaps it in with
`dependency_overrides`; `audioplayers` itself stays on pub.dev.

The one change is marked `RIFT PATCH`.

## Why

The plugin's dispose, which runs as the Flutter engine shuts down at quit,
called `gst_deinit()`. That waits for every GStreamer thread in the process to
finish, not only the plugin's own. Rift's chat videos play through GStreamer
too (`rust/src/clips/linux.rs`), and a paused one keeps its streaming threads
until the clip is dropped, which nothing does at quit. So quitting with a chat
video open hung for good: the window went black and the process never exited.
Seen Nov 14 2026 on an AMD desktop with 2.2.0-beta.1, from the stack of the
hung process (the main thread in `gst_deinit` under this plugin's dispose, a
chat video's queue waiting on its sink).

The call is gone. Nothing needs it: the process is exiting, and GStreamer
cannot be started again after it in any case.

## When this can go

When upstream stops calling `gst_deinit()` from the plugin (still there in
4.3.0 and on `main` as of Nov 14 2026). Then delete this folder and its
override.
