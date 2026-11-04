# Step 3 on Windows: GPU decode and draw for watchers — design

Nov 4 2026. Agreed by the owner Nov 4, with four changes from the review (the tearing
check moved first, the device asked for rather than passed through Dart, ducking, the
shader compiler in CI); phase A being built (the runner's drawing, Nov 4, which now
waits for its draw: *A read at once does tear*; the texture installed in the runner
and turned on in Dart; the sound through WASAPI, tested in Rust, and not turned
down beside Rift's own call; phase A driven in the app Nov 4, with the owner's pass by hand
and the game, tearing and device-loss runs done Nov 4 with phase B, in Discrete and
Hybrid).
Windows' half of step 3
(`STEP3_PLAN.md`), on the same Rust and Dart code Linux runs, with its own texture,
decoder and sound. What is the owner's is marked so; the rest is the builder's call.

## Why

Watching a 1080p60 H264 share on Windows costs about 117% of a core today (Oct 26,
`STEP3_PLAN.md`, *Why*), nearly all of it flutter_webrtc converting each picture to
RGBA on the CPU and Flutter uploading it. On Linux the same watch through Rust costs
about half of the call's path (`CALLS.md`, *Watching a share through Rust*). Gaming is
Rift's main use: what bothers people is a watcher's stream stuttering or lagging, and
watching costing their own game (owner).

**Success** is what `STEP3_PLAN.md` asks, measured on Windows the same way: the
watcher's cost against the call's path, a smooth picture, the sound no further from the
picture than today's, and a game beside it no worse.

## Where it starts (Nov 4)

- The branch builds on Windows with MSVC, the fork's pass-through decoder included
  (the link fix, `RIFT.md` patch 5 there, holds on a real Windows link).
- The unit tests pass. `live_watch_` passes as it is against `livekit-server --dev`
  on the laptop: a watched synthetic share arrives at its size and shade (VP8 at 30 a
  second), unwatching stops it, and a share sealed under a rotated key is read.
- The sound test (`live_watched_sound`) finds its sink through PulseAudio, so it is
  Linux only until the Windows player gives it a Windows check (it has one since, into
  VB-Cable).

## The texture

### The route: our own D3D11 device, a shared texture

Flutter on Windows draws with Impeller on OpenGL ES through ANGLE, on D3D11 (Flutter
3.47.7: the engine turns Impeller on unless told not to). A plugin texture there is a
`GpuSurfaceTexture`: on Flutter's raster thread the engine asks for a
`FlutterDesktopGpuSurfaceDescriptor`, and ANGLE wraps the D3D11 texture it names as a
pbuffer bound to a GL texture (`external_texture_d3d.cc`). Two kinds of handle:

- **An `ID3D11Texture2D`** must be on ANGLE's own device (`EGL_D3D_TEXTURE_ANGLE`).
  Flutter exports none of ANGLE's EGL functions (`flutter_windows.dll`'s export table),
  so the runner cannot reach that device. Not possible here.
- **A DXGI shared handle** (`EGL_D3D_TEXTURE_2D_SHARE_HANDLE_ANGLE`): a texture made
  with `D3D11_RESOURCE_MISC_SHARED` on any device of the same adapter, which ANGLE
  opens on its own. **This is the route.**

So the runner makes its own D3D11 device on the adapter Flutter draws with, and keeps one
BGRA texture per watched share, shared by handle. When Flutter asks, it takes Rust's
picture (`rift_watch_frame_lock`), draws it into that texture with a YUV→RGB pixel
shader, waits for the GPU to finish the draw, gives it back (`_unlock`) and answers the
handle. Linux's `populate` does the same with GL.

**One texture, not a ring.** Flutter keeps its pbuffer while the handle stays the same,
and makes a new one each time it changes. A ring of textures therefore costs a new
pbuffer every picture.

**No keyed mutex.** ANGLE only exposes a shared texture's keyed mutex for the app to
take (`SwapChain11`'s `getKeyedMutex`); it never acquires one itself. A keyed mutex on
the texture Flutter reads would sync nothing. media_kit's Windows video output orders
the two devices with a `Flush` alone (MIT, `angle_surface_manager.cc`: one shared BGRA
texture, `CopyResource`, `Flush`, no keyed mutex). That is not enough here: the runner
waits for its draw to finish before it answers (*A read at once does tear*, below).

**Probed Nov 4.** The probe is a throwaway Flutter 3.47.7 app, release build. It runs on
the laptop in Hybrid, where Flutter draws on the Iris Xe. A 1920×1080 I420 picture is
made on the CPU at 60 a second: four blocks and a moving bar. It is uploaded as three R8
textures and drawn by the shader into a shared BGRA texture on Flutter's adapter, matched
by LUID.

- **Right:** the four blocks came out (255,0,0), (1,255,2), (1,0,255) and
  (255,254,255), right side up.
- **On the raster thread:** the callback ran there, not on the platform thread.
- **Cost:** 0.50 ms a picture on average (p50 0.42 ms, p99 1.35 ms), upload included.
  A ring of three textures cost 0.56 ms on average, but 5.9 ms at p99.
- **No tearing:** in 300 screen grabs, the bar never sat at different columns at the
  top and the bottom of the picture.
- **No tearing under load either (Hybrid, Nov 4).** The whole route rests on the GPU
  finishing the runner's draw before ANGLE reads the texture, with only the `Flush`
  between them. So this was checked before anything was built on it (the plan's Task 0):
  - **CS2 behind the probe:** a match against bots on dust2, the owner's settings (cap
    400), on the RTX at 59–70% of its 3D engine while the probe was in front. 0 of 600
    grabs torn. Per block of 600 pictures, the draw took 0.48–0.52 ms at p50 and
    0.97–1.13 ms at p99; the longest was 31 ms, once, in the first block.
  - **The worst case, a load on Flutter's own GPU:** a scratch program keeping the Iris
    Xe's 3D engine busy with back-to-back 10–13 ms draws. 0 of 600 grabs torn. The draw
    took 0.38–0.39 ms at p50 and 0.62–0.79 ms at p99; the longest were 15 ms and 32 ms,
    once each, in two of the three blocks.
  - **The check can see a tear:** with every fourth picture torn on purpose (its bar 400
    columns apart in the bottom half), it found 68 of 300 grabs torn.

- **A read at once does tear (Nov 4, the plan's Task 1).** The runner's drawing has a test
  program (`windows/runner/test/`). It reads the texture back on a second device of the
  same adapter, the moment the draw returns, keeping the opened texture between reads as
  ANGLE keeps its pbuffer. Two 2560×1440 pictures were drawn in turn, 200 of them, with
  only a `Flush` after each:
  - **RTX:** 198 read wrong, nearly all half drawn: the new picture's bottom under the
    old one's top.
  - **Iris Xe:** 1 wrong.
  - **On a texture just made** (a new size), the RTX once read it all black.

  Through Flutter nothing tore, as above. Flutter's read comes later in its frame, but
  nothing promises that. **So the runner waits for its draw** before answering: a D3D11
  fence with an event, so the raster thread sleeps rather than spins, or an event query
  polled where there is no fence (Windows 10 before 1703). With the wait, 0 of 200 on both.
  At 1080p, `Draw` with its upload took p50 0.86 ms and p99 2.0 ms on the Iris Xe, and
  p50 0.70 ms and p99 2.6 ms on the RTX. Without the wait it was 0.47 and 1.9 ms, and
  0.18 and 2.6 ms.
- **Discrete (Nov 4, the plan's Task 11, with phase B's pictures):** Flutter, the
  decoder and CS2 all on the RTX. Watching a share of the moving bar through Rust (H264
  decoded through D3D11), the check grabbed the watcher's tile:
  - with nothing else running, 0 of 600 grabs torn (picture 1898×1080);
  - with CS2 in front and drawing (about 40% of the RTX's 3D engine), the watcher's
    window kept on top so its pictures stay on, 0 of 600 torn;
  - the check on the tile saw 74 of 300 torn on a page torn on purpose every fourth
    frame.
- **Hybrid (Nov 4, the same check with phase B's pictures):** Flutter and the decoder
  on the Iris Xe, CS2 on the RTX. H264 at 720p60 from a window share of the bar:
  0 of 600 grabs torn with nothing else running, 0 of 600 with CS2 running behind the
  watcher, and 0 of 600 with CS2 in front (the watcher's window kept on top).

### Which adapter, on a hybrid

The runner asks Flutter for its adapter (`FlutterDesktopPluginRegistrarGetGraphicsAdapter`)
and makes its device on the adapter with that LUID, never by index: step 1 saw the
index move while CS2 ran (`STEP1_WINDOWS.md`). The adapter is:

- **Hybrid:** the Iris Xe, where Flutter draws (Rift sets no GPU preference, so ANGLE
  takes the system's default adapter). The game is on the RTX, so watching decodes and
  draws on the GPU the game is not using. The plan's rule ("decode on the GPU Flutter
  draws with") gives that by itself.
- **Discrete:** the RTX, beside the game.

### Threads

| What | Thread |
|---|---|
| `create`, `dispose` (method channel) | the platform thread (the window's) |
| the device, made once on the first `create` | the platform thread |
| the descriptor callback: lock, draw, wait for the draw, unlock | Flutter's raster thread |
| Rust's mark | the decode thread or the runtime; the registrar posts it to the platform thread |
| freeing a texture's D3D resources | the raster thread, in `UnregisterTexture`'s callback |

The device's immediate context is used on the raster thread alone in phase A. The
close fence holds as on Linux: once Rust's `unwatch` returns nothing marks the
texture, and the runner frees the texture's object only when Flutter's unregister
callback says the engine has let it go.

**Read against the engine's sources** (3.47.7, `flutter_windows_texture_registrar.cc`
and `external_texture_d3d.cc`, Nov 4, the plan's Task 2):

- **Mark** may come from any thread: the registrar posts it to the platform thread.
  The runner still looks the texture up under its own lock first, so a mark after
  `dispose`, or after the window closed, does nothing.
- **Unregister** is posted twice: to the platform thread, which takes the id out of
  the engine, and to the raster thread, which deletes the engine's texture object
  (releasing ANGLE's surface on our texture) and then calls our callback there. The
  runner frees its `StreamDraw` in that callback. An engine that is stopping, and draws
  no more, calls back at once on the caller's thread instead.
- **Drawing:** the engine finds the texture object under its map's lock and then uses
  it with the lock released. That is safe because only a raster task removes it, and
  the raster thread is busy drawing.
- **The handle** is opened, and its `release_callback` called, inside the descriptor
  callback's frame. ANGLE keeps its surface, and with it a reference to our texture,
  until the handle changes. So a texture of a new size can never reuse the old one's
  handle while ANGLE still shows it.
- **A null descriptor** makes the engine let go of its surface and draw nothing there
  that frame. The runner answers null only once its device is lost.

The runner writes its lines to the app's log through `rift_runner_log`, a function of
Rust's library that it finds by name, so a lost device or a failed draw is in the file
people send.

## Phase A: libwebrtc's pictures, the texture and the sound

- **The runner** (`windows/runner/stream_texture.cpp`): the `rift/stream_texture`
  channel, as on Linux (`create` with Rust's lock and unlock, answering `textureId`,
  `mark` and `takesGpuPictures`; `dispose`). `IN_MEMORY` pictures are uploaded as
  three R8 textures (`UpdateSubresource`, 1.5 bytes a pixel) and drawn BT.601 limited,
  as on Linux. The shaders are compiled into the runner at build time, not at run time,
  by MSBuild's own HLSL step (the `.hlsl` files' `VS_SHADER_*` properties; one file per
  shader, since the step takes one entry point a file). Flutter's
  Windows build uses the Visual Studio generator, and so does `release.yml`'s, so the
  Windows SDK's `fxc` is found the same way on the laptop and in CI.
- **Colour:** the same matrix and range sums as `stream_texture.cc`'s `Colour`, in
  HLSL.
- **The sound** (`rust/src/watching/sound/windows.rs`): a WASAPI render stream, shared
  mode with conversion, 48 kHz stereo, on the output chosen in settings (the device id
  as WebRTC lists it, looked up as the mic test does, `audio_endpoints::device_by_id`;
  the default when it is gone), reopened when the output changes. The mic test's
  playback is the model, including its lesson that Windows' engine empties the buffer
  in uneven gulps: room is counted from the padding, about 60 ms held as on Linux, and
  a short cushion of silence when it ran dry. `PLAYS` becomes true on Windows.
- **Ducking:** Windows turns other sounds down while a communications stream plays, by
  18 dB measured (`CALLS.md`, *Windows turning other apps down*). A call's playback is
  such a stream. Through the call, the share's sound is part of it, so it is never
  turned down; Rust's own stream might be. It is measured against the call's path. If
  Windows ducks it, the stream is tagged as communications, or joins the call's audio
  session, whichever the measurement shows works. Measured Nov 4: it does not. Windows
  spares every stream of the process whose call it is (0 dB beside a call in the same
  process, 18 dB down beside another process's), so nothing is needed.
- **Dart:** `RustWatch.available` takes Windows too. Nothing else in the cubit is
  platform-specific.
- **The sound test** gets a Windows check: played into VB-Cable only (never the
  speakers), recorded from VB-Cable's other end, with the same levels, ears and
  volumes as on Linux.

## Phase B: decoding on the GPU

### One device for decoding and drawing

The handoff asked how a picture crosses from the decoder's device to the drawing one.
On Windows the drawing device is the runner's own, not ANGLE's, so it can simply be the
decoder's device too: **the decoder decodes on the runner's device**. Then the decoded
surface is sampled where it lies, nothing crosses devices but the finished BGRA
picture, and the order of decoding and drawing is the one queue's. This is how
Moonlight's `d3d11va.cpp` (GPL-3.0) works: it binds the decoder's own texture-array
slices to its shader. Rift's licence allows taking that code. Two rejected options:

- **A copy into a shared NV12 texture with a keyed mutex**, between a decoder device and
  the runner's: it works, but costs a copy and a second device for nothing.
- **Decoding on ANGLE's device:** it cannot be reached (above).

How:

- **The device.** The runner makes its device with video support and multithread
  protection (`ID3D10Multithread`), since the decode thread and the raster thread both
  use it. That lock is also FFmpeg's (ffdec sets it as the device context's), and the
  runner holds it through each draw up to its flush, so neither side's sequence of
  calls on the immediate context is cut into by the other's. **Rust asks the runner for it**, and it never passes through Dart. The runner
  exe exports `rift_stream_d3d11_device()`, which returns the device with a reference
  added, or null when there is none or it was lost. Rust finds it with
  `GetProcAddress` on the exe when it opens a decoder, and hands it to ffdec. The
  decoder holds that reference until it closes. So a device lost in between is still a
  live object whose calls fail, and no address can outlive what it names; an address
  carried through Dart could have. The bridge does not change.
- **ffdec** (`RIFT_FFDEC_D3D11VA`): an `AVD3D11VADeviceContext` on that device (ffdec
  holds a reference), with FFmpeg's `d3d11va` hwaccel. The surfaces are made with
  `D3D11_BIND_SHADER_RESOURCE` as well as `DECODER`, so the shader can read them. A
  picture leaves as a new kind, `IN_D3D11`: the texture array and its slice, the
  matrix and range from the stream. `extra_hw_frames = LENT_PICTURES`, as on Linux.
  `RIFT_FFENC_ABI` goes to 12.
- **The runner** makes an R8 and an R8G8 view of the slice (NV12's two planes), cached
  per texture and slice, and draws them through the NV12 shader. A surface is lent
  only for the draw on the raster thread, then handed back. Where a GPU cannot make
  shader views of decoder surfaces (Moonlight checks with
  `CheckFormatSupport`), the runner copies the slice into a texture of its own first,
  as Moonlight does.
- **Choosing at start** (`decode::choose`, before any room): Rust looks at the adapter
  ANGLE will take (the system default, adapter 0 for this process) and asks its D3D11
  video device for decoder profiles. With H264 or VP9 there, the runtime goes
  pass-through, as on Linux. The runner's `create` checks that its adapter is that one
  (`takesGpuPictures`). If it is not, Rust refuses the watch, as Linux does under X11,
  and the call's path is taken.
- **What the GPU decodes.** Asked of the device, not assumed (`Gpu::decodes`). Probed
  Nov 4 on the laptop: the Iris Xe and the RTX 3070 Ti both list H264 (NV12) and VP9
  profile 0, and neither lists VP8. FFmpeg has no VP8 `d3d11va` hwaccel anyway. So on
  Windows a VP8 share fails by name (`the GPU cannot decode this Vp8`) and goes back
  to the call's connection, as on AMD's Linux. `live_gpu_watch` already expects that of
  a codec the device lacks.
- **FFmpeg's build:** Windows' `build.sh` branch builds `ffdec.c` too, which it does not
  yet, with `--enable-decoder=h264,vp9` and `--enable-hwaccel=h264_d3d11va2,vp9_d3d11va2`
  (the forms that take a frames context of D3D11 textures).

## Fallback

Each of these falls back to the call's connection once, with a line in the log, the
same way as on Linux (`session::lost`, `_fallBackFromRust`):

| What | How it is seen |
|---|---|
| No device on Flutter's adapter | `create` answers no texture; the share is watched the call's way |
| The runner's adapter is not the decoder's | `takesGpuPictures` false; Rust refuses the watch |
| A codec the GPU lacks (VP8 on Windows) | the decoder fails by name |
| A picture that will not decode | three keyframes, then give up (`Chain`, as on Linux) |
| A draw that fails, the device removed, a view that cannot be made | the runner hands the picture back undrawn (`unlock` with 0) |

**Device loss** includes a TDR, a driver update and a game changing display mode. The
runner checks `GetDeviceRemovedReason` before each draw. Once the device is gone, it
hands the picture back undrawn and stops answering a handle. Rust then sends the call
back to its own connection, and the tile shows the call's renderer instead of freezing.
The next `create` (the next call) makes a new device. Undrawn has meant "a GPU picture
that would not import" until now; it now covers in-memory pictures on Windows too, so
`frames.rs`'s log line says "a picture" instead of "a picture decoded on the GPU".

ANGLE's own device lost is Flutter's to recover, and is out of scope: Flutter on
Windows does not recover from it today, with or without this.

## What was read, and what came from where

- **Flutter's engine** (3.47.7): `external_texture_d3d.cc` (the pbuffer per handle,
  bound once), `flutter_windows_texture_registrar.cc` (mark posts to the platform
  thread; unregister finishes on the raster thread), `egl/manager.cc` (ANGLE on D3D11,
  the adapter by preference or the default).
- **ANGLE** (`SwapChain11.cpp`): a shared handle opened with `OpenSharedResource`; the
  keyed mutex only exposed, never taken.
- **media_kit** (MIT), `angle_surface_manager.cc`: the shared BGRA texture handed to
  Flutter. The handover only; its own ANGLE context is not needed here.
- **Moonlight** (GPL-3.0), `d3d11va.cpp`: FFmpeg's `d3d11va` on a device of its own,
  shader views of decoder surfaces, the copy where a GPU cannot, and its YUV shaders.
  Code taken from it keeps its notice.
- **mpv's** D3D11 hwdec files: their licence is checked file by file before any line
  is taken. mpv's own route goes through ANGLE's EGL streams, which Rift cannot reach,
  so it is reading only.

## How it is proven

Every number says which BIOS mode it came from. Hybrid first, then Discrete.

1. **Rust:** `live_watch_` (passing, Nov 4); `live_watched_sound` into VB-Cable;
   `live_gpu_watch` once `d3d11va` exists (H264 and VP9 decoded on the GPU; VP8 fails
   by name). Passing Nov 4 on the Iris Xe, Hybrid: VP9 88 and H264 89 of 90 pictures in
   3 s, VP8 given up by name, every reference to the device handed back. Passing Nov 4
   on the RTX, Discrete: VP9 89 and H264 90.
2. **ffdec alone:** a Windows test beside `test_ffdec.c`, modelled on `test_d3d11.c`
   and `test_windows.sh`: the four colours back at 1920×1080 from H264 and VP9,
   decoded on a device made the runner's way and drawn by the runner's shader.
   As built (`test_ffdec_d3d11.c`, `test_ffdec_windows.sh`), it reads the colours back
   from the decoder's slices and the runner's drawing has its own test of NV12 slices
   (`stream_draw_test`). Both pass on the Iris Xe and the RTX 3070 Ti, Hybrid, Nov 4.
3. **The probe under load, first:** the tearing check with CS2 running, and with a load
   program on Flutter's own GPU. Hybrid before anything is built (passed Nov 4, above);
   Discrete before phase B. Then again with the decoder's pictures, in both modes
   (both passed Nov 4, *The route*, above). The
   drawing's own test reads every picture back on a second device the moment it is drawn
   (`windows/runner/test/run.ps1`, on each adapter).
4. **The app** (owner by hand, release build; two clients with their own
   `RIFT_PROFILE`s against the Docker stack, handoff §5):
   - H264 and VP9 at 1080p60, a window share and a whole-screen share;
   - a resize, minimising and restoring the watcher, a second monitor if there is one;
   - leaving and rejoining, and the first Watch after joining from the sidebar;
   - a late viewer's wait, through Rust and through the call, each named;
   - volume, mute and deafen;
   - the sound's level through Rust and through the call, in a call, within 1 dB
     (ducking);
   - Quit from the tray while watching.

   The log must name the decoder and the texture each time, so a pass is known to
   be the path it is meant to be.

   Done Nov 4 in Hybrid with phase B (`TESTING.md`), all but a second monitor (none was
   attached). The sound's level was measured later the same day: −20.00 dBFS through
   Rust and −20.02 through the call for a −20.0 tone (`CALLS.md`). The volume, mute and
   deafen were measured from VB-Cable rather than heard.
5. **Cost:** the watcher's threads over 20 s per case, through Rust,
   `RIFT_WATCH_DECODE=cpu` and `RIFT_WATCH_PATH=call`, in a table like `CALLS.md`'s.
   A viewer on the same PC counts in any game-cost figure, so the figure says so.
   Done Nov 4 in Hybrid, the whole process rather than by thread (`CALLS.md`).
6. **The watcher's game (the gate):** CS2 with no watch, watching through the call, and
   watching through Rust. Capped and uncapped, Hybrid and Discrete. Each reports the
   mean, the p99, the frames over twice the target, the stream's rate and any freeze
   over 50 ms. Sharing's gate was 0.2 ms added a game frame; the owner judges.

   Done Nov 4 in Discrete (`CALLS.md`, *Watching a share through Rust*): through Rust
   0.22 ms added a frame uncapped, through the call 0.43 ms, no frame over 16.7 ms while
   watching; capped at 120, every case held 118–120. CS2 ran in a 1280×720 window beside
   the watcher's, since a game covering Rift turns the pictures off. The stream's rate
   and freezes over 50 ms were not recorded.

   Done Nov 4 in Hybrid the same way: through Rust about 1.2 ms added a frame
   uncapped, through the call about 1.7 ms, against 6.9–7.4 ms not watching. CS2
   ran at about half its Discrete rate watched or not, and frames over 16.7 ms came in
   every case, watching or not, more often watching through the call; capped at 120,
   no case held it, not watching included.
7. **Device loss:** `dxcap -forcetdr` in Discrete, as in step 1. The tile goes back to
   the call's renderer and does not freeze.

   Done Nov 4, watching H264 through Rust. The sharer's NVENC died with
   the reset and it went on in VP9 by itself. A second later the watcher found the
   runner's device gone and went back to the call's path ("the window has no GPU
   device"), which then holds for the rest of that call. Both Rift windows drew white, then
   black, as in step 1: Flutter's own device lost, which it does not recover from. So the
   tile's picture could not be seen moving. Rift started again watched through Rust at
   once (VP9 on the RTX through D3D11).

## What is not known yet

- The stream's own rate and freezes beside a game on the laptop, in either mode. Measured on
  the AMD desktop Nov 5: 60 a second and no freeze over 50 ms, through Rust and through the
  call (`STEP3_AMD.md`, *On Windows*).
- What holds CS2 to half its Discrete rate in Hybrid, watched or not: the RTX is busy
  only 2.3–3.0 ms of its 7 ms frames.
- The shader step on GitHub's `windows-latest`, until the first release run after it.
- Whether every driver makes shader views of decoder surfaces. Moonlight's check and
  copy cover it; which GPUs take the copy is to be seen. The Iris Xe, the RTX 3070 Ti and the
  RX 9070 XT all make the views.
- Multithread protection's cost on the raster thread while the decoder runs.
- The server: watching through Rust in the app needs rift-self-host `dev` 604f8c4 or
  later, run here in Docker Desktop since Nov 4.
- AMD on Windows beyond the RX 9070 XT. That card was run Nov 5 (`STEP3_AMD.md`, *On
  Windows*): it makes shader views of decoder surfaces, so the runner reads them directly;
  H264 and VP9 decode through D3D11 and VP8 falls back by name; 0 of 600 grabs torn with CS2
  in front; 0.13 ms added to a game frame through Rust against 0.34 ms through the call, the
  stream at 60 a second with no freeze over 50 ms on either path. No GPU here has taken the
  copy yet.

## What Linux must recheck

Nothing here was built or run on Linux: every change was made and tested on the
Windows laptop. Shared structs grew at the end and the bridge did not change, so Linux
should behave as before, but only a Linux run shows that. On the Linux machine, on
`gpu-codecs` from `fe4f0af8` on:

1. **The build:** `native/ffenc/build.sh`, then `flutter build linux --release`. The
   library's ABI is 12 now, so a `librift_ffenc.so` from before is refused by name.
2. **Rust:** `cargo test --release`, then `live_watch_` against `livekit-server --dev`
   (the module doc in `rust/src/watching/live_test.rs`).
3. **The sound test:** `live_watched_sound` into the null sink, as the module doc
   says. It was rebuilt to take a Windows check beside Linux's, so Linux's half (the
   sink found through PulseAudio, the levels, ears and volumes) runs a changed body.
4. **`live_gpu_watch`** on VAAPI (Intel or AMD) and on CUDA (NVIDIA): `WatchPlanes`
   and `RiftFfdecConfig` and `RiftFfdecPicture` each grew two fields at the end, and
   `ffdec.c`'s choice of format changed shape (the same choice on Linux). A layout
   that disagreed would show as a black or garbled share, or a crash in the runner.
5. **`cargo xwin check`** for Windows, as before.
6. **In the app,** once: a share watched through Rust on the GPU, H264 or VP9, with its
   sound. The log line when the runner cannot draw a picture now reads "the window
   could not draw a picture", without "decoded on the GPU".

The shared files, from `fe4f0af8`:

- `rust/src/watching/frames.rs`: the `IN_D3D11` kind and the `texture` and `slice`
  fields at the end of `WatchPlanes`; the unlock log line.
- `linux/runner/stream_texture.cc`: the same two fields, appended so Linux's layout
  keeps its order.
- `native/ffenc/ffdec.c` and `ffdec.h`: `RIFT_FFDEC_D3D11VA`, `IN_D3D11`, the D3D11
  fields at the end of the config and the picture; Linux's includes and the CUDA copy
  behind `__linux__`; `get_format`'s loop.
- `native/ffenc/ffenc.h` and `rust/src/screenshare/encoder/ffmpeg.rs`: ABI 12.
- `native/ffenc/build.sh`: Windows' decoder and hwaccel list only; Linux's branch is
  unchanged.
- `rust/src/watching/decode/mod.rs` and `linux.rs`: Windows' module beside Linux's;
  Linux's config and picture carry the new fields as null.
- `rust/src/watching/sound/mod.rs`: Windows' module beside Linux's.
- `rust/src/watching/live_test.rs`: the sound test's body, shared with Windows.
- `rust/src/logging.rs`: `rift_runner_log`, an export Linux's runner does not use.
- `lib/logic/services/rust_watch.dart`: Windows in `available`.
