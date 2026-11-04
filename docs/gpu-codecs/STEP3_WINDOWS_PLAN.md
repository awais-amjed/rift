# Watching through Rust on Windows — implementation plan

> **For agentic workers:** steps use checkbox (`- [ ]`) syntax for tracking. Test first: see each new
> test fail, then make it pass, one commit per logical change.

**Goal:** Windows watches a share through the Rust watch connection, as Linux does: the picture drawn on the
GPU into a texture Flutter shows (phase A), then decoded on the GPU too (phase B), with Rust playing its sound.
Measured against the call's path, and with a game beside it.

**Architecture** (`STEP3_WINDOWS.md`): the runner makes one D3D11 device on the adapter Flutter draws with, matched
by LUID. Each watched share has one shared BGRA texture, which Flutter reads by DXGI handle. On Flutter's raster
thread, the runner borrows Rust's newest picture (`rift_watch_frame_lock`), draws it with a YUV→RGB shader, waits
for the GPU to finish it and hands it back. In phase B, ffdec decodes with FFmpeg's `d3d11va` on that same device, and the
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
- **The shaders are compiled at build time, by MSBuild's own HLSL step.** Flutter's Windows build uses the
  Visual Studio generator. CMake marks the `.hlsl` files (one per shader: the step takes one entry point a
  file) with `VS_SHADER_TYPE`, `VS_SHADER_MODEL 5.0` and `VS_SHADER_OUTPUT_HEADER_FILE`. MSBuild then runs the Windows SDK's `fxc` itself, so nothing looks for it on
  `PATH`. The header goes in the build directory, and no `d3dcompiler_47.dll` is loaded at run time. The
  GitHub release build (`release.yml`, `windows-latest`) uses the same generator and the same SDK (Task 1,
  Step 5).
- **Tearing under load is checked before anything is built on the texture route** (Task 0). The route rests
  on the GPU finishing the runner's draw before Flutter reads the texture, with nothing but `Flush` ordering
  them. So far this has only been checked on an idle GPU. If it tears, the runner waits for its draw to finish
  before answering the descriptor: an event query after `Flush`, polled on the raster thread. That wait is
  measured, and the design changes before Task 1.
- **The runner waits for its draw (Task 1, Nov 4).** Nothing tore through Flutter (Task 0), but the drawing's
  test, reading each picture back on a second device the moment it was drawn, found 198 of 200 half drawn
  on the RTX at 1440p with a `Flush` alone. `Draw` now waits: a D3D11 fence with an event, so the raster
  thread sleeps, or an event query where there is no fence. It costs about 0.4–0.5 ms a picture at p50
  (`STEP3_WINDOWS.md`, *A read at once does tear*).
- **The runner's drawing is a part with no Flutter in it** (`stream_draw.{h,cpp}`), so a test program can drive
  it: draw, read back, check the colours. `stream_texture.cpp` is only the channel, the registrar and the
  lifetimes.
- **Device loss in a test build is simulated** with `RIFT_STREAM_TEXTURE_FAIL_AFTER=<n>`: after n pictures, the
  runner answers as if the device were removed. A real reset (`dxcap -forcetdr`) is the owner's by-hand step,
  as in step 1.
- **Rust asks the runner for the device; it never travels through Dart:**
  - The runner exe exports `rift_stream_d3d11_device()`. It returns the device with a reference added, or null
    when there is none yet or it was lost. It takes the same lock as the live map.
  - Rust finds the export with `GetProcAddress(GetModuleHandleW(NULL), ...)` when it opens a share's decoder.
    The decoder keeps that reference, and releases it when it closes.
  - Because Rust holds its own reference, a device lost in between is still a live object: its calls fail with
    `DXGI_ERROR_DEVICE_REMOVED` and the share falls back. No address can outlive the device behind it.
  - A runner without the export (an old build, the test program) is "no device": that share is watched
    through the call when decoding would be on the GPU.
  - The bridge and Dart do not change, so Linux has nothing new to recheck there.
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
- **The device's lifetime across the runner and Rust:** `rift_stream_d3d11_device()` adds a reference under
  the lock, and every path that opens a decoder releases it (Tasks 2, 8).
- **Sound:** the share's sound through Rust is not turned down by Windows' ducking while the call is up (Tasks
  4, 6).
- **Linux untouched:** shared structs grow at the end, and the bridge does not change. `cargo xwin` on Linux
  still builds Windows (Tasks 6, 8).

---

## Phase A

### Task 0: Tearing under load, before building on the route

The probe (`STEP3_WINDOWS.md`, *Probe evidence*) is the texture route with nothing else in it. It stays a
scratch tool outside the repository. The load program is scratch too: one D3D11 window on adapter 0 drawing
a heavy full-screen pixel shader without vsync, so Flutter's own GPU is busy.

- [x] **Step 1: Hybrid, the case people meet.** CS2 running in a match against bots, at the owner's settings,
  on the RTX, the way Hybrid runs it. The probe and `tear.ps1`, 600 grabs. The rows agree in every grab.
  Record the probe's draw times and CS2's share of the RTX (its frame rate needs PresentMon, the owner's
  admin step, and isn't needed for a tear check).
- [x] **Step 2: Hybrid, the worst case.** The load program on the Iris Xe, which is Flutter's adapter. Same
  check, 300 grabs.
- [x] **Step 3 (not needed: nothing tore, Nov 4): If anything tears,** add the wait to the probe (an event query after `Flush`, polled until
  done) and run Steps 1–2 again. Record how long it waits at p50 and p99. The design then says the runner
  waits, and Task 1's interface says so.
- [ ] **Step 4: Discrete** comes at the owner's first Discrete boot, before phase B starts (Task 6, Step 7).
- [x] **Step 5: Commit** the result in `STEP3_WINDOWS.md` (*Probe evidence*), with the mode, the load and
  the counts.

### Task 1: The runner's drawing, tested alone

**Files:**
- Create: `windows/runner/stream_draw.h`, `windows/runner/stream_draw.cpp`,
  `windows/runner/stream_draw_vs.hlsl`, `windows/runner/stream_draw_ps.hlsl`
- Create: `windows/runner/test/stream_draw_test.cpp`, `windows/runner/test/run.ps1` (builds the test with
  `cl` and runs it; no Flutter)
- Modify: `windows/runner/CMakeLists.txt` (the sources, the `.hlsl` files' `VS_SHADER_*` properties, `d3d11`
  and `dxgi`)

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
    // waits for the GPU to finish it. False when it could not, the device
    // removed included.
    bool Draw(const WatchPlanes& planes);
    HANDLE handle() const;
    uint32_t width() const, height() const;
  };
  ```
- The colour sums are those of `stream_texture.cc`'s `Colour`, passed as a constant buffer.

- [x] **Step 1: The failing test.** `stream_draw_test.cpp` makes a device on adapter 0. It draws a 1920×1080
  I420 picture of four blocks (BT.601 limited: red, green, blue, white) and reads the BGRA texture back
  through a staging copy. Checks:
  - each block's centre is within 2 of (255,0,0), (0,255,0), (0,0,255) and (255,255,255);
  - row 0 is the top;
  - a second picture at 1280×720 resizes the texture;
  - odd sizes (1279×719) draw, with the chroma rounded up;
  - two 2560×1440 pictures in turn, 200, each read back on the second device the moment `Draw` returns, all
    whole (added Nov 4, after Task 0: it fails without the wait).
- [x] **Step 2: Run it to see it fail** (`run.ps1`: it does not link yet).
- [x] **Step 3: Implement** `MakeDevice` and `StreamDraw` for `IN_MEMORY`, and the shader step.
- [x] **Step 4: Run it on both adapters:** the Iris Xe and the RTX, in Hybrid. Record the colours. (Nov 4: on
  both, at every size, (254,0,0), (0,255,1), (0,0,255) and (255,255,255); the read-at-once check 0 of 200
  wrong.)
- [x] **Step 5: The release build finds the shader compiler.** (Nov 4: built clean from a plain PowerShell,
  with no `fxc` on `PATH`. MSBuild ran the SDK's `fxc` 10.0.26100.0; the `.cso` files stay in the
  intermediate directory. `windows-latest` (image 20261030) lists Windows SDK 10.0.26100.)
  - Clean `build/windows`, then run `scripts/build_windows.ps1` from a plain PowerShell with no developer
    environment, which is how `release.yml` runs it. It must build.
  - Check the shader header was made by MSBuild's FxCompile step, in the build log.
  - Check that `windows-latest`'s image lists a Windows 10/11 SDK, from its published software list.
  - CI itself is checked on the first `release.yml` run the owner starts. Until then this is a claim, and
    the commit says so.
- [x] **Step 6: Commit.**

### Task 2: The stream texture in the runner

**Files:**
- Create: `windows/runner/stream_texture.h`, `windows/runner/stream_texture.cpp`
- Modify: `windows/runner/flutter_window.{h,cpp}` (install it), `windows/runner/CMakeLists.txt`
- Modify: `rust/src/logging.rs` (`rift_runner_log`, so the runner's lines reach the app's log)
- As built (Nov 4): the runner uses Flutter's C texture API (`FlutterDesktopTextureRegistrar*`), so it needs
  neither a `PluginRegistrarWindows` nor `flutter_wrapper_plugin`.

**Interfaces:**
- The `rift/stream_texture` channel, as on Linux:
  - `create` `{lock, unlock}` answers `{textureId, mark, takesGpuPictures}`;
  - `dispose` `{textureId}`.
- `rift_stream_texture_mark(uint64_t)` looks the texture up under a lock and calls
  `MarkTextureFrameAvailable`; a texture already gone is nothing.
- `extern "C" __declspec(dllexport) ID3D11Device* rift_stream_d3d11_device()`, exported by the runner exe: the
  device with a reference added, under the same lock, or null when there is none or it was lost. Phase A
  only exports it. Rust starts calling it in Task 8.
- The callback runs on the raster thread:
  - lock; on a new picture, `Draw`; then unlock with `drawn`;
  - it answers the descriptor, or null when there is no texture yet and no device.
  - Before the first picture it answers a 1×1 black texture, as Linux's `DrawBlack`.
- `dispose` takes the texture out of the live map, then calls `UnregisterTexture(id, callback)`. The callback
  frees the `StreamDraw` on the raster thread.
- `RIFT_STREAM_TEXTURE_FAIL_AFTER=<n>`: debug builds only (`#ifdef _DEBUG`, which Flutter's CMake sets for
  Debug alone, never Profile or Release). The picture after the n-th drawn in the process finds its device
  removed, once, so the next `create` makes a working device.
- Device removed (`GetDeviceRemovedReason`, or the hook):
  - unlock with 0;
  - a one-time warning;
  - the device is let go for the process;
  - the next `create` makes a new one.

- [x] **Step 1: Build the runner** with the texture installed and `RustWatch.available` still Linux only. The
  app starts and nothing changes. (Nov 4: release build, no new warnings; the exe exports
  `rift_stream_d3d11_device` and the Rust library `rift_runner_log`. A test client started, signed in and
  answered, with no texture line in its log. The drawing's test still passes on both adapters.)
- [x] **Step 2 (Nov 4: in `STEP3_WINDOWS.md`, *Threads*): Read the lifetimes against the engine's sources:**
  - mark from any thread;
  - unregister finishes on the raster thread;
  - `PopulateTexture` holds the texture's raw pointer only under the registrar's raster task.

  Write down where each call runs.
- [x] **Step 3: Commit.**

### Task 3: Dart turns it on for Windows

**Files:**
- Modify: `lib/logic/services/rust_watch.dart` (`available`: Linux or Windows), and its doc comment, which names
  the Windows runner's file

- [x] **Step 1:** Change `available`. Run `flutter analyze` and `flutter test`. Analyze clean; the tests pass but
  four in `overlay_material_test.dart`, which fail the same without the change on a Windows host (`DuckingCubit`
  reaches Rust, which a widget test has not loaded).
- [x] **Step 2: Commit** with `CALLS.md` (*Watching a share through Rust*: Windows in the first list, the texture
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

- [x] **Step 1: The failing unit tests** for the room and the cushion:
  - empty: the cushion, then the frame;
  - full: nothing;
  - part full: whole frames only.
- [x] **Step 2: Run to see them fail; implement; pass.** Four failed against a stub; all pass. As built, the
  room and the cushion are one function, `to_write(frame, queued, gain)`, beside `room`. A write that fails
  (a device unplugged) opens the output again on the next frame; three in a row end the sound.
- [x] **Step 3: The live test on Windows.** `live_watched_sound` gets a Windows check:
  - The output is VB-Cable's input, by name.
  - It asserts the name contains `CABLE` and is not the default output.
  - It records VB-Cable's output through WASAPI capture in the same test.
  - It checks, as on Linux:
    - the tone in the left ear, then the right, at the level sent (±1 dB);
    - nothing at volume 0;
    - 6 dB down at half;
    - silent once unwatched.

  See it fail with `PLAYS` false, then pass.

  Nov 4, against `livekit-server --dev` on 7980: −15.2 dBFS in each ear for −15.3 sent, the other ear at
  −96.7, −21.3 at half, −96.5 at 0 and once unwatched. With `PLAYS` false: −96.5 at full, failed.
- [x] **Step 4: Ducking.** A call's playback is a communications stream, and Windows turns other sounds down
  for it, by 18 dB measured (`CALLS.md`, *Windows turning other apps down*). The share's sound through the
  call is part of that stream, so it is never turned down. Rust's stream is not, so it might be.
  - In the live test, a second render stream opens on VB-Cable with the communications role while the tone
    plays, and the tone's level is measured before and after it opens. The level must not drop by more than
    1 dB.
  - If Windows ducks it, the stream is tagged as communications (`AudioClientProperties`, category
    `AudioCategory_Communications`), or joins the call's audio session. The choice is made on what was
    measured, and written down.
  - If the test can't make Windows duck at all (ducking may not reach VB-Cable), it says so, and the real
    check is the app's (Task 6, Step 6).

  Nov 4, `live_watched_sound_is_not_turned_down_beside_a_call`: Windows ducks only the communications
  device's own streams, so VB-Cable was made the communications device for the run (Windows set to lower
  by 80%). A silent call stream in the same process: the tone stayed at −15.3 dBFS. The same stream from a
  second process (a test the first starts): −33.3, 18 dB down, as measured in October, and back at −15.3
  once it closed. Windows spares the process whose call it is, so Rust's stream needs no tag or session.
  The test also checks that Windows ducked, and that another process's call turns the cable down, so it
  cannot pass without measuring anything.
- [x] **Step 5: `cargo test --release`, `cargo fmt --check`, commit** with `CALLS.md` (the sound on Windows).

### Task 5: The server for the app (owner)

- [x] **Step 1:** The owner installs Docker Desktop (approved Nov 4) with the command given; it is not run
  here.
- [x] **Step 2:** Bring up rift-self-host's stack (`dev`, 604f8c4 or later).
  - Copy `_shared`, `get_channel_token`, `get_dm_call_token`, `moderate_user`, `voice_roster` and
    `livekit_webhook` into the functions container, then restart it.
  - `diff` the copy against the repository.
  - Write a script that redoes the copy, since the console copies its old functions back on every start.

  As done Nov 4: the stack (1.2.0) updated to 1.4.1 by its console (`update --yes`), which ran migrations
  022–024; `dev` at 604f8c4 cloned from the GitHub mirror (the Forgejo one wants credentials); the six
  functions copied and diffed the same by a script kept with the test files (`copy-functions.sh`); and
  LiveKit's `webhook:` block added from `dev`'s template, which 1.4.1's console does not add yet.
- [x] **Step 3:** Two test profiles join a channel on it.
  - Check the watcher's log does not say `the server does not mint watch connections`.
  - Check the server's log shows the `_watch` identity joining.

  Nov 4, s1 and s2: no such line; LiveKit logged `…~e22aaee4_watch` active and sent the webhook, which
  `livekit_webhook` served.

### Task 6: Phase A in the app, measured

- [x] **Step 1: Release build** (`scripts/build_windows.ps1`, after the Rust build). Two clients on the stack:
  `RIFT_PROFILE=a` sharing, `RIFT_PROFILE=b` watching.
- [x] **Step 2: The watcher's log names the path:**
  - `watching ... through Rust`;
  - `shares decode on the CPU`;
  - `watching: picture WxH`.
- [ ] **Step 3: By hand with the owner** (numbered steps for the owner):
  - H264 and VP9, 1080p60, a window share and a whole-screen share;
  - resize; minimise and restore the watcher;
  - leave and rejoin; the first Watch after joining from the sidebar;
  - volume, mute and deafen;
  - Quit from the tray while watching.
- [x] **Step 4: Device loss, simulated.** `RIFT_STREAM_TEXTURE_FAIL_AFTER=300` in a test build:
  - the log says the window could not draw;
  - the tile is back on the call's renderer within a second, moving, not frozen.
- [x] **Step 5: Cost,** Hybrid. The watcher's threads over 20 s, three runs each:
  - through Rust (CPU decode);
  - `RIFT_WATCH_PATH=call`.

  H264 and VP9 at 1080p. A sharer on the same PC is named in the table.

  Nov 4 (profiles s1 sharing and s2 watching, as profiles a and b are on the owner's real server): steps 2
  and 4 as written, the device loss falling back in 30 ms; cost in `CALLS.md` and `TESTING.md` row 26, H264
  92–97% of a core through Rust against 105–108%, VP9 107–110% against 127–130%.
- [ ] **Step 6: The sound against ducking, in the app.**
  - The sharer shares a window playing a steady tone.
  - The watcher's output is VB-Cable, with Windows' Communications setting left at its default (80%).
  - Record VB-Cable for 10 s watching through Rust, then 10 s with `RIFT_WATCH_PATH=call`.
  - The two levels agree within 1 dB.
  - The log names which path each recording was.

  Not done in the app yet. A tone the sharer captures but nobody hears needs a source off the speakers, and
  two clients on one PC loop the watcher's sound back into a whole-screen share. The rule is measured in
  Rust (Task 4 Step 4): Windows spares the process whose call it is.
- [ ] **Step 7: Discrete, before phase B.** The owner reboots into Discrete. There, run Task 0's tear check
  under load (CS2, then the load program on the RTX, which is Flutter's adapter there), then Steps 2 and 4 of
  this task once.
- [ ] **Step 8: Commit** with `TESTING.md` row 26 and `CALLS.md` (what was driven, the cost table, what was not).

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
  - `rust/src/watching/decode/mod.rs`: the `mod` lines. Windows' decoder asks for the runner's device when
    it opens; Linux's is unchanged.
  - `rust/src/watching/frames.rs`: `IN_D3D11`; `texture` and `slice` appended to `WatchPlanes`; the unlock log
    line without "decoded on the GPU".
  - `linux/runner/stream_texture.cc`: the appended fields.

**Interfaces:**
- ```rust
  pub(crate) struct Gpu { luid: i64, name: String, h264: bool, vp9: bool }
  pub(super) fn device() -> Result<Gpu, String>;  // adapter 0's video profiles; Err with none
  impl Gpu { pub(crate) fn decodes(&self, codec: Codec) -> Option<bool>; }  // VP8: Some(false)
  // The runner's device, from its `rift_stream_d3d11_device` export, with the
  // reference it added; None when the export or the device is missing.
  fn runner_device() -> Option<ID3D11Device>;
  ```
- A decoder that finds no runner device fails by name ("the window has no GPU device"), and the share falls
  back to the call's connection, as any decoder that cannot open does.
- Tests put their own device in the runner's place (a `#[cfg(test)]` override, since a test binary exports
  nothing).

- [ ] **Step 1: The failing unit tests:**
  - `decodes` from a profile list (pure: a list of GUIDs in, the answer out);
  - with no runner device, opening a GPU decoder fails with the reason, and nothing is leaked.
- [ ] **Step 2: See them fail; implement; pass.** `flutter analyze` (nothing in Dart should change).
- [ ] **Step 3: `live_gpu_watch` on Windows.**
  - The test puts in place a device made as the runner makes it.
  - `lent_from_the_gpu` checks the `IN_D3D11` picture: a texture, a slice within the array, the size sent.
  - H264 and VP9 decode at 80% or more of the pictures sent; VP8 fails with
    `the GPU cannot decode this Vp8`.
  - Run it in Hybrid on the Iris Xe. The RTX's turn is in Task 11.
- [ ] **Step 4: Commit.** The Linux side's recheck list gets this task's shared files.

### Task 9: The runner draws decoded surfaces

**Files:**
- Modify: `windows/runner/stream_draw.{h,cpp}` (NV12 from a slice: R8 and R8G8 views, cached per texture and
  slice; the copy where views cannot be made), `windows/runner/stream_texture.cpp` (`takesGpuPictures` from
  the LUID), `windows/runner/test/stream_draw_test.cpp`

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

- [ ] **Step 1: Tearing again, now with the decoder's pictures.** CS2 running, in Hybrid and in Discrete:
  watching a share of a moving bar, the rows agree in every grab. Then `live_gpu_watch` on the RTX
  (Discrete).
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
  - `live_gpu_watch` on VAAPI and CUDA (`WatchPlanes` grew);
  - `cargo xwin` building Windows;
  - every shared file this plan touched.
- [ ] **Step 2:** Search the docs for lines this made untrue ("every platform but Linux", "Linux only for
  now", `watchPlaysSound`) and fix them.
- [ ] **Step 3:** Write the review prompt for the owner's cloud session (not run here). Commit.
