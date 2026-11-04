# Watching through Rust on Windows — implementation plan

> **For agentic workers:** steps use checkbox (`- [ ]`) syntax for tracking. Test first: see each new
> test fail, then make it pass, one commit per logical change.

**Goal:** Windows watches a share through the Rust watch connection, as Linux does: the picture drawn on the
GPU into a texture Flutter shows (phase A), then decoded on the GPU too (phase B), with Rust playing its sound.
Measured against the call's path, and with a game beside it.

**Architecture** (`STEP3_WINDOWS.md`): the runner makes one D3D11 device on the adapter Flutter draws with, matched
by LUID. Each watched share has one shared BGRA texture, which Flutter reads by DXGI handle. On Flutter's raster
thread, the runner borrows Rust's newest picture (`rift_watch_frame_lock`), draws it with a YUV→RGB shader,
`Flush`es and hands it back. In phase B, ffdec decodes with FFmpeg's `d3d11va` on that same device, and the
runner samples the decoder's surface where it lies. The sound plays through WASAPI. Rust's session and Dart's
cubit are Linux's, unchanged but for small additions.

**Tech stack:**
- C++ in the runner: D3D11, Flutter's `GpuSurfaceTexture`, HLSL compiled by `fxc` at build time.
- C in ffdec: FFmpeg 9.0.2's `hwcontext_d3d11va` and the `d3d11va` hwaccels.
- Rust: `wasapi`, the `windows` crate, `watching`.
- Dart: `RustWatch`.

**Spec:** `docs/gpu-codecs/STEP3_WINDOWS.md`, and `STEP3_PLAN.md` behind it. Read both first.

## Global Constraints

- **Git:**
  - Branch `gpu-codecs`; commit locally per task. Pushes are the owner's.
  - Stage named paths; never `git stash`. No attribution lines.
  - The LiveKit fork is public: anything in it waits for the owner. No fork change is planned.
- **The owner's priority:**
  - Watching must be smooth, and must not cost the watcher's own game.
  - Every failure lands on the call's connection, once, with a line in the log.
  - Nothing may freeze a tile, crash, hang on quit or take the call down.
- **Machines without any of this keep watching as today:** no D3D11 video, Windows 10, an old driver, a server
  without watch connections.
- **Shared files must still build on Linux,** which can't be run here:
  - Per-OS code sits in its own file, gated at the `mod` line.
  - Shared structs only grow at the end.
  - `stream_texture.cc` follows any `WatchPlanes` change.
- **The ABI moves only for phase B:** `RIFT_FFENC_ABI` and `ABI` in `ffmpeg.rs` go from 11 to 12 once, in the
  task that changes `ffdec.h`.
- **Colour:**
  - libwebrtc's pictures are drawn BT.601 limited, as on Linux.
  - The GPU decoder's pictures are drawn in the matrix and range the stream says.
- **Before each commit:**
  - `cargo test --release`, `cargo fmt --check` and `flutter analyze` are clean.
  - `CALLS.md`, `TESTING.md` and `STEP3_PLAN.md` change in the commit that changes behaviour or proves it.
  - No machine paths in docs.
- **Sound:** test audio goes to VB-Cable only, never the speakers.
- **Processes:**
  - Kill by PID only.
  - Never kill or launch the owner's own Rift; test clients use `RIFT_PROFILE`.
  - Leave test clients running at the end.
- **Asked for, not done:**
  - Installs (Docker Desktop included), admin actions and BIOS changes are the owner's.
  - Give the exact command with `!`.
- **After any Rust change,** run `cargo build --release --target x86_64-pc-windows-msvc` before `flutter build`,
  and check the DLL's time.
- **Every measured number names its BIOS mode** (Hybrid or Discrete) and its path (Rust or call).

## Decisions this plan makes

- **The device is the runner's, one per process.** It is made on the first `create`, on Flutter's adapter by
  LUID. Video support and multithread protection are on from the start, so phase B needs no second device.
  It is let go only when it is lost.
- **One texture per share, no ring.** The probe: the ring's p99 was 5.9 ms against 1.35 ms.
- **The shaders are compiled at build time.** `fxc` writes a header the runner includes, so no
  `d3dcompiler_47.dll` is loaded at run time.
- **The runner's drawing is a part with no Flutter in it** (`stream_draw.{h,cpp}`), so a test program can drive
  it: draw, read back, check the colours. `stream_texture.cpp` is only the channel, the registrar and the
  lifetimes.
- **Device loss in a test build is simulated** with `RIFT_STREAM_TEXTURE_FAIL_AFTER=<n>`: after n pictures, the
  runner answers as if the device were removed. A real reset (`dxcap -forcetdr`) is the owner's by-hand step,
  as in step 1.
- **The device goes to Rust through Dart:**
  - `create` answers `device`, its address.
  - `watchShare` takes it as `gpuDevice` (0 on Linux, and in phase A).
  - Rust keeps it with the share, and opens that share's decoder on it.

  This is the only change to the bridge. Phase A ships without it.
- **Choosing at start:** Rust looks at adapter 0 (the one ANGLE takes, Rift setting no GPU preference) and asks
  its video device which profiles it has. With H264 or VP9 there, the runtime is made pass-through. The runner's
  `takesGpuPictures` is true only when its adapter's LUID is that one.
- **VP8 is not decoded on the GPU on Windows.** Neither GPU offers it and FFmpeg has no `d3d11va` hwaccel for
  it, so it fails by name and falls back, as on AMD's Linux. `--enable-decoder` on Windows is `h264,vp9`.

## Review Focus

- **The close fence:** once `unwatchShare` returns nothing marks the texture, and the runner frees the
  texture's object only in `UnregisterTexture`'s callback, on the raster thread (Task 2).
- **Threads:** the immediate context is used on the raster thread and, in phase B, by FFmpeg on the decode
  thread, under multithread protection. Nothing D3D is called on the platform thread except making the device
  and the textures (Tasks 2, 7).
- **Device loss:** the tile goes back to the call's renderer and never freezes. A lost device is not used again
  (Tasks 2, 9).
- **Lent surfaces:** a decoder surface is held only for the draw. FFmpeg's pool is `LENT_PICTURES` larger, so a
  slow draw never stalls decoding (Task 7).
- **Linux untouched:** shared structs grow at the end. Linux passes `gpuDevice` 0. `cargo xwin` on Linux still
  builds Windows (Tasks 6, 8).

---

## Phase A

### Task 1: The runner's drawing, tested alone

**Files:**
- Create: `windows/runner/stream_draw.h`, `windows/runner/stream_draw.cpp`, `windows/runner/stream_shaders.hlsl`
- Create: `windows/runner/test/stream_draw_test.cpp`, `windows/runner/test/run.ps1` (builds the test with
  `cl` and runs it; no Flutter)
- Modify: `windows/runner/CMakeLists.txt` (the sources, `fxc` as a custom command, `d3d11` and `dxgi`)

**Interfaces:**
- ```cpp
  // The device on the adapter with `luid`, with video support and multithread
  // protection; null with the reason logged.
  ComPtr<ID3D11Device> MakeDevice(LUID luid);
  // One share's picture: a shared BGRA texture, its shared handle, and what
  // drawing into it needs, sized to the picture as it comes.
  class StreamDraw {
   public:
    explicit StreamDraw(ID3D11Device* device);
    // Draws `planes` (WatchPlanes, IN_MEMORY now; IN_D3D11 in Task 9) and
    // flushes. False when it could not, the device removed included.
    bool Draw(const WatchPlanes& planes);
    HANDLE handle() const;
    uint32_t width() const, height() const;
  };
  ```
- The colour sums are those of `stream_texture.cc`'s `Colour`, passed as a constant buffer.

- [ ] **Step 1: The failing test.** `stream_draw_test.cpp` makes a device on adapter 0. It draws a 1920×1080
  I420 picture of four blocks (BT.601 limited: red, green, blue, white) and reads the BGRA texture back
  through a staging copy. Checks:
  - each block's centre is within 2 of (255,0,0), (0,255,0), (0,0,255) and (255,255,255);
  - row 0 is the top;
  - a second picture at 1280×720 resizes the texture;
  - odd sizes (1279×719) draw, with the chroma rounded up.
- [ ] **Step 2: Run it to see it fail** (`run.ps1`: it does not link yet).
- [ ] **Step 3: Implement** `MakeDevice` and `StreamDraw` for `IN_MEMORY`, and the `fxc` step.
- [ ] **Step 4: Run it on both adapters:** the Iris Xe and the RTX, in Hybrid. Record the colours.
- [ ] **Step 5: Commit.**

### Task 2: The stream texture in the runner

**Files:**
- Create: `windows/runner/stream_texture.h`, `windows/runner/stream_texture.cpp`
- Modify: `windows/runner/flutter_window.cpp` (install it, keep a `PluginRegistrarWindows` alive),
  `windows/runner/CMakeLists.txt` (`flutter_wrapper_plugin`)

**Interfaces:**
- The `rift/stream_texture` channel, as on Linux:
  - `create` `{lock, unlock}` answers `{textureId, mark, takesGpuPictures}`;
  - `dispose` `{textureId}`.
- `rift_stream_texture_mark(uint64_t)` looks the texture up under a lock and calls
  `MarkTextureFrameAvailable`; a texture already gone is nothing.
- The callback runs on the raster thread:
  - lock; on a new picture, `Draw`; then unlock with `drawn`;
  - it answers the descriptor, or null when there is no texture yet and no device.
  - Before the first picture it answers a 1×1 black texture, as Linux's `DrawBlack`.
- `dispose` takes the texture out of the live map, then calls `UnregisterTexture(id, callback)`. The callback
  frees the `StreamDraw` on the raster thread.
- `RIFT_STREAM_TEXTURE_FAIL_AFTER=<n>`: test builds only (an `#ifndef NDEBUG` or a build flag, decided in the
  task, never in a release). After n draws, `Draw` reports the device removed.
- Device removed (`GetDeviceRemovedReason`, or the hook):
  - unlock with 0;
  - a one-time warning;
  - the device is let go for the process;
  - the next `create` makes a new one.

- [ ] **Step 1: Build the runner** with the texture installed and `RustWatch.available` still Linux only. The
  app starts and nothing changes.
- [ ] **Step 2: Read the lifetimes against the engine's sources:**
  - mark from any thread;
  - unregister finishes on the raster thread;
  - `PopulateTexture` holds the texture's raw pointer only under the registrar's raster task.

  Write down where each call runs.
- [ ] **Step 3: Commit.**

### Task 3: Dart turns it on for Windows

**Files:**
- Modify: `lib/logic/services/rust_watch.dart` (`available`: Linux or Windows), and its doc comment, which names
  the Windows runner's file

- [ ] **Step 1:** Change `available`. Run `flutter analyze` and `flutter test`.
- [ ] **Step 2: Commit** with `CALLS.md` (*Watching a share through Rust*: Windows in the first list, the texture
  route in two sentences). Mark it built, not yet driven.

### Task 4: The share's sound through WASAPI

**Files:**
- Create: `rust/src/watching/sound/windows.rs`
- Modify: `rust/src/watching/sound/mod.rs` (the `mod` lines; `output()` and `output_changes()` lose their
  `allow(dead_code)` on Windows), `rust/src/watching/live_test.rs` (the sound test's Windows check)

**Interfaces:**
- `pub(crate) const PLAYS: bool = true;` and `pub(super) fn run(frames: Receiver<Vec<i16>>, gain: &Gain)`.
- The render stream:
  - shared mode with conversion, 48 kHz, 16-bit stereo;
  - on `audio_endpoints::device_by_id(Render, id)`, or the default when the id is gone;
  - reopened when `output_changes()` moves.
- Pure, and unit-tested: `room(queued, held) -> usize` and the cushion of silence after running dry. The mic
  test's lesson stands: count room from the padding, never trust the buffer size alone.

- [ ] **Step 1: The failing unit tests** for the room and the cushion:
  - empty: the cushion, then the frame;
  - full: nothing;
  - part full: whole frames only.
- [ ] **Step 2: Run to see them fail; implement; pass.**
- [ ] **Step 3: The live test on Windows.** `live_watched_sound` gets a Windows check:
  - The output is VB-Cable's input, by name.
  - It asserts the name contains `CABLE` and is not the default output.
  - It records VB-Cable's output through WASAPI capture in the same test.
  - It checks, as on Linux:
    - the tone in the left ear, then the right, at the level sent (±1 dB);
    - nothing at volume 0;
    - 6 dB down at half;
    - silent once unwatched.

  See it fail with `PLAYS` false, then pass.
- [ ] **Step 4: `cargo test --release`, `cargo fmt --check`, commit** with `CALLS.md` (the sound on Windows).

### Task 5: The server for the app (owner)

- [ ] **Step 1:** Ask the owner to install Docker Desktop. Give the command; do not run it.
- [ ] **Step 2:** Bring up rift-self-host's stack (`dev`, 604f8c4 or later).
  - Copy `_shared`, `get_channel_token`, `get_dm_call_token`, `moderate_user`, `voice_roster` and
    `livekit_webhook` into the functions container, then restart it.
  - `diff` the copy against the repository.
  - Write a script that redoes the copy, since the console copies its old functions back on every start.
- [ ] **Step 3:** Two test profiles join a channel on it.
  - Check the watcher's log does not say `the server does not mint watch connections`.
  - Check the server's log shows the `_watch` identity joining.

### Task 6: Phase A in the app, measured

- [ ] **Step 1: Release build** (`scripts/build_windows.ps1`, after the Rust build). Two clients on the stack:
  `RIFT_PROFILE=a` sharing, `RIFT_PROFILE=b` watching.
- [ ] **Step 2: The watcher's log names the path:**
  - `watching ... through Rust`;
  - `shares decode on the CPU`;
  - `watching: picture WxH`.
- [ ] **Step 3: By hand with the owner** (numbered steps for the owner):
  - H264 and VP9, 1080p60, a window share and a whole-screen share;
  - resize; minimise and restore the watcher;
  - leave and rejoin; the first Watch after joining from the sidebar;
  - volume, mute and deafen;
  - Quit from the tray while watching.
- [ ] **Step 4: Device loss, simulated.** `RIFT_STREAM_TEXTURE_FAIL_AFTER=300` in a test build:
  - the log says the window could not draw;
  - the tile is back on the call's renderer within a second, moving, not frozen.
- [ ] **Step 5: Cost,** Hybrid. The watcher's threads over 20 s, three runs each:
  - through Rust (CPU decode);
  - `RIFT_WATCH_PATH=call`.

  H264 and VP9 at 1080p. A sharer on the same PC is named in the table.
- [ ] **Step 6: Commit** with `TESTING.md` row 26 and `CALLS.md` (what was driven, the cost table, what was not).

## Phase B

### Task 7: ffdec on D3D11

**Files:**
- Modify: `native/ffenc/ffdec.h`, `native/ffenc/ffdec.c`, `native/ffenc/ffenc.h` (ABI 12),
  `native/ffenc/build.sh` (Windows: `ffdec.c` built, `--enable-decoder=h264,vp9`,
  `--enable-hwaccel=h264_d3d11va2,vp9_d3d11va2`),
  `rust/src/screenshare/encoder/ffmpeg.rs` (`ABI`)
- Create: `native/ffenc/test_ffdec_d3d11.c`, `native/ffenc/test_ffdec_windows.sh`

**Interfaces:**
- ```c
  RIFT_FFDEC_D3D11VA = 2,        // RiftFfdecApi
  RIFT_FFDEC_IN_D3D11 = 2,       // RiftFfdecMemory
  // RiftFfdecConfig, appended:
  void* d3d11_device;            // the runner's ID3D11Device; ffdec holds a reference
  // RiftFfdecPicture, appended:
  void* d3d11_texture;           // the decoder's ID3D11Texture2D array
  int32_t d3d11_slice;           // and the picture's slice in it
  ```
- The frames context is FFmpeg's own pool:
  - `BindFlags` is `DECODER | SHADER_RESOURCE` where the device allows shader views of NV12 decoder
    surfaces (`CheckFormatSupport`);
  - otherwise `DECODER` alone, and the runner copies (Task 9).
- The picture carries the matrix and range from the stream, as on Linux.
- VP8 on Windows answers `AVERROR(ENOSYS)`.

- [ ] **Step 1: The failing test,** `test_ffdec_d3d11.c`:
  - It makes a device the way `MakeDevice` does.
  - It encodes four blocks at 1920×1080 with `h264_nvenc` or `h264_qsv`, whichever opens, and with the
    library's VP9 if none does; otherwise it takes a stream file from `test_ffdec.c`'s set.
  - It decodes them through `rift_ffdec_*` on that device.
  - It copies the slice to staging and checks the four colours in NV12.
  - It checks VP8 fails with `ENOSYS`.
- [ ] **Step 2: See it fail** (no `RIFT_FFDEC_D3D11VA`). Implement. Build with `build.sh` in MSYS2 UCRT64 and
  pass on the Iris Xe, then the RTX.
- [ ] **Step 3: Check the stamp and the ABI.** An old DLL is refused with the ABI message, not a crash.
- [ ] **Step 4: Commit.**

### Task 8: Rust decodes on the runner's device

**Files:**
- Create: `rust/src/watching/decode/windows.rs`
- Modify:
  - `rust/src/watching/decode/mod.rs`: the `mod` lines; `feed` and `Decoder::open` take the share's device,
    which Linux ignores.
  - `rust/src/watching/frames.rs`: `IN_D3D11`; `texture` and `slice` appended to `WatchPlanes`; the unlock log
    line without "decoded on the GPU".
  - `rust/src/watching/session.rs`: `gpu_device` kept per share.
  - `rust/src/api/watching.rs`: `watch_share(..., gpu_device: usize)`.
  - Regenerated bindings: `lib/src/rust/`, `rust/src/frb_generated.rs`.
  - `lib/logic/services/rust_watch.dart`: passes `device`.
  - `linux/runner/stream_texture.cc`: the appended fields.

**Interfaces:**
- ```rust
  pub(crate) struct Gpu { luid: i64, name: String, h264: bool, vp9: bool }
  pub(super) fn device() -> Result<Gpu, String>;  // adapter 0's video profiles; Err with none
  impl Gpu { pub(crate) fn decodes(&self, codec: Codec) -> Option<bool>; }  // VP8: Some(false)
  ```
- `watch` refuses when `decode::gpu()` is some and `takes_gpu_pictures` is false, or `gpu_device` is 0, as on
  Linux.

- [ ] **Step 1: The failing unit tests:**
  - `decodes` from a profile list (pure: a list of GUIDs in, the answer out);
  - `watch` refusing a share with no device when decoding on the GPU (`session`'s refusal, without a server).
- [ ] **Step 2: See them fail; implement; pass.** Regenerate the bindings (flutter_rust_bridge 2.13.0).
  `flutter analyze`.
- [ ] **Step 3: `live_gpu_watch` on Windows.**
  - The test hands a device made as the runner makes it.
  - `lent_from_the_gpu` checks the `IN_D3D11` picture: a texture, a slice within the array, the size sent.
  - H264 and VP9 decode at 80% or more of the pictures sent; VP8 fails with
    `the GPU cannot decode this Vp8`.
  - Run it in Hybrid on the Iris Xe. The RTX's turn is in Task 11.
- [ ] **Step 4: Commit.** The Linux side's recheck list gets this task's shared files.

### Task 9: The runner draws decoded surfaces

**Files:**
- Modify: `windows/runner/stream_draw.{h,cpp}` (NV12 from a slice: R8 and R8G8 views, cached per texture and
  slice; the copy where views cannot be made), `windows/runner/stream_texture.cpp` (`device` in `create`'s
  answer; `takesGpuPictures` from the LUID), `windows/runner/test/stream_draw_test.cpp`

- [ ] **Step 1: The failing test:**
  - `stream_draw_test` makes an NV12 array texture as a decoder's, with `DECODER | SHADER_RESOURCE` where
    allowed, and fills slice 3 with the four blocks. It draws from slice 3 and checks the colours.
  - Then again in BT.709 full range, the matrix the stream says.
  - Then with the copy forced.
- [ ] **Step 2: See it fail; implement; pass** on both adapters.
- [ ] **Step 3: Commit.**

### Task 10: Phase B in the app

- [ ] **Step 1:** Release build with the new ffenc DLL. The watcher's log names:
  - `shares decode on the GPU (<adapter>)`;
  - `decoding H264 on <driver>`;
  - the texture.
- [ ] **Step 2:** The same by-hand list as Task 6, Step 3, in Hybrid. Add:
  - a VP8 share falling back to the call's connection with its line in the log;
  - a late viewer's wait through Rust and through the call, each named.
- [ ] **Step 3:** Device loss, simulated (as Task 6, Step 4), with a GPU picture lent.
- [ ] **Step 4: Cost,** Hybrid, three runs of 20 s each: through Rust (GPU decode), `RIFT_WATCH_DECODE=cpu` and
  `RIFT_WATCH_PATH=call`, H264 and VP9 at 1080p.
- [ ] **Step 5: Commit** with `TESTING.md`, `CALLS.md` and `STEP3_PLAN.md` (step 4's line: Windows built and
  where it was proven).

### Task 11: The gate, Discrete, and a real reset

- [ ] **Step 1: The probe's tear check under load.** CS2 running, in Hybrid and in Discrete: the rows agree in
  every grab. Then `live_gpu_watch` on the RTX (Discrete).
- [ ] **Step 2: The watcher's game.** CS2, three cases (no watch, the call's path, Rust's), capped and uncapped,
  Hybrid and Discrete. For each:
  - the mean, the p99, frames over twice the target;
  - the stream's rate, and any freeze over 50 ms.

  PresentMon is the owner's command. A sharer on the same PC is named. Report; the owner judges.
- [ ] **Step 3: A real reset** (owner, Discrete, `dxcap -forcetdr` while watching):
  - the tile goes to the call's renderer and keeps moving;
  - the next call watches through Rust again.
- [ ] **Step 4: Commit** with the numbers in `STEP3_WINDOWS.md` and `CALLS.md`.

### Task 12: Docs and the Linux side's recheck

- [ ] **Step 1:** `STEP3_WINDOWS.md` gets *What Linux must recheck*:
  - the Linux build;
  - `cargo test --release` and `live_watch_`;
  - `live_gpu_watch` on VAAPI and CUDA, with `gpuDevice` 0;
  - the app once (the `create` answer and `watchShare`'s new argument);
  - `cargo xwin` building Windows;
  - every shared file this plan touched.
- [ ] **Step 2:** Search the docs for lines this made untrue ("every platform but Linux", "Linux only for
  now", `watchPlaysSound`) and fix them.
- [ ] **Step 3:** Write the review prompt for the owner's cloud session (not run here). Commit.
