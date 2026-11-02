# Step 3: GPU decode and draw for desktop watchers — design

Nov 2 2026. Proposed to the owner; not yet agreed or built. Step 3 of `PLAN.md`. What is
the owner's is marked so; the rest is the builder's call, and says so where it is a
judgement.

## Why

Watching a share on the desktop today: flutter_webrtc's libwebrtc decodes it on the CPU,
`FlutterVideoRenderer::CopyPixelBuffer` converts every frame to RGBA on the CPU
(`ConvertToARGB`), and Flutter uploads the RGBA picture on its raster thread. Measured
(`PLAN.md`, step 0; `RESEARCH.md`):

- **Linux** (Oct 26, 1080p60, Rift on the Iris Xe): about 65% of a core while watching.
  The raster thread is 21–23% (convert, upload and the window's redraw), the decoder 15%,
  the main thread 12–13%.
- **Windows** (Oct 26, 1080p60 H264): 117% of a core, about 87% of it the stream page
  (convert, upload, draw, nearly all on the raster thread), 7–30% the decoder.

Gaming is Rift's main use (owner). A watcher who is also playing feels this as stutter.

**Success:** watching a 1080p60 H264 share costs well under half of today's on Linux and
Windows, measured the way step 0 was (`threadtop`, 20 s, release build), with the picture
as smooth and as sharp as today's and the sound no further from the picture than today.

## The route (owner, Nov 2): watch through Rust

- A watcher opens a **second, receive-only LiveKit connection from Rust**, as a sharer
  already opens one to publish (`rust/src/sharing/room.rs`). It exists only while a share
  is watched.
- It receives **both the share's picture and its sound** (owner, Nov 2). One connection
  carries both, so WebRTC keeps them in step. The sharer's voice stays on the call's
  connection and may drift a little against the share; the owner accepts that.
- Not chosen: rebuilding flutter_webrtc's libwebrtc (`PLAN.md`, step 3 (a)), and waiting
  for an upstream decoder hook ((c)).
- **Not chosen: moving all call audio to Rust (owner, Nov 2).** Weighed and dropped: the
  web and the phones would keep the Dart call, so every call fix would be made twice.

## Goals

- Linux (Intel and AMD through VAAPI, NVIDIA through NVDEC) and Windows (D3D11): the share
  decoded on the GPU and drawn by a shader into a texture Flutter shows, with the picture
  never on the CPU.
- Everything watching does today still works:
  - every place a share is drawn: the tile, the expanded tile, the member card and the
    PiP window;
  - the sharer's camera over the stream;
  - the stream's volume, mute and deafen;
  - the picture pausing while Rift cannot be seen, with the sound kept;
  - the call's key and its rotation;
  - a share that changes size;
  - a late joiner's first picture.
- A watcher whose server or GPU cannot do this watches as today. Nothing gets worse.

## Not in this step

- Cameras: they stay on the call's connection, decoded and drawn as today. The shader from
  phase A could be put into flutter_webrtc's renderer for them later.
- Phones and the web: phones already decode on the GPU and the browser decodes for itself.
- H265 and AV1 (step 4), and the codec switch-down that comes with them.
- macOS.

## Anti-goals

- A watcher who sees nothing because the new path failed. Any failure (no token, no
  GPU decoder, an import refused, a lost connection) falls back to today's path, once,
  with a line in the app's log.
- A hidden listener: a watch connection that can hear a call its owner has left (see
  *The server*).
- A watch connection that kicks the watcher's own voice connection (see *Old servers*).

## How it works

```
Dart                        Rust                                   Runner (C++)
 watch(share) ─────────────▶ watch connection (hidden, _watch)
                             ├ picture: pass-through ─▶ ffdec (FFmpeg hwaccel)
                             │                           └ GPU frame ─▶ stream texture
 Texture(id) ◀─────────────────────────────────────────────────────── (shader, NV12 → RGBA)
                             └ sound: PCM ─────────────▶ output device (mic test's playback)
```

### Phase A: the watch connection, drawing on the GPU

Built and measured first. It proves everything except the hardware decoder, and it is
also the fallback when there is no hardware decoder.

- **The connection** is LiveKit's normal Rust room. It subscribes only to the watched
  share's tracks, at high quality, with the call's key (the same key handling as
  `sharing/room.rs`). One connection per call, whichever shares are watched.
- **The picture** comes out of libwebrtc's own decoder (LiveKit's build, in software) as
  I420. Phase A only changes the drawing.
- **The texture** is the runner's, as the noise filter is. Dart asks the runner for one
  and passes its handle to Rust, the way DPDFNet's entry points reach the noise filter
  (`dpdfnet::entry_points`). Rust says when a new frame is ready, and the runner draws it
  when Flutter asks:
  - **Linux:** an `FlTextureGL`. Its `populate` runs on the raster thread with Flutter's
    GL context current. It uploads the three planes as one-byte textures (1.5 bytes a
    pixel, against 4 for today's RGBA) and draws them through a YUV→RGBA shader into the
    texture Flutter shows. The CPU conversion is gone. Rift's Linux build draws with
    Impeller on OpenGL ES, and no engine document says `FlTextureGL` works there. **Probed
    Nov 2** (a throwaway app, Flutter 3.47.7, the RTX 3070 Ti on discrete, GL ES 3.2): a
    1280x720 I420 picture of four colour blocks, uploaded as three planes and drawn through
    the shader, came out right under native Wayland (Flutter's own snapshot) and on screen
    under X11 (a screenshot), at 60 updates a second with no GL error. The same probe on
    the Iris Xe (laptop on hybrid, Mesa, GL ES 3.2) came out right under Wayland and X11
    too, about 1.1 ms an update including the CPU fill, no GL error.
  - **Windows:** a `GpuSurfaceTexture` from a DXGI shared handle on Flutter's own adapter,
    filled the same way by a D3D11 pixel shader.
- **The sound** comes out of the Rust connection as PCM (`NativeAudioStream`), see
  *The sound*.
- **Dart** switches each share's tile from `VideoTrackRenderer` to a `Texture` while the
  Rust path holds it. It also stops subscribing to that share on the call's connection,
  so the share is not received twice. The stream volume key stays
  `screenshareSettingsKey`.

### Phase B: decoding on the GPU

- **LiveKit's pass-through decoder** (rust-sdks #1515, open upstream, last updated Oct
  27) is taken into our fork's `rift` branch, as the stereo patches were. The watch
  connection then hands Rust each frame still encoded and already decrypted.
  - The jitter buffer and the A/V-sync delay still run before it (the PR, *Why smoothing
    is off*), so the picture stays in step with the sound.
- **ffdec**, a decoder next to ffenc in the same FFmpeg library (`native/ffenc`), decodes
  each frame with FFmpeg's hwaccel:
  - **Linux VAAPI** (Intel, AMD): the surface is exported as a DMA-BUF
    (`vaExportSurfaceHandle`). The runner imports its planes into EGL images in Flutter's
    context, and the same shader draws them. No copy.
  - **Linux NVIDIA**: NVDEC through FFmpeg's `cuda` hwaccel. The planes are copied on the
    GPU into GL textures through CUDA-GL interop, as ffenc's NVENC path does the other
    way.
  - **Windows**: `d3d11va` on Flutter's adapter, then the D3D11 shader.
- **On a hybrid laptop,** decode on the GPU Flutter draws with, so the frame stays on one
  GPU. This mirrors the sharer's rule (owner, Oct 29).
- **No hardware decoder:**
  - Checked once, before the connection opens. Without one, the connection uses
    libwebrtc's own decoder, as in phase A.
  - A failure mid-share reopens the watch connection that way. The viewer loses about a
    second, once.
  - No second software decoder ships (builder's call). FFmpeg is built with the hwaccels
    only, so the H265 question in `PLAN.md` stays where it is.

### The sound

The owner's view (Nov 2): echo is not worth much effort. Most players wear headphones,
and a speaker user's game is heard in a share anyway.

**Rust plays the share's sound itself**, on the output the app has chosen, through the
mic test's playback code (`mic_test`: PulseAudio on Linux, WASAPI on Windows). It applies
the stream's volume, mute and deafen. Echo for watchers on speakers is accepted (owner,
Nov 2). It is also better sound than today: stereo and full band, where the call's
playback caps the share's sound at about 15 kHz (`CALLS.md`).

Probed Nov 2 and not chosen: mixing it into the call's playback through libwebrtc's render
hook (`RTCAudioProcessing::SetRenderPreProcessing`). A throwaway Flutter app on the vendored
flutter_webrtc sent its mic between two connections in one process, with the playback
going to a test sink whose monitor was the mic. The hook mixed in a signal at −23 dBFS:
- **It plays, and the echo canceller takes it out:** noise came back at −64 dBFS with
  echo cancellation on, and at −14 to −21 dBFS, feeding back, with it off. (A steady
  1 kHz tone was not taken out either way: the canceller cannot find the delay of a pure
  tone, so that was the wrong test signal.)
- **But it reaches the left channel only:** recorded off the test sink, left −24.8 dBFS,
  right −68.6. The hook is handed channel 0 of a stereo playback, and reaching the right
  would mean writing past that buffer on a guess about the prebuilt library's memory.
- It also runs at the playback's processing rate (32 kHz), the same 15 kHz cap.

### The server

A watch connection needs its own token, and so a change in `rift-self-host`:
`get_channel_token`, `get_dm_call_token`, the roster's `voiceUserId`, and `kick_user` /
`moderate_user`, with `API.md`.

- Asked with `watch: true`, the identity is `<userId>~<deviceId>_watch`.
- The grant:
  - `canPublish: false`.
  - `canSubscribe` under the same rules as the voice connection (not deafened, may
    listen).
  - `hidden: true`, so no client, old or new, ever shows it.
- **A hidden connection that can subscribe is what share tokens were stopped from being**
  (the `canSubscribe` comment in `get_channel_token`): somebody could sit in a call,
  hearing everything, appearing nowhere. So:
  - a watch token is minted only while that device's voice connection is in the room;
  - the roster and every token mint remove any `_watch` connection whose voice
    connection has gone;
  - a kick or moderation removes the watch connection with the voice one.

  What is left: a modified client could keep listening, hidden, after leaving, until the
  next roster read or join in that room. It could only hear what it already had the
  right to hear. **Accepted (owner, Nov 2)**; a sweep on a timer only if it ever matters.
- **Old servers:** a server without this would ignore `watch` and mint the voice identity
  itself, and joining with it would kick the watcher's own voice connection. The app
  checks the returned identity ends in `_watch` before connecting, and falls back to
  today's path if it does not.
- Shipping it needs a console release (owner's OK). Until a server has it, its watchers
  watch as today.

## Order

1. **Two small probes** on Linux: the sound hand-off, and `FlTextureGL` under Impeller.
   Done Nov 2 (above).
2. **Phase A on Linux:** the server token, the watch connection, the `FlTextureGL` and
   shader, the sound, and Dart's switch between the two paths. Measured against today.
3. **Phase B on Linux:** VAAPI on the Iris Xe, then NVDEC with the laptop on discrete.
   AMD by the AMD desktop's Claude.
4. **Windows** (phases A and B) by the Windows Claude, on the same Rust and Dart code
   with its own texture and decoder.

## Tests

- **Rust live tests** (`cargo test live_watch_ -- --ignored`), beside `gpu_live_test.rs`:
  - a test share is watched by a watch connection; every picture arrives and decodes;
  - the tear picture comes through clean;
  - a resize mid-share;
  - a late joiner;
  - a refused token falls back;
  - a hardware decoder failure falls back.
- **A/V drift:** the beep-and-flash rig from the stream A/V-sync work (Oct 4), measured
  on the Rust path against today's.
- **Server:** each repository's DB/function tests for the new token, a minted-only-while-
  in-the-call case, and the old-server identity check.
- **The app:** the measurement, the drawing places listed in *Goals*, and a game beside
  it. By hand, with the owner, recorded in `TESTING.md`.

## Open, for the owner

- Whether this step waits for the console release, or the app ships the path ready and
  each server picks it up when it updates (builder's view: the second; the fallback makes
  it safe).
