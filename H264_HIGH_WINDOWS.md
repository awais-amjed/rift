# H264 High on Windows: a brief

A brief for the agent working on Windows, on the user's laptop booted into
Windows. It lives on the `h264-high-windows` branch only and goes when the
work is merged. Read `AGENTS.md`, `CODE_STYLE.md`, and in `CALLS.md` the
sections "Encoding a share on the GPU" and "H264 in High profile" first. The
conventions there hold here too.

**The job:** show that a Windows share made on the GPU goes out in H264 High
and plays, and that the Windows app plays a High share it watches. Nothing
new is meant to be built. Fix what fails, and leave the results on this
branch.

## The machine

The user's dual-boot laptop has an **NVIDIA RTX 3070 Ti Laptop GPU** and
**Intel Iris Xe**. So `h264_nvenc` and `h264_qsv` can both be run here.
`h264_amf` (AMD) is built but cannot run here; the user's AMD PC tests it
later. Say which GPU each run used.

The Oct 9 work (`GPU_ENCODING_WINDOWS.md` on the old `gpu-encoding` branch)
set up MSYS2 UCRT64, Rust, Flutter, Visual Studio Build Tools and
`livekit-server` on this Windows. Check they are still there. Ask the user
before installing or downloading anything.

## What changed since Oct 9

- **Media Foundation is gone** (da6c1407). Windows encodes H264 only through
  FFmpeg (`rift_ffenc.dll`), trying NVENC, then AMF, then Quick Sync. With
  none of them, a share goes out as VP9 on the CPU.
- **GPU shares go out in High** (05d81ba3).
  - `EncoderSettings::h264_high` sets both the encoder's profile and the
    published track's.
  - ffenc's ABI is now 4, for the `high` field, so an old `rift_ffenc.dll`
    will not load. Rebuild it.
  - In `native/ffenc/ffenc.c`, NVENC and QSV take the profile through their
    own `profile` option (`high` / `baseline`). AMF reads
    `AVCodecContext::profile`; FFmpeg 9.0.2's `amfenc_h264.c` maps
    `AV_PROFILE_H264_HIGH` and `AV_PROFILE_H264_CONSTRAINED_BASELINE`.
- **The LiveKit fork** is pinned at b73b6f02 in `rust/Cargo.toml`. It offers
  High alone when asked (`TrackPublishOptions::h264_high`), lists High as
  receivable, and lets the pass-through encoder's formats be negotiated.
- **Proved on Linux, Oct 28 2026.** The Rust live tests passed on NVENC and
  VAAPI. Then a Linux app shared in High (NVENC, 1080p60) and three viewers
  played it: a Linux desktop, Chrome on the web, and an Android phone on its
  hardware decoder (TESTING.md, "A GPU share's H264 in High profile").

## Rules

- **Commit on `h264-high-windows` only, and push it.** Never push `dev` or
  `production`, never tag, and never release. **No `Co-Authored-By`,
  `Claude-Session` or other attribution lines in any commit message, and
  never mention leaving them out.**
- Stage files by name, never `git add -A`. One logical change per commit.
  Docs change in the commit that makes them wrong. Don't commit `.idea/`,
  `SHARE_DIALOG_PLAN.md` or `out.zip`.
- `flutter analyze` must be clean and `cargo test --release` must pass
  before each commit. Run `rustfmt` on the files you touched only.
- Ask before installing anything, and before anything that needs
  administrator rights.
- Logs stay on this machine, in `%USERPROFILE%\rift-gpu-test\high\`. Upload
  nothing.
- Don't create accounts on any Rift server. The app test (step 3) is on the
  user's own accounts and servers. Ask them which to use.
- Never print secrets or tokens, and never touch the clipboard.

## Plan

### 1. Build

- Pull this branch.
- Build the Rust crate in release (`cargo build --release` in `rust/`). This
  fetches the fork at the pinned commit from GitHub.
- Run `powershell -File scripts/build_windows.ps1`. It builds
  `rift_ffenc.dll` through MSYS2 and fails if the DLL is missing.
- `cargo test --release` must pass.

### 2. The Rust live tests, on each GPU

`rust/src/screenshare/gpu_live_test.rs` shares through a real room to real
viewers. Read its header and `live_test.rs` for the server variables. Use
`livekit-server --dev` with key `devkey` and secret `secret`.

```
set LIVEKIT_URL=ws://127.0.0.1:7880
set LIVEKIT_API_KEY=devkey
set LIVEKIT_API_SECRET=secret
set RIFT_FFENC_LIB=<the built rift_ffenc.dll>
cd rust
cargo test --release live_gpu_ -- --ignored --test-threads=1
```

- Run it once on NVENC (the default), then with
  `set RIFT_FFENC_ENCODER=h264_qsv` for Intel.
- The test checks that the encoder's SPS carries `profile_idc` 100 (High) and
  that the sharer's SDP says `profile-level-id=6400`.
- With `GPU_LIVE_ONLY` unset, it also runs the baseline and libwebrtc
  controls.
- If QSV sends `profile_idc` 66 or 77, its `profile` option was not taken.
  Read FFmpeg's `qsvenc_h264.c` to see why.
- For AMF, check by reading only: the profile reaches
  `AMF_VIDEO_ENCODER_PROFILE` in `amfenc_h264.c`.

### 3. The app, with the user

- Run the built app (`build\windows\x64\runner\Release\RiftChat.exe`). The
  log must say "publishing H264 from the GPU, High profile".
- **Windows sharing.** The user shares a window with something moving, at
  1080p60, in H264, in a call on their own server. A second device watches
  it: their phone, or another computer.
  - Check the picture moves and has no artefacts.
  - Check the log's "screenshare: left out N pictures" lines. A few as a
    viewer joins is fine; a steady count is not.
- **Windows watching.** Windows Rift watches a High share. It can come from a
  second Rift on this Windows, started with `set RIFT_PROFILE=b` and signed
  in as another of the user's accounts, or from another computer.
  - Check the picture plays and keeps moving.
  - Check the log has no decode errors.
- Run each on NVENC and on Quick Sync. To force Intel, use
  `set RIFT_FFENC_ENCODER=h264_qsv` before starting the sharing Rift.

### 4. Write it up

- Put the results in `H264_HIGH_WINDOWS_RESULTS.md` on this branch: what ran,
  on which GPU, what passed and what did not. Include a few log lines,
  filtered so no secrets appear.
- If something needed a fix, commit the fix and say why.
- Update `TESTING.md`'s row "A GPU share's H264 in High profile", which
  lists Windows as not yet driven, and the last sentence of `CALLS.md`'s
  "H264 in High profile".
- Push the branch. The Linux side reviews it and merges into `dev`.
