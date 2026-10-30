# Step 2: zero-copy sharing on Linux Wayland — design

Oct 29 2026. Designed with the owner; not yet built. Step 2 of `PLAN.md`. What is
the owner's is marked so; the rest is the builder's call, and says so where it is
a judgement.

## Why

A Wayland share today: the compositor's picture is on the GPU; libwebrtc's
PipeWire capturer imports it into EGL and reads it back (`pipewire-main-l`);
`share-frames` converts it to NV12 with libyuv; `gpu-encoder` uploads it and
FFmpeg encodes it. That is 21–23% of a core at 1080p60 (`PLAN.md`, step 0), most
of a core at 1440p120, and NVENC waits 10 ms a picture on top. Every step of it
moves a picture that was already where the encoder needed it.

**Success:** a 1080p60 share of a moving picture, measured the way step 0 was
(`threadtop`, 20 s, release build), costs Rift under about 3% of a core on VAAPI,
against 21–23% now, with the picture as smooth and as sharp as today's.
Reached 4.5%, accepted Oct 30 against gpu-screen-recorder's 3.4% and OBS's 8%
for the same picture (`PLAN.md`, step 0).

## Goals

- Wayland shares (screen or window) encoded on Intel or AMD through VAAPI with
  the picture never on the CPU.
- One capturer for every Wayland share, GPU or not (builder's call, put to the
  owner Oct 29 with no objection).
- Every behaviour a share has today still works: the picker and the saved
  window pick, sound matched to the window, changing quality mid-share, a
  window resized mid-share, minimised (paused) and closed windows, the fall back
  to VP9 when the encoder fails, keyframe and bitrate requests, the rate gate.

## Not in this step

- **NVIDIA-drawn screens (owner, Oct 29): next, on this laptop.** It can be set to
  NVIDIA-only display in the BIOS. VAAPI is built and proved first, then the owner
  switches the laptop and the NVIDIA half (EGL import, GL shader to NV12,
  CUDA-GL into NVENC: `PLAN.md`) is designed and built on the same capturer. Until
  then a screen the Intel/AMD GPU cannot import keeps today's CPU route through
  the new capturer (below).
- X11 shares: unchanged, libwebrtc's capturer.
- Windows (step 1), watching (step 3), new codecs (step 4).

## Anti-goals

- A share that starts on the GPU path and is worse than today: dropped pictures,
  a black or torn picture, a lost cursor, a picker asked twice.
- Rift failing to start, or to share at all, on a machine without PipeWire,
  VAAPI or EGL. Every new library is opened at run time or lives in one that is.

## How it works

### Who owns what

```
Rust (portal, ashpd)        C, librift_ffenc.so                   Rust
 picker + restore token ──▶ PipeWire stream (pw_thread_loop) ──▶ share-frames
 PipeWire fd + node id       one buffer held at a time           Feed::Gpu ─▶ ffenc: map, scale_vaapi, h264_vaapi
                                                                 Feed::Raw ─▶ today's I420 path (SHM buffers)
```

- **The portal: Rust, with `ashpd` (MIT, on `zbus`, no system library).** It runs
  CreateSession, SelectSources, Start and OpenPipeWireRemote, and hands the fd and
  node id to the stream.
  - A window share keeps Dart's picker (`WindowSharePortal`): Rust starts its
    session with Dart's restore token, so no second picker.
  - A screen share gets the picker from Rust, where libwebrtc ran it before.
  - The cursor is asked for as `embedded` (builder's call, put to the owner Oct
    29 with no objection): the compositor
    draws it into the picture, so Rift draws no cursor. A share's cursor setting
    never changes mid-share; a new setting is a new session.
  - Sessions close when the share ends, and GNOME's saved pick is still forgotten
    after it (`WindowSharePortal.forget`).
- **The PipeWire stream: C, in `librift_ffenc.so`** (a new `pipewire.c` beside
  `ffenc.c`). The library is already opened at run time and optional, so linking
  libpipewire and libEGL there keeps them off Rift's own load. *Builder's call:*
  Rust's `pipewire` crate links libpipewire into the Rust library, which every
  Linux Rift would then need to start; C in ffenc avoids that.
- **Reuse over our own (owner, Oct 29): code other people already run, wherever it
  fits.** Read Oct 29 at OBS `1d4d119` and Sunshine `a679b05`:
  - The stream is OBS's `plugins/linux-pipewire/pipewire.c` (GPL-2.0-or-later, C,
    the most widely run Linux screencast consumer), its rendering, cursor and
    OBS types cut away. Kept as OBS wrote them: `build_format`/`build_format_params`
    (formats with modifiers), `init_format_info`, `remove_modifier_from_format` and
    `renegotiate_format` (a modifier that fails to import), `find_latest_buffer`
    and `return_unused_pw_buffer`, `on_param_changed_cb` (buffer kinds and metas,
    the explicit-sync timeline included), and the state and core callbacks.
    Explicit sync is built only against PipeWire 1.2's headers or newer, behind
    OBS's own `PW_CHECK_VERSION(1, 2, 0)`. The release is built on Ubuntu 24.04,
    which has 1.0, so a release build syncs implicitly (found Oct 30, when the
    builder failed on it). The NVIDIA half needs this settled first, since
    NVIDIA's driver relies on explicit sync.
  - The modifier query is OBS's `libobs-opengl/gl-egl-common.c`
    (`query_dmabuf_formats`, `query_dmabuf_modifiers`).
  - A crop meta is honoured the way OBS honours it (a window's stream can carry
    one); `scale_vaapi` reads a frame's crop. A rotation meta is turned upright
    on the GPU (`transpose_vaapi`), as OBS turns it (owner, Oct 29). A resized window is letterboxed on the GPU
    (`pad_vaapi`) by the same rule as today's (`resolution::letterbox`).
  - The import is FFmpeg's own: a DRM_PRIME frame `hwmap`ped to VAAPI, as
    `kmsgrab` users run it, not Sunshine's EGL-and-shader route into a VA surface.
    Sunshine's EGL import is what the NVIDIA half takes later.
  - The portal is `ashpd`, a library many Rust apps run, not our own D-Bus code.
  - Each file brought in keeps its copyright header and says what was changed.
- **What to do with each picture stays in Rust**, on `share-frames`: the feed, the
  target size, the rate gate and the fall back are all there today and stay there.
  The C side passes an opaque picture up (its size, and either a DMA-BUF or a
  memory buffer) and takes it back once used.

### Buffers

- **GPU feed:** the stream offers DMA-BUF in BGRx/BGRA (and RGBx/RGBA) with the
  modifiers the encoder's GPU can import, asked from EGL on that render node
  (`eglQueryDmaBufModifiersEXT`, leaving out external-only ones), as OBS does.
  - ffenc maps the DMA-BUF as a DRM_PRIME frame into VAAPI (`av_hwframe_map`),
    `scale_vaapi` makes NV12 at the target size, and `h264_vaapi` encodes it.
  - ffenc is built with libavfilter for this, only `buffer`, `buffersink`,
    `scale_vaapi` (all LGPL). *Builder's call:* VAAPI's video processing by hand
    would avoid libavfilter, but scale_vaapi is the tested way.
  - The PipeWire buffer goes back as soon as scale_vaapi's copy is done, not after
    the encode, so the compositor is never short of buffers.
  - **A modifier that fails to import** is dropped and the stream renegotiates
    without it (OBS's way); with none left, it renegotiates to memory buffers.
  - The GPU: the render node the compositor's buffers import on. On a hybrid
    laptop that is the Intel GPU (owner, Oct 29). *Builder's call:* try VAAPI on
    each render node with an Intel/AMD driver and keep the one whose import works;
    a screen none imports goes to memory buffers.
- **Raw feed (VP9 picked, or the encoder failed):** the stream renegotiates to
  memory buffers (`SPA_DATA_MemFd`/`MemPtr`) in the same four formats, the
  compositor reads back, and the picture takes today's I420 path in `frames.rs`,
  libyuv converting either byte order. (Built with memory in BGRx/BGRA only at
  first; some wlroots compositors share memory only red first, so the other two
  were added before release.) Pictures in the old kind of
  buffer while the switch lands are dropped. This is about today's cost, moved to
  the compositor.

### Timing

- PipeWire sends a picture when the screen changes, not on a clock. The stream
  asks for at most the share's fps, and `share-frames` keeps only the newest.
- A still screen sends nothing, but WebRTC still asks for keyframes and a joining
  watcher needs one: the last picture is kept (a VAAPI surface after scale_vaapi
  for the GPU feed) and encoded again on a keyframe request and about once a
  second. *Builder's call:* check what today's capture sends on a still screen and
  match it. Today's capture hands libwebrtc its last picture on every tick. A
  memory picture has no keyframe request to wait on (libwebrtc's own encoder
  takes those), so it is kept as the I420 it was converted to and sent again
  every 100 ms of quiet, the rate of LiveKit's own keepalive, and once a second
  after 2 s still, as libwebrtc's own still-screen mode backs off (owner, Oct
  30). The first picture
  is kept the same way until the feed it sizes is attached: without that, KDE's
  covered window, drawn once, never reached the viewer (found Oct 30).
- Each picture carries PipeWire's presentation time for the share's clock and A/V
  sync, as today's frames carry theirs.

### Events kept

- **Size change** (a resized window): PipeWire renegotiates the size; the picture
  arrives at the new size and `VideoSlot::feed` handles it as today, letterbox
  included. ffenc rebuilds its filter graph for the new input size.
- **Paused** (a minimised window) and **closed** (the stream ends, errors, or the
  portal session closes): mapped onto today's `on_paused` and
  `ScreenshareEvent::SourceClosed`.
- **No pictures in 10 seconds:** the same failure as today.

### When the new capturer is not used

If `librift_ffenc.so` does not load, or the portal or PipeWire refuses, the share
runs on libwebrtc's capturer exactly as today. So a Wayland machine always shares.

## Proof

- Unit tests (`cargo test --release`) for the pure parts: modifier lists and the
  drop-and-renegotiate order, the buffer kind for each feed, the keep-and-repeat
  rule.
- A live test in the style of `gpu_live_test.rs` that shares through the portal
  on this laptop, if the portal can be answered without a person (a restore
  token); otherwise driven by hand.
- Driven live on this laptop, GNOME 50 Wayland, with a web viewer and an app
  viewer: whole screen and a window; 1080p60 moving picture through `threadtop`
  against step 0's table; quality changed mid-share to VP9 and back; a window
  resized, minimised and closed; the encoder made to fail (`RIFT_FFENC_ENCODER`
  pointed at something that breaks) to see the VP9 fall back; sound matched to
  the window still.
- KDE Plasma in the KDE VM: the capturer must at least fall back cleanly there
  (the VM has no VAAPI GPU).
- `CALLS.md` and `TESTING.md` updated in the commits that change the behaviour.

## Left to the builder

- The C API between Rust and the stream (create, start, a picture callback,
  release, renegotiate, stop), with `RIFT_FFENC_ABI` bumped.
- Thread ownership: PipeWire's thread loop holds buffers only briefly; no FFmpeg
  call on PipeWire's thread.
- HDR or 10-bit formats: refused at negotiation, for now.
- Build changes: libpipewire and EGL headers in `native/ffenc/build.sh` and the
  Linux build (`linux/CMakeLists.txt`, CI's packages), licence notices for `ashpd`
  and its crates through `scripts/generate_licenses.sh`.
