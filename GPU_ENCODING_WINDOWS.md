# GPU encoding on Windows through FFmpeg: a brief

A brief for the agent working on Windows, on the user's laptop booted into
Windows. It lives on the `gpu-encoding` branch only and goes when the work is
merged. Read `AGENTS.md`, `CODE_STYLE.md` and `ARCHITECTURE.md` ("Encoding a
share on the GPU") first; the conventions there hold here too.

**The job:** encode a share's H264 on Windows with FFmpeg's GPU encoders, the
way Linux already does with FFmpeg's VAAPI encoder, in place of Media
Foundation. Build it, measure it on this laptop, and leave it on this branch.

## The machine

The user's dual-boot laptop: **NVIDIA RTX 3070 Ti Laptop GPU** (GA104M) and
**Intel Iris Xe** (Alder Lake-P, 12th gen). So `h264_nvenc` and `h264_qsv` can
both be built *and measured* here. `h264_amf` (AMD) can be built but not run.
The user's AMD PC (RX 9070 XT) tests it later. Which GPU Windows hands an app
can depend on the power plan and on Windows' graphics settings; say which one
each run used.

Whether Flutter, Rust, Visual Studio Build Tools or MSYS2 are installed on
this Windows is not known. Look first, and ask the user before installing
anything.

## Why

- Friends' H264 shares on Windows went wrong (Oct 9 2026). On a 4070 Ti
  Super at 120 fps the frame rate collapsed. At 60 fps the picture slowed and
  sped up, and the sound drifted out of sync. A GTX 1060 crashed Rift, with
  no faulting module known yet.
- The cause found: Rift hands WebRTC finished frames, and WebRTC never drops
  them (a patch of ours in webrtc-sys). Whatever an encoder makes beyond
  WebRTC's target queues up and the picture falls behind the sound. Media
  Foundation's encoders run in unconstrained VBR and are the suspect. NVENC
  on Linux follows the target exactly.
- `rust/src/screenshare/rate_gate.rs` (shipped in v1.4.0-beta.4) now leaves
  pictures out before the encoder once output runs 0.2 s ahead. That is a
  guard, not a fix: an encoder that follows the rate never trips it. **It
  stays.**
- On Linux, Rift's own FFmpeg replaced LiveKit's VAAPI encoder on Intel and
  AMD (v1.4.0-beta.5). It follows a moved rate within a few percent, and the
  user's AMD shares no longer stall.

**Measure Media Foundation on this laptop first** (step 1), so there is a
before to compare with. If MF turns out to follow the rate here, say so before
building anything: the plan may change.

## What exists

- **`native/ffenc/`**: a C library, `ffenc.h` / `ffenc.c`, around a minimal
  static FFmpeg 9.0.2. It exports eight `rift_ffenc_*` functions with every
  FFmpeg symbol hidden. On Linux, `build.sh` builds it (the runner's CMake
  calls it), and it ships as `lib/librift_ffenc.so`.
  - `ffenc.h` already has a `_WIN32` export macro.
  - `ffenc.c` assumes a hardware frames context (VAAPI surfaces): it uploads
    each NV12 picture with `av_hwframe_transfer_data`.
  - `h264_nvenc`, `h264_amf` and `h264_qsv` all take system-memory NV12
    directly, so the Windows path can likely skip the hw frames context.
    Check each one.
- **`third_party/ffmpeg/`**: one patch, to `h264_vaapi` only. FFmpeg's VAAPI
  encoder sent the bitrate to the GPU only with a keyframe, and the patch
  makes it send each change with the next picture. `RIFT_PATCHES.md` has the
  story.
  - **Whether `h264_nvenc`, `h264_qsv` and `h264_amf` follow a mid-stream
    `bit_rate` change on their own is the first thing to establish.** Read
    the source first: look for a reconfigure on a bitrate change in
    `nvenc.c`, `qsvenc.c` and `amfenc.c`. Then measure it (step 2).
  - A patch, if one is needed, goes in `third_party/ffmpeg/` with its story
    in `RIFT_PATCHES.md`.
- **`rust/src/screenshare/encoder/`**:
  - `ffmpeg.rs` loads the library at run time (`libloading`), and
    `RIFT_FFENC_LIB` points a test at a build elsewhere.
  - `worker.rs` is the encoder thread NVENC and FFmpeg share on Linux, behind
    the `Session` trait.
  - `media_foundation.rs` is Windows' encoder today. It has its own thread,
    picks a hardware MFT by vendor (`EncoderInfo`, the `_only` index), and
    also makes AV1, though AV1 is used only in its tests.
  - `mod.rs` gates all of this by OS: today `ffmpeg.rs` and `worker.rs` are
    Linux only.
- **Settings Linux settled on, and why** (comments in `ffenc.c`):
  - constrained baseline (the one profile LiveKit takes for pre-encoded H264);
  - no B-frames and no SEI;
  - VBR with the peak at 100% of the target (CBR padded still screens with
    filler);
  - a QP floor of 18 (without it a still picture never settles; Media
    Foundation has the same floor);
  - a GOP of 60 s (WebRTC asks for keyframes when it needs them);
  - one picture in flight;
  - timestamps in microseconds, carried through;
  - the 150 kbps minimum and the 4096x2304 largest size in `mod.rs`.

  Map each one onto NVENC's and QSV's options: low-latency tuning, no
  lookahead, zero delay.
- **`assets/licenses/ffmpeg.txt`** covers FFmpeg (LGPL 2.1) for Linux.
  - NVENC in FFmpeg needs `nv-codec-headers` (ffnvcodec, MIT).
  - AMF needs AMD's AMF headers (MIT).
  - QSV needs libvpl (MIT).
  - None of them may need `--enable-nonfree`; check `configure`.
  - The client is GPL-3.0, and NVIDIA's Video Codec SDK *samples* are under
    a EULA it cannot take. That is why LiveKit's own NVENC is excluded.
    Headers only.
  - Pin each download by version and sha256, as `build.sh` does for FFmpeg.
  - Notices for anything new go in `assets/licenses/` and its `README.txt`.

## Rules

- **Commit on `gpu-encoding` only, and push it.** Never push `dev` or
  `production`, never tag, and never release. **No `Co-Authored-By`,
  `Claude-Session` or other attribution lines in any commit message, and
  never mention leaving them out.**
- Stage files by name, never `git add -A`. One logical change per commit.
  Docs change in the commit that makes them wrong (`AGENTS.md`, "Keeping the
  docs true"). Don't commit `.idea/` or `SHARE_DIALOG_PLAN.md`.
- `flutter analyze` must be clean and `cargo test` must pass before each
  commit. Run `rustfmt` on the files you touched only, not `cargo fmt`.
- Ask before installing anything and before anything needing administrator
  rights.
- Recordings and logs stay on this machine, in one folder
  (`%USERPROFILE%\rift-gpu-test\windows\`). Upload nothing, and commit no
  recordings.
- Don't create accounts on any Rift server. The app test (step 5) is the
  user's, on their own account.
- Never print secrets or tokens, and never touch the clipboard.

## Plan

### 1. Media Foundation, measured (the before)

The share bench runs on Windows (`rust/src/screenshare/bench_test.rs`; read its
header). It needs a LiveKit server: `livekit-server --dev` on Windows is a
single exe (ask before downloading it), with key `devkey` and secret `secret`.

```
set LIVEKIT_URL=ws://127.0.0.1:7880
set LIVEKIT_API_KEY=devkey
set LIVEKIT_API_SECRET=secret
cd rust
REM viewer, in one terminal
set BENCH_ROOM=win-1& set BENCH_SECS=120& set RUST_LOG=info
cargo test bench_view -- --ignored --nocapture
REM sharer, in another (BENCH_WINDOW: a window with something moving at 60 fps)
set BENCH_ROOM=win-1& set BENCH_SECS=120& set BENCH_CODEC=h264& set BENCH_HEIGHT=1440& set BENCH_FPS=60& set BENCH_MBPS=20& set RUST_LOG=info
cargo test bench_share -- --ignored --nocapture
```

Run it at 1440p60 / 20 Mbps and 1080p120 / 30 Mbps, on NVIDIA and on Intel.
The `bench share:` line every 2 s gives fps and Mbps sent against WebRTC's
target, and how long packets queued. The viewer gives fps decoded, freezes,
loss and PLIs.

A capped upload is what shows whether the encoder follows a falling target.
On Linux that was a network-namespace rig; on Windows, find a way that needs
no admin, or ask the user. Without a cap the target rarely moves.

### 2. The library on Windows

Build `rift_ffenc.dll` with `h264_nvenc`, `h264_qsv` and `h264_amf`, and the
smallest FFmpeg that holds them: the same `--disable-everything` idea as
`build.sh`, plus `--disable-autodetect`.

- **The toolchain is your call.** MSYS2 with MinGW-w64, or MSVC through
  MSYS2 (`--toolchain=msvc`). It has to build on GitHub's `windows-latest`,
  which has MSYS2 at `C:\msys64`.
- The DLL is loaded by name with a C ABI, so its compiler need not match the
  crate's. It must not need a runtime DLL the app does not ship: link it
  statically, then check with `dumpbin /dependents` or `objdump -p`.
- Port the round-2 harness (`GPU_ENCODING_TESTS_2.md`, step 1: `check.c`) to
  `LoadLibrary`. Run its `rate` (20 → 5 → 12 Mbps), `still` and `opens` (30
  opens) on NVIDIA and on Intel. **Each second's Mbps against the asked rate
  is the most important number in the whole job.**

### 3. Into the crate

- Let `ffmpeg.rs` and `worker.rs` build on Windows. The library is
  `rift_ffenc.dll` beside `rift.exe`. The encoder is picked by GPU vendor:
  NVIDIA → `h264_nvenc`, Intel → `h264_qsv`, AMD → `h264_amf`. Work out how
  to name the adapter to open on a laptop with two GPUs.
- **Keep Media Foundation as the fallback**: when the DLL won't load or no
  FFmpeg encoder opens, and for AMF until the AMD PC has measured it. Say in
  the results what you would drop and when.
- Build the DLL in `windows/CMakeLists.txt` (or the runner's), the way
  `linux/CMakeLists.txt` runs `native/ffenc/build.sh`, and install it beside
  the exe. Add the steps to `.github/workflows/release.yml`'s `windows` job.
  Check that `scripts/build_windows.ps1` and `scripts/vpk_pack.sh win` carry
  the DLL into the package.
- The Rust live test, `live_gpu_h264_is_seen_with_the_key_and_by_nobody_else`
  (`gpu_live_test.rs`), must pass on each GPU:

  ```
  set GPU_LIVE_ONLY=gpu
  cargo test live_gpu_h264 -- --ignored --nocapture --test-threads=1
  ```

  Never use `cargo test --release`.

### 4. Measured again (the after)

Step 1's runs again, through FFmpeg, on both GPUs, with the capped upload if
you found one. Also keep `grep "left out"`: the rate gate firing means the
encoder overshot.

### 5. In the app

Build it (`powershell -File scripts\build_windows.ps1`) and ask the user to
share a game or video at 60 and 120 fps, H264, with someone watching. The
sharer's log should name the FFmpeg encoder at startup and when the share
starts. Look at the picture and the sound against it.

## When done

1. Write the numbers into `GPU_ENCODING_WINDOWS_RESULTS.md` next to this
   file: before and after, per GPU, per rate, and what was not run. Commit it
   and push `gpu-encoding`. Push the code commits along the way, so nothing is
   lost if the session ends.
2. Update the docs in the code commits:
   - `ARCHITECTURE.md` ("Encoding a share on the GPU");
   - the module docs in `encoder/mod.rs`;
   - `RIFT_PATCHES.md`;
   - `assets/licenses/`;
   - `TESTING.md`'s rows, with what was checked and what was not.
3. Tell the user what is done, what is unproven (AMF at least), and that the
   Linux side merges it into `dev`.
