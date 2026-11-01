# Zero-copy sharing on Windows, the rest — implementation plan

> **For agentic workers:** steps use checkbox (`- [ ]`) syntax for tracking. Test first: see each new
> test fail, then make it pass, one commit per logical change.

**Goal:** what the first milestone left out (`STEP1_WINDOWS.md`, *Not built yet*): the settings switch shown
on Windows, Quick Sync and AMF taking the WGC picture on the GPU, live tests for this path, the app driven
through everything a share does, and the docs that say so.

**Architecture:** unchanged from the milestone. `capture_wgc.rs` captures on one D3D11 device the encoder
shares; `d3d11_nv12.c` draws the picture into FFmpeg's D3D11 frames as NV12. What changes: the device opens on
the adapter of *whichever* encoder won the probe, not always NVIDIA's, and `ffenc.c` hands the frames to AMF as
they are and to Quick Sync through a derived QSV frames context.

**Tech stack:** Rust (`windows` crate, `capture_wgc`, `encoder`), C (D3D11, FFmpeg 9.0.2's `hwcontext_d3d11va`
and `hwcontext_qsv`), Dart (`HostPlatform`, settings).

**Spec:** `docs/gpu-codecs/STEP1_WINDOWS.md`, with the owner's verdict of Nov 1 (read it first). The order below
is the verdict's: the switch first.

## Global Constraints

- Branch `gpu-codecs`; commit locally per task. Pushes are the owner's. Stage named paths; never `git stash`.
  No attribution lines.
- **The share must not make the sharer's game stutter, and viewers must not see stutter, lag or a wrong
  picture (owner).** A share never crashes, hangs on stop or takes the call down; every failure lands on
  today's path.
- Rift still starts and shares on a machine with none of this: no NVIDIA, no Intel graphics, Windows 10, an old
  driver. New C is inside `#if defined(_WIN32)`; nothing new in `ffenc.c` may change what Linux builds.
- Colours stay BT.601 limited, as `ffenc.c` tells viewers.
- `RIFT_FFENC_ABI` and `ABI` in `ffmpeg.rs` move from 9 to 10 once, only if `ffenc.h` changes.
- No hook into a game, ever: it risks anti-cheat bans (owner).
- `cargo test --release`, `cargo fmt --check` and `flutter analyze` clean before each commit; `CALLS.md` and
  `TESTING.md` change in the commit that changes behaviour or proves it. No machine paths in docs.
- The owner's Rift is never killed or launched; test clients use `RIFT_PROFILE`. PresentMon and anything else
  that needs an administrator goes to the owner as a command. BIOS changes are the owner's.
- After any Rust change, `cargo build --release --target x86_64-pc-windows-msvc` before `flutter build`, and
  check the DLL's time.

## Decisions this plan makes

- **The switch is shown on every Windows build**, Windows 10 included, where it still governs window shares.
  Not hidden when no encoder takes textures: the person cannot know that, and off is always safe.
- **The D3D11 device follows the encoder.** The probe already picks NVENC, AMF or Quick Sync in that order;
  the capture opens its device on that encoder's vendor (`0x10de`, `0x1002`, `0x8086`), never by list position.
  Windows crosses GPUs for the capture, as it does today for NVIDIA in Hybrid.
- **AMF takes the converter's frames as they are.** FFmpeg 9.0.2's `amfenc.c` lists
  `HW_CONFIG_ENCODER_FRAMES(D3D11, D3D11VA)`.
- **Quick Sync gets a copy in its own surfaces.** `qsvenc.c` lists only QSV frames, and a QSV pool, its own
  or derived from ours, is one D3D11 texture array. NV12 arrays bound as render targets are refused above 2 on
  both GPUs here (`E_INVALIDARG`, Nov 1, a throwaway test), too few for the last picture kept for repeats and the
  frames the encoder holds; arrays bound for decoding were made up to 8. So the converter draws as today, and
  each picture is copied on the GPU into a QSV surface from a pool of 8 such (`MFX_MEMTYPE_VIDEO_MEMORY_DECODER_TARGET`),
  as OBS's Quick Sync encoder copies its input. NVENC and AMF take the converter's frames with no copy.
- **AMF stays off this path until it runs on an AMD card.** This laptop has none. `takes_textures` answers
  true for AMF only when `RIFT_FFENC_AMF_TEXTURES=1` is set, until the owner's RX 9070 XT runs Windows for a
  test; then the gate comes out in its own commit. Cost if wrong: AMD sharers keep today's path a while longer.
- **Quick Sync goes first only if it costs the game less than NVENC** in Hybrid on CS2 (owner). Until that
  measurement, NVENC stays first.
- **Device loss in a test build is simulated** with a test-only `RIFT_D3D11_FAIL_AFTER=<n>` (the converter
  fails as if the device were removed after n pictures), and a real driver reset is the owner's by-hand step.

## Review Focus

- **The switch off keeps the share entirely out of the new code**, the startup probe included: no D3D11 device,
  no WGC session (Task 1, Task 4's live test).
- **A device on the wrong adapter:** the encoder refuses the frames and the share goes to memory, not black
  (Task 2, forced vendor mismatch).
- **QSV lifetimes:** the copy into a QSV surface is queued before the surface goes to the encoder, the
  converter's frame is freed after; closing the encoder mid-share, or a resize, frees in the right order with
  nothing still mapped (Task 3).
- **Device loss mid-share:** the last picture repeats, then after about a second the share moves to VP9 without
  a second picker; no hang on stop (Task 4, Task 5).
- **Quit mid-share from the tray** exits at once on every encoder (Task 5).

---

### Task 1: The settings switch on Windows

**Files:**
- Modify: `lib/logic/services/host_platform.dart`, `docs/gpu-codecs/STEP1_WINDOWS.md` (*Not built yet*),
  `CALLS.md` (*How Windows captures a screen*)
- Create: `test/host_platform_test.dart`

**Interfaces:**
- `HostPlatform.capturesShareOnGpu` is true on Windows, and under Wayland on Linux as before. Everything below it
  already exists: `AppState.gpuScreenCapture` (default true), the toggle in `general_content.dart`,
  `ScreenShareConfig.gpu_capture`, and `capture_wgc::run` returning `Handoff::Fallback` before any probe when it
  is false.

- [x] **Step 1: The failing test.** `test/host_platform_test.dart`: on a Windows host,
  `HostPlatform.capturesShareOnGpu` is true (`skip: !Platform.isWindows`, so Linux's run is unaffected).
- [x] **Step 2: Run it to see it fail.** `flutter test test/host_platform_test.dart`.
- [x] **Step 3: Change the getter** to `!kIsWeb && (Platform.isWindows || (Platform.isLinux && _underWayland))`,
  with its doc comment saying why Windows always.
- [x] **Step 4: Run the test, `flutter analyze`, `flutter test`.**
- [x] **Step 5: Check the Rust side keeps out.** Read `capture_wgc::run` and `ffmpeg.rs`'s open: with
  `gpu_capture` false, no `encoder::takes_textures()` call and no `d3d11_device`. Proven live in Task 4.
- [x] **Step 6: Commit** with `CALLS.md` (the switch, and that it takes effect from the next share).

---

### Task 2: The capture's device on the encoder's adapter

**Files:**
- Modify: `rust/src/screenshare/capture_wgc.rs` (`nvidia_adapter` becomes `adapter_of`),
  `rust/src/screenshare/encoder/ffmpeg.rs`, `rust/src/screenshare/encoder/mod.rs`

**Interfaces:**
- ```rust
  /// The PCI vendor whose adapter must hold the capture's device for this encoder
  /// to take its textures; None for an encoder that does not take them.
  pub(crate) fn texture_vendor(encoder: &CStr) -> Option<u32>;
  /// The vendor of the encoder that won the probe, when it takes textures here.
  pub(crate) fn takes_textures() -> Option<u32>;   // was bool
  ```
- Values: `h264_nvenc` → `0x10de`; `h264_qsv` → `0x8086`; `h264_amf` → `0x1002` only with
  `RIFT_FFENC_AMF_TEXTURES=1`; anything else → `None`.

- [x] **Step 1: The failing tests** for `texture_vendor` in `ffmpeg.rs`: each of the four cases above, AMF with and
  without the variable (the variable read once, through a parameter, so the test is pure).
- [x] **Step 2: Run to see them fail.** `cargo test --release texture_vendor`.
- [x] **Step 3: Implement**, and `adapter_of(vendor)` in `capture_wgc.rs` (hardware only, first of that vendor).
  `takes_rifts_capture` keeps its `encoder_takes_textures: bool` (`.is_some()`), so its tests stand.
- [x] **Step 4: Forced mismatch.** In a test build, `RIFT_WGC_VENDOR=0x8086` with NVENC encoding: the converter or
  encoder refuses, the log says memory pictures, and `bench_share` still delivers 60 fps. Record it.
- [x] **Step 5: `cargo test --release`, commit.**

---

### Task 3: Quick Sync and AMF take the converter's frames

**Files:**
- Modify: `native/ffenc/ffenc.c`, `native/ffenc/ffenc.h` (a comment), `native/ffenc/d3d11_nv12.c`,
  `native/ffenc/d3d11_nv12.h`, `native/ffenc/build.sh` (oneVPL's headers; the DLL's own name),
  `rust/src/screenshare/encoder/ffmpeg.rs` (`texture_vendor`), `CALLS.md`
- Create: `native/ffenc/test_d3d11.c`, `native/ffenc/check_d3d11.py`, `native/ffenc/test_windows.sh`

**Interfaces:**
- `d3d11_nv12.h` gains `AVBufferRef* d3d11_nv12_device(D3d11Nv12*)`, FFmpeg's D3D11 device, to derive from,
  and `d3d11_nv12_copy`, a drawn frame into a slice of another NV12 texture.
- In `rift_ffenc_open` on `_WIN32`: `config->d3d11_device` set and API NVENC or AMF → the converter as today;
  API QSV → the converter as today, plus a QSV device derived from its D3D11 device
  (`av_hwdevice_ctx_create_derived`) and a QSV frames pool of 8 decoder-target surfaces on it, which is
  `enc->frames`. Each picture is drawn into a converter frame, then a QSV surface is taken, mapped to D3D11
  (`av_hwframe_map`) for its texture and slice, and the picture copied in (`CopySubresourceRegion`); the
  converter frame is released and the QSV frame sent. `enc->last` holds the QSV frame.
- Any step failing: a warning, and the encoder opens on memory as today.

- [x] **Step 1: The failing test.** ffenc's own, as Linux's `test_nvenc_dmabuf.c` (a Rust one would need a real
  WGC picture): `test_d3d11.c` opens each encoder with a device on its maker's GPU and sends BGRA textures through
  `rift_ffenc_send_d3d11`; `check_d3d11.py` decodes and checks within ±4 of BT.601 limited: quarters and repeats,
  a moving bar (none late), a letterboxed picture, memory pictures between; `--exit-open` must end.
  `test_windows.sh` runs it. Quick Sync failed: it opened but took no D3D11 picture.
- [x] **Step 2: Implement the QSV pool and the copy.** Free order in `rift_ffenc_close`: codec, then
  `enc->last`, then the QSV frames and device, then the converter.
- [x] **Step 3: Run the test on Quick Sync, then NVENC**, both pass. Then a bench share on Quick Sync.
- [x] **Step 4: AMF, by code only.** `h264_amf` gets the converter's frames as NVENC does. Not run here; the
  `RIFT_FFENC_AMF_TEXTURES` gate stays. If the owner's desktop runs Windows, `test_windows.sh` there, a share
  with `RIFT_FFENC_AMF_TEXTURES=1`, then the gate comes out.
- [x] **Step 5: `cargo test --release`, the ffenc build in MSYS2, commit** with `CALLS.md`.

---

### Task 4: Live tests for this path

**Files:**
- Modify: `rust/src/screenshare/gpu_live_test.rs`, `rust/src/screenshare/capture_wgc.rs` (test-only counts),
  `native/ffenc/d3d11_nv12.c` (the failure switch, and a second of failures rather than 120 pictures),
  `TESTING.md`, `CALLS.md`

**Interfaces:**
- `RIFT_D3D11_FAIL_AFTER=<n>`, read by the converter as it opens (as Linux's `RIFT_FFENC_NO_GL`): every picture
  after the nth fails as a passing failure would.
- A test window in a second process (the test binary again, `wgc_test_window`): libwebrtc lists no window of
  its own process.

All need LiveKit (`livekit-server --dev`) and a display, one test per process:

- [x] **Step 1: Run the two existing shared tests on Windows.** Both passed unchanged, on NVENC and Quick Sync.
- [x] **Step 2: `live_wgc_switch_keeps_the_share_off_the_gpu`.** Written against what was built in Task 1.
- [x] **Step 3: `live_wgc_window_share_ends_when_the_window_closes`**, five closes a run.
- [x] **Step 4: `live_wgc_failing_gpu_moves_to_vp9`.** RED against the library before the switch (no VP9 within
  15 s). With 120 pictures as the limit it measured 4.3 s at 30 fps, which the 4 s bound added after would fail;
  GREEN at a second of failures (1.4 s).
- [x] **Step 5: `live_wgc_still_window_reaches_a_late_viewer`.**
- [x] **Step 6: Commit with `TESTING.md`.** A real driver reset stays the owner's by-hand step (Task 5).

---

### Task 5: The app, and Quick Sync against NVENC on the game

**Files:**
- Modify: `TESTING.md`, `CALLS.md`, `docs/gpu-codecs/STEP1_WINDOWS.md`, `docs/gpu-codecs/PLAN.md`; the local
  `MANUAL_TESTING.md`

- [ ] **Step 1: A server.** Ask the owner which: Docker Desktop with `rift-self-host`'s stack here, the Linux
  stack, or a call the owner sets up. Never the owner's real server from a test profile.
- [ ] **Step 2: Release build and test clients** (`RIFT_PROFILE`), a viewer on the Linux PC where possible, and
  say so wherever the viewer is on the laptop.
- [ ] **Step 3: Everything a share does, on the new path**: screen and window; quality to VP9 and back; a window
  resized, minimised, closed; CS2 closed mid-share; a game that swaps its window; a late viewer on a still
  screen; the switch off (log says libwebrtc's capturer); Quit from the tray mid-share. Per-thread CPU of the
  share every few seconds, and PresentMon frame times on CS2 (the owner starts it), for the 80 ms frames and the
  Discrete share CPU the verdict asked to watch.
- [ ] **Step 4: By-hand steps for the owner**, numbered: a driver reset mid-share (`dxcap -forcetdr` in an
  administrator shell, needs Graphics Tools), and anything Rift's GUI needs a person for. Wait for the result.
- [x] **Step 5: Quick Sync against NVENC, Hybrid, CS2.** The gate's way, lowest settings standing still, 60 and
  120 fps, three rounds each, `RIFT_FFENC_ENCODER=h264_qsv` against NVENC in the same sitting. The viewer ran on
  this laptop (the Linux PC was busy). Added ms per game frame, p99, viewer fps, share CPU. Quick Sync cost the
  game three to seven times as much, so the order stays (Nov 1, `STEP1_WINDOWS.md`).
- [ ] **Step 6: Commit the numbers and the `TESTING.md` rows**, with what was checked and what was not.

---

### Task 6: The review, and handing back to Linux

- [ ] **Step 1: The review prompt for the owner** (Opus 5.5 at max, in the owner's cloud session): the commit
  range, the docs to read, the main files, what the product needs, where to look hardest (lifetimes and threads,
  shutdown, fallbacks, device loss), "report findings only".
- [ ] **Step 2: Each finding checked against the code**: fixed with a test where real, why not where not.
- [ ] **Step 3: A closing section in `STEP1_WINDOWS.md`** on what the Linux side must recheck: `cargo fmt`,
  `flutter analyze`, the Linux build, and the shared files this work touched (`gpu_feed.rs`, `worker.rs`,
  `ffenc.c`, `ffenc.h`, `ffmpeg.rs`, `gpu_live_test.rs`, `bench_test.rs`).

## Not in this plan

Merging to `dev` (owner: when GPU encode and decode are both done), pushing, releases. The once-a-minute keyframe
freeze (its own task). Why Windows hands the capture a picture only every 21 ms in Discrete. Windows 10 whole
screens on this path. AMD until a Windows AMD machine is available.
