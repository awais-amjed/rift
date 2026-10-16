# GPU encoding tests: the NVIDIA laptop, on Windows

A brief for the agent on the user's dual-boot laptop, **booted into Windows**:
RTX 3070 Ti Laptop beside Intel Iris Xe (Alder Lake), one 1920x1080 screen at
165 Hz wired to the Iris Xe. It lives on the `gpu-encoding` branch only and goes
when its questions are answered. Your results go in
`GPU_ENCODING_NVIDIA_LAPTOP_RESULTS.md` beside it.

Read first: `AGENTS.md`, `ARCHITECTURE.md` ("Encoding a share on the GPU"),
`third_party/ffmpeg/RIFT_PATCHES.md`, and `GPU_ENCODING_WINDOWS_RESULTS.md`,
which is this laptop's last run (Oct 9 2026) and has the numbers to compare
against. `TESTING.md`'s rows on GPU shares say what has and has not been driven.

## What changed since the last run (Oct 16 2026, all tested on Linux only)

1. **The newest picture wins** (`rust/src/screenshare/latest.rs`). The capture
   and encoder queues were two deep and dropped the picture *just made* when
   full, so an encoder that fell behind always worked on the stalest one. Each
   is now one waiting picture that a newer one replaces.
2. **The stream says its colours** (`native/ffenc/ffenc.c`): BT.601, limited
   range, written into the SPS by FFmpeg's encoders. Media Foundation is left
   untagged.
3. **The rate gate counts keyframes.** Its 5 s log line now reads like
   `left out 12 pictures (12 within 1 s of a keyframe) to keep … within … bps;
   keyframes: 1, 298 KB average`.
4. **Keyframes an encrypted viewer could not read.** LiveKit's frame encryption
   leaves only the first slice's NAL header and one more byte readable, and a
   receiver reads the IDR's PPS id from there. FFmpeg's VAAPI encoder wrote
   slice type 7, which pushed the id one bit into the ciphertext: about one
   keyframe in two was dropped by whoever was watching, so they froze each time
   somebody joined. Fixed for VAAPI with an FFmpeg patch. **Nobody knows yet
   whether NVENC, Quick Sync or Media Foundation on Windows write their slice
   headers the same way** (Linux NVENC writes types 2 and 0, which is fine).
   `h264::idr_readable_when_encrypted` checks a keyframe; a share logs
   `this encoder's keyframes put the slice's PPS id past what encryption leaves
   readable` once if it happens, `live_gpu_h264_is_seen_with_the_key_and_by_nobody_else`
   fails on one, and so does Media Foundation's
   `each_hardware_encoder_makes_decodable_h264`.
5. **Encoder timings in the log** (`encoder/timings.rs`). Every 5 s an FFmpeg
   session logs `encoder: NVENC …: send 1.2 ms, encode 9.8 ms, deliver 0.4 ms a
   picture over 600 (longest 14.1)`.
6. **`bench_churn`** in `bench_test.rs`: a viewer joining every 4 s, staying 2 s
   after its first picture, leaving. Run beside `bench_view` and `bench_share`,
   it shows what each join's keyframe costs the viewer already watching.
7. **The probe**: `gpu_test/ffenc_probe.c` encodes synthetic pictures
   through `rift_ffenc.dll` into a file, and `gpu_test/check_h264.py` says
   whether its keyframes stay readable when encrypted.

## Setup

1. `git fetch` and check out `gpu-encoding`. Ask the user before installing
   anything, and before anything that needs administrator rights.
2. Check the toolchain: MSYS2 UCRT64 at `C:\msys64` (gcc, make, CMake, Ninja,
   pkgconf), Rust, Flutter, Visual Studio Build Tools, and `ffmpeg`/`ffprobe`/
   `ffplay` on the PATH. The last run had all of these.
3. Build the library in MSYS2's UCRT64 shell, into a folder outside the repo:
   `native/ffenc/build.sh ~/rift-gpu-test/ffenc`. About two minutes.
   Point the Rust tests at it with
   `$env:RIFT_FFENC_LIB = "$env:USERPROFILE\rift-gpu-test\ffenc\rift_ffenc.dll"`
   (adjust to where MSYS2's home really is).
4. Build the probe in the same shell:
   `gcc -O1 -I native/ffenc gpu_test/ffenc_probe.c -o ~/rift-gpu-test/ffenc_probe.exe`.
5. A LiveKit server: `livekit-server --dev` (1.13.7 last time), a fresh one
   per run, with `LIVEKIT_URL=ws://127.0.0.1:7880`, `LIVEKIT_API_KEY=devkey`,
   `LIVEKIT_API_SECRET=secret`.
6. **Build mode.** The last run's briefs said never `cargo test --release`.
   Use release builds this time (`cargo test --release …`), since that is what
   users run; if one will not build, say why and fall back to debug for that
   step only. Every number below says which it was.
7. Window capture topped out at about 42 fps here last time, so capture the
   **whole screen** (leave `BENCH_WINDOW` unset) with the picture playing full
   screen on top, as before: for a moving picture
   `ffplay -fs -f lavfi "testsrc2=size=1920x1080:rate=120,noise=alls=10:allf=t"`
   or the clip used last time if it is still in `%USERPROFILE%\rift-gpu-test`;
   for a still one, a long text document maximised in an editor. Keep the
   process on the Iris Xe (the screen's GPU) as last time; FFmpeg's NVENC
   reaches the NVIDIA GPU through CUDA either way.
8. Logs go in `%USERPROFILE%\rift-gpu-test\oct16\`. Never commit them.

## 1. Keyframes, encrypted (the question from change 4)

For **NVENC** (the default here) and **Quick Sync**
(`$env:RIFT_FFENC_ENCODER = "h264_qsv"`):

1. **The probe**:
   `ffenc_probe.exe <dll> h264_nvenc "" nvenc.h264` (and `h264_qsv`), then
   `python -I gpu_test/check_h264.py nvenc.h264`. It prints each slice
   type seen and `OK` or `FAIL`.
2. **The live test**, which now also fails on an unreadable keyframe:
   ```
   $env:GPU_LIVE_ONLY = "gpu"
   cargo test --release live_gpu_h264 -- --ignored --nocapture --test-threads=1
   ```
3. **The churn bench**, at 1080p60 and 20 Mbps: `bench_view`, then
   `bench_share` with `BENCH_CODEC=h264 BENCH_HEIGHT=1080 BENCH_FPS=60
   BENCH_MBPS=20 BENCH_SECS=60`, then `bench_churn`, all three with the same
   `BENCH_ROOM` and in that order, a few seconds apart (each its own
   PowerShell window or `Start-Process`). What matters is `bench_view`'s last
   line: fps decoded, freezes and **PLIs** (the watching viewer asking for a
   keyframe because it lost one), and `bench_churn`'s first-picture times. On
   Linux, the bug looked like 50 to 55 fps and 4 to 11 PLIs in 30 to 40 s,
   joiners up to 1.3 s; fixed, 60.0 fps, no PLIs, joiners 136 to 204 ms.

For **Media Foundation**, which shares never use on NVIDIA or Intel GPUs: run
`cargo test --release each_hardware_encoder_makes_decodable_h264 -- --ignored --nocapture`
with `$env:GPU_ENCODER_DUMP` set to a folder, and `check_h264.py` on each
`gpu-*.h264` it writes. For the record only.

**If any encoder fails:** stop and tell the user before changing anything.
Write down the slice types `check_h264.py` printed. The fix is a design
decision: an encoder option that writes the short slice types (2 and 0) if
FFmpeg has one for it, a patch in `third_party/ffmpeg/` if FFmpeg writes the
header itself, or rewriting the first slice header in Rust if the driver writes
it. Do not start on the last without the user's go-ahead.

## 2. The colour tag (change 2)

`ffprobe -v error -show_streams -select_streams v nvenc.h264 | findstr color`
on the probe's NVENC and Quick Sync files. Expect `color_range=tv` and
`smpte170m` for `color_space`, `color_transfer` and `color_primaries`. Linux
VAAPI showed all four `unknown` before the change.

## 3. NVENC only reaching 88 of 120 fps

Last run: NVENC through FFmpeg made 59.9 fps at 60 but 88.5 at 120; a picture
took 11.7 ms in the share process against 4.1 in a C harness on the same
library. Quick Sync did 120.0. The cause was not found. Those runs were **debug
builds**, and changes 1 and 5 are new, so start there.

1. Run the share bench at 1080p120, 30 Mbps, a moving full-screen picture,
   120 s counted, in **release**, and note the viewer's fps and the
   `encoder: … send … encode … deliver` lines. Then once in debug, to see
   whether the build alone was it.
2. Run `nvidia-smi dmon -s pc` alongside and note the GPU and video clocks.
3. Depending on what the timings say:
   - **`encode` dominates and the clocks drop between pictures:** let NVENC
     hold one picture. Add `int32_t delay_frames` to `RiftFfencConfig`, bump
     `RIFT_FFENC_ABI` to 3 (and `ABI` in `encoder/ffmpeg.rs`), and in `ffenc.c`
     use `av_opt_set_int(c->priv_data, "delay", config->delay_frames, 0)` for
     NVENC instead of the fixed `"0"`. For the experiment take it from an env
     var (`RIFT_FFENC_DELAY`, like `RIFT_FFENC_ENCODER`). With 1, `receive`
     returns nothing until the next picture is in, so encoding overlaps the
     next upload, at one picture of delay (8 ms at 120 fps). Compare 0 and 1.
   - **The timings are uneven, with long tails:** raise the encoder thread's
     priority with MMCSS (`AvSetMmThreadCharacteristicsW("Capture")` from
     avrt, through the `windows` crate) at the top of the encoder thread,
     reverted when it ends. Compare.
   - **`deliver` is large:** move delivering off the encoder thread, or out
     of the sink's lock.
4. **Decide:** keep `delay=1` only above 60 fps, and only if the viewer's fps
   at 120 rises clearly (towards 115 or more) with no new freezes, made
   automatic (`delay_frames = if fps > 60 { 1 } else { 0 }`) with a comment
   giving the measurement, and no env var. Keep the priority change if it
   helps on its own. If nothing helps, change nothing beyond what is already
   in. Either way the "cause not found" line in `TESTING.md` becomes the cause
   or what was ruled out, dated, with numbers.

## 4. Keyframes against the rate gate (change 3)

The churn bench from section 1, on NVENC and on Quick Sync, once with a moving
picture and once with the still text: read the rate gate's lines in
`bench_share`'s log. On Linux at 1440p60 and 8 Mbps, VAAPI's keyframes of a
still text screen were about 300 KB and about 12 pictures were left out after
each; moving ones were about 50 KB with none left out; Linux NVENC's were 100
to 115 KB with 1 to 6 left out. Windows' FFmpeg encoders keep a one-second
buffer like VAAPI's, so expect them to look more like VAAPI. Record the
numbers; change nothing.

## 5. The app (the user's part, optional)

Only if the user wants it: build the app (`scripts/build_windows.ps1`, which
carries the DLL), and have the user share a screen in H264 to a second device
in an encrypted voice channel while a third person joins and leaves, at 60 and
at 120 fps. What to watch: the picture on the device already watching
stalling when the other joins. The log (Settings → Help → Logs → Open folder)
should not have the `PPS id past what encryption leaves readable` line.

## Rules

- **Commit on `gpu-encoding` only, and push it** (`git pull --rebase` first:
  the AMD PC pushes to it too). Never push `dev` or `production`, never tag,
  never release. **No `Co-Authored-By`, `Claude-Session` or other attribution
  lines in any commit message, and never mention leaving them out.**
- Stage files by name, never `git add -A`. One logical change per commit, the
  docs in the commit that makes them wrong (`AGENTS.md`). `cargo test` passing
  and `flutter analyze` clean before each commit; `rustfmt` on touched files
  only.
- Ask before installing anything or anything needing administrator rights.
- Upload nothing, commit no logs or recordings. No accounts on any Rift
  server. Never print secrets or tokens, never touch the clipboard.

## When done

Write `GPU_ENCODING_NVIDIA_LAPTOP_RESULTS.md`: the machine (GPUs and driver
versions, screen, Windows build, power plan), each section's numbers with the
build mode, what passed and failed, and what was not run. Commit it, push
`gpu-encoding`, and tell the user the Linux side merges the code into `dev`.
