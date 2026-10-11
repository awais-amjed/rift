# AMF on Windows: a brief

For the user's AMD PC (RX 9070 XT) booted into Windows. It lives on the
`gpu-encoding` branch only, beside `GPU_ENCODING_WINDOWS.md` and its results,
which this follows. Read those two first, then `AGENTS.md` and
`ARCHITECTURE.md` ("Encoding a share on the GPU").

**The job:** find out whether FFmpeg's AMF encoder (`h264_amf`) follows
WebRTC's target the way NVENC and Quick Sync do, so AMD's GPUs on Windows can
leave Media Foundation. Today Rift uses Media Foundation on AMD, because AMF
is built and patched (`third_party/ffmpeg/amf-encode-moving-bitrate.patch`)
but has never run.

There are two parts. Part 1 is the user's and needs no tools. Part 2 is for
an agent on this PC.

## Part 1: in the app (the user, about 15 minutes)

Rift 1.4.0-beta.6 or later already carries the AMF encoder; one setting
switches it on.

1. Quit Rift completely (right-click its tray icon → Quit). A second launch
   hands over to a running copy and the setting would be lost.
2. Open Command Prompt and run:

   ```
   set RIFT_FFENC_ENCODER=h264_amf
   "%LOCALAPPDATA%\CodingFries.Rift\current\rift.exe"
   ```

3. Join a voice channel with someone watching (another device of yours is
   fine). Share a game or a video in **H264**, first at **60 fps**, then at
   **120 fps**, a few minutes each. Watch for: the picture stuttering or
   slowing down and catching up, the sound drifting from the picture, and
   Rift closing.
4. Settings → Help → Logs → **Open folder**. In the newest file, look for:
   - `encoder: AMF (...) encodes H264`: AMF was used. If it says
     `no H264 from AMF` or `no FFmpeg here`, it fell back to Media
     Foundation; note the reason after the colon.
   - `left out`: Rift dropped pictures because the encoder ran over its
     target. A few at the start of a share are normal; regular ones later
     are not.
5. Do the same share once without the setting (start Rift normally), so
   there is Media Foundation to compare with.

Write down what you saw for each run (60/120, AMF/Media Foundation). That
alone can decide it if AMF is clearly better or clearly broken.

## Part 2: measured (an agent on this PC)

The same steps as `GPU_ENCODING_WINDOWS.md`, on AMD only. Its results file
has the numbers to compare against.

1. **Toolchain.** Check what is installed (MSYS2 UCRT64 at `C:\msys64`,
   Rust, Flutter, Visual Studio Build Tools) and ask the user before
   installing anything. `native/ffenc/build.sh` builds `rift_ffenc.dll` in
   MSYS2's UCRT64 shell in about two minutes.
2. **The harness.** `check.c` from `GPU_ENCODING_TESTS_2.md` (step 1), ported
   to `LoadLibrary` as the Windows results describe: 2560x1440 at 60 fps,
   noise, the rate moved 20 → 5 → 12 Mbps, a keyframe asked for at 7 s. Run
   `rate`, `still` and `opens` (30 opens) with `h264_amf`. **Each second's
   Mbps against the asked rate is the number that matters,** and whether a
   moved rate brings a keyframe with it (the patch says it should not).
   Also time each picture at 1440p60 and 1080p120.
3. **The share bench** (`rust/src/screenshare/bench_test.rs`), with
   `RIFT_FFENC_ENCODER=h264_amf` and then without it (Media Foundation): 60
   fps at 20 Mbps and 120 fps at 30 Mbps, capturing the whole screen, with
   `livekit-server --dev` (ask before downloading it). The capped-upload rig
   in the Windows results (LiveKit in Docker Desktop, `tbf` through an `ifb`
   device: 30 → 8 → 15 Mbit) shows whether it follows a falling target; ask
   before installing Docker Desktop if it is missing.
4. **The live test** must pass on AMF:

   ```
   set GPU_LIVE_ONLY=gpu
   set RIFT_FFENC_ENCODER=h264_amf
   cargo test live_gpu_h264 -- --ignored --nocapture --test-threads=1
   ```

   Never `cargo test --release`.
5. **If AMF passes,** make it the default on AMD in
   `rust/src/screenshare/encoder/ffmpeg.rs` (the `h264_amf` exclusion in the
   candidate list) and `windows_gpu.rs`, and update their module docs,
   `ARCHITECTURE.md` and `TESTING.md` in the same commit. If it fails, say how
   and leave Media Foundation in place. A patch, if one is needed, goes in
   `third_party/ffmpeg/` with its story in `RIFT_PATCHES.md`.

## Rules

As in `GPU_ENCODING_WINDOWS.md`:

- **Commit on `gpu-encoding` only, and push it.** Never push `dev` or
  `production`, never tag, never release. **No `Co-Authored-By`,
  `Claude-Session` or other attribution lines in any commit message, and
  never mention leaving them out.**
- Stage files by name, never `git add -A`. `flutter analyze` clean and
  `cargo test` passing before each commit; `rustfmt` on touched files only.
- Ask before installing anything or anything needing administrator rights.
- Logs and recordings stay in `%USERPROFILE%\rift-gpu-test\amd\`. Upload
  nothing, commit no recordings.
- No accounts on any Rift server. Never print secrets or tokens, never touch
  the clipboard.

## When done

Write `GPU_ENCODING_AMD_WINDOWS_RESULTS.md` next to this file: the machine
(GPU, driver version, screen and refresh rate), Part 1 as the user reports it,
Part 2's numbers against Media Foundation's, and what was not run. Commit it,
push `gpu-encoding`, and tell the user the Linux side merges it into `dev`.
