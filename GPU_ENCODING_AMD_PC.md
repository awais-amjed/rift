# GPU encoding tests: the AMD PC, on Linux and on Windows

A brief for the agent on the user's AMD PC: Radeon RX 9070 XT beside the CPU's
own Radeon graphics, one 5120x1440 screen at 240 Hz. It boots both Linux and
Windows; **Part A is on Linux, Part B on Windows**, and the user says which you
are on. It lives on the GPU test branches only and goes when its questions
are answered. **Your branch is `gpu-encoding-amd`**, made from `gpu-encoding`;
the NVIDIA laptop tests at the same time on `gpu-encoding-nvidia`.
Your results go in `GPU_ENCODING_AMD_PC_RESULTS.md` beside it,
one section per part; whichever part runs second adds to the file.

Read first: `AGENTS.md`, `ARCHITECTURE.md` ("Encoding a share on the GPU"),
`third_party/ffmpeg/RIFT_PATCHES.md`, and this PC's earlier results:
`GPU_ENCODING_RESULTS_2.md` (Linux, Oct 9 2026) and
`GPU_ENCODING_AMD_WINDOWS_RESULTS.md` (Windows, Oct 11 2026). They have the
numbers to compare against. `TESTING.md`'s rows on GPU shares say what has and
has not been driven.

## What changed since the last runs (Oct 16 2026, tested on Intel and NVIDIA only)

1. **The newest picture wins** (`rust/src/screenshare/latest.rs`). The capture
   and encoder queues were two deep and dropped the picture *just made* when
   full, so an encoder that fell behind always worked on the stalest one. Each
   is now one waiting picture that a newer one replaces.
2. **The stream says its colours** (`native/ffenc/ffenc.c`): BT.601, limited
   range, written into the SPS by FFmpeg's encoders (VAAPI and AMF here).
   Media Foundation is left untagged.
3. **The rate gate counts keyframes.** Its 5 s log line now reads like
   `left out 12 pictures (12 within 1 s of a keyframe) to keep … within … bps;
   keyframes: 1, 298 KB average`.
4. **Keyframes an encrypted viewer could not read.** LiveKit's frame encryption
   leaves only the first slice's NAL header and one more byte readable, and a
   receiver reads the IDR's PPS id from there. FFmpeg's VAAPI encoder wrote
   slice type 7, which pushed the id one bit into the ciphertext: about one
   keyframe in two was dropped by whoever was watching, so they froze each time
   somebody joined. Found on Intel; **AMD on Linux goes through the same FFmpeg
   code, so it had the bug too**, and the fix
   (`third_party/ffmpeg/vaapi-encode-h264-short-slice-types.patch`) has not run
   here. **On Windows nobody knows yet whether AMF or Media Foundation write
   their slice headers the same way.** `h264::idr_readable_when_encrypted`
   checks a keyframe; a share logs `this encoder's keyframes put the slice's
   PPS id past what encryption leaves readable` once if it happens,
   `live_gpu_h264_is_seen_with_the_key_and_by_nobody_else` fails on one, and so
   does Media Foundation's `each_hardware_encoder_makes_decodable_h264`.
5. **Encoder timings in the log** (`encoder/timings.rs`). Every 5 s an FFmpeg
   session logs `encoder: …: send 7.3 ms, encode 0.0 ms, deliver 0.0 ms a
   picture over 300 (longest 12.6)` (VAAPI does its work inside `send`).
6. **`bench_churn`** in `bench_test.rs`: a viewer joining every 4 s, staying 2 s
   after its first picture, leaving. Run beside `bench_view` and `bench_share`,
   it shows what each join's keyframe costs the viewer already watching.
7. **The probe**: `gpu_test/ffenc_probe.c` encodes synthetic pictures
   through the encoder library into a file, and `gpu_test/check_h264.py`
   says whether its keyframes stay readable when encrypted.

**The numbers from Linux on Intel (Iris Xe, iHD 26.2.4), Oct 16, to set yours
beside:** a 2560x1440 noisy pattern at 60 fps and 8 Mbps, encrypted, a viewer
joining every 4 s. Before the fix the viewer already watching decoded 50 to 55
fps, dipping to 17.5, with 4 to 11 PLIs in 30 to 40 s, and the slowest joiner
waited 1.3 s for a picture. Fixed: 60.0 fps, no PLIs, joiners 136 to 204 ms.
Without anyone joining, both held 60.0.

## Common to both parts

- `git fetch` and check out `gpu-encoding-amd`. Ask the user before installing
  anything, and before anything that needs administrator rights.
- A LiveKit server: `livekit-server --dev` (1.13.7 last time), a fresh one per
  run, with `LIVEKIT_URL=ws://127.0.0.1:7880`, `LIVEKIT_API_KEY=devkey`,
  `LIVEKIT_API_SECRET=secret`.
- Rust tests in release (`cargo test --release …`), which is what users run.
  On Windows the last briefs said never `--release`; try it, and if it will
  not build say why and use debug for that step only. Every number says which.
- **The churn bench**, used throughout: `bench_view`, then `bench_share`, then
  `bench_churn`, all three with the same `BENCH_ROOM`, in that order, a few
  seconds apart, in separate terminals. `bench_share` takes `BENCH_CODEC=h264
  BENCH_HEIGHT=… BENCH_FPS=… BENCH_MBPS=… BENCH_SECS=60`. What matters is
  `bench_view`'s last line (fps decoded, freezes, **PLIs**: the watching viewer
  asking for a keyframe because it lost one), `bench_churn`'s first-picture
  times, and in `bench_share`'s log the rate gate's and the encoder's lines.
  Run each at 1440p60 / 20 Mbps and 1080p120 / 30 Mbps, as in the earlier runs.
- Pictures: a moving one (the Counter-Strike 2 clip from last time if it is
  still in `~/rift-gpu-test` or `%USERPROFILE%\rift-gpu-test`, else
  `ffplay -f lavfi "testsrc2=size=2560x1440:rate=120,noise=alls=10:allf=t"`),
  and for section 4 a still one: a long text document maximised in an editor.
- Logs go in `~/rift-gpu-test/oct16/` (Linux) or
  `%USERPROFILE%\rift-gpu-test\oct16\` (Windows). Never commit them.

**If any encoder's keyframes come out unreadable** (beyond the unpatched VAAPI
library, which should): stop and tell the user before changing anything. Write
down the slice types `check_h264.py` printed. The fix is a design decision: an
encoder option that writes the short slice types (2 and 0) if FFmpeg has one,
a patch in `third_party/ffmpeg/` if FFmpeg writes the header itself, or
rewriting the first slice header in Rust if the driver writes it. Do not start
on the last without the user's go-ahead.

## Part A: Linux (VAAPI on Mesa)

1. **Build two libraries**, each into a folder outside the repo:
   - the fixed one: `native/ffenc/build.sh ~/rift-gpu-test/ffenc`;
   - the one from before the fix, for comparison: `git worktree add
     ~/rift-gpu-test/before 289df856` and run that tree's
     `native/ffenc/build.sh ~/rift-gpu-test/ffenc-before`. Remove the worktree
     when done (`git worktree remove`). Never `git stash`.

   Point the tests at one with `RIFT_FFENC_LIB=…/librift_ffenc.so`. Note the
   Mesa version and which render node is the RX 9070 XT (`vainfo`, `ls
   /dev/dri`), as round 2 did.
2. **The probe**, on each library:
   `cc -O1 -I native/ffenc gpu_test/ffenc_probe.c -o ~/rift-gpu-test/ffenc_probe -ldl`,
   then `ffenc_probe <lib> h264_vaapi /dev/dri/renderD12x out.h264` and
   `python3 -I gpu_test/check_h264.py out.h264`. Expect `FAIL` with slice
   type 7 before the fix, `OK` with 2 and 0 after.
3. **The colour tag**: `ffprobe -v error -show_streams -select_streams v out.h264
   | grep color` on the fixed library's file. Expect `color_range=tv` and
   `smpte170m` for the other three.
4. **The live test**, on each library:
   `GPU_LIVE_ONLY=gpu cargo test --release live_gpu_h264 -- --ignored --nocapture --test-threads=1`.
   It should fail before the fix and pass after.
5. **The churn bench** on each library, at both sizes. Capture a window under
   X11 or Xwayland as round 2 did (`XDG_SESSION_TYPE=x11`, `BENCH_WINDOW` set to
   the `ffplay` window's title). Before: the watching viewer's PLIs and dips;
   after: none, joiners quick.
6. **The rate gate's keyframe lines** (change 3) from the fixed library's
   runs, moving and still. On Intel at 1440p60 and 8 Mbps a still text screen
   made keyframes of about 300 KB and about 12 pictures were left out after
   each; a moving one about 50 KB and none. Record yours; change nothing.
7. **The app** (the user's, optional): a Linux build (`flutter build linux
   --release`, which builds the library with the patch) sharing in H264 to a
   second device in an encrypted voice channel while a third person joins and
   leaves. The device already watching should not stall when the other joins.

## Part B: Windows (AMF, and Media Foundation behind it)

1. **Build the library** in MSYS2's UCRT64 shell:
   `native/ffenc/build.sh ~/rift-gpu-test/ffenc`, then point the tests at
   `rift_ffenc.dll` with `$env:RIFT_FFENC_LIB`. Build the probe:
   `gcc -O1 -I native/ffenc gpu_test/ffenc_probe.c -o ~/rift-gpu-test/ffenc_probe.exe`.
2. **AMF**, the default on AMD:
   - the probe: `ffenc_probe.exe <dll> h264_amf "" amf.h264`, then
     `python -I gpu_test/check_h264.py amf.h264`;
   - the colour tag: `ffprobe … amf.h264 | findstr color` (expect `tv` and
     `smpte170m` as above);
   - the live test: `$env:GPU_LIVE_ONLY = "gpu"`, then
     `cargo test --release live_gpu_h264 -- --ignored --nocapture --test-threads=1`;
   - the churn bench at both sizes, capturing the **whole screen** (the
     5120x1440 screen publishes 4096x1152 at 60 and 3840x1080 at 120, as last
     time).
3. **Media Foundation**, which a share falls back to on AMD when FFmpeg's
   library will not load or AMF will not open. Reach it by pointing
   `$env:RIFT_FFENC_LIB` at a file that does not exist; the log then says the
   library did not load and names AMD's MFT.
   - `cargo test --release each_hardware_encoder_makes_decodable_h264 -- --ignored --nocapture`
     with `$env:GPU_ENCODER_DUMP` set to a folder: it now fails on an
     unreadable keyframe; run `check_h264.py` on each `gpu-*.h264` too;
   - the live test and the churn bench as for AMF.
4. **The rate gate's keyframe lines** from the AMF runs, moving and still.
   AMF keeps a one-second buffer like VAAPI's, so expect large still
   keyframes. Record; change nothing.
5. **The app** (the user's, optional): a build from `scripts/build_windows.ps1`
   (it carries the DLL), the same encrypted share with someone joining and
   leaving, at 60 and 120 fps. The log (Settings → Help → Logs → Open folder)
   should have `encoder: AMF (…) encodes H264` and not the `PPS id past what
   encryption leaves readable` line.

## Rules

- **Commit on `gpu-encoding-amd` only, and push it.** Never push any other
  branch (`gpu-encoding`, `gpu-encoding-nvidia`, `dev`, `production`), never
  tag, never release. **No `Co-Authored-By`, `Claude-Session` or other
  attribution lines in any commit message, and never mention leaving them
  out.**
- Stage files by name, never `git add -A`. One logical change per commit, the
  docs in the commit that makes them wrong (`AGENTS.md`). `cargo test` passing
  and `flutter analyze` clean before each commit; `rustfmt` on touched files
  only.
- Ask before installing anything or anything needing administrator rights.
- Upload nothing, commit no logs or recordings. No accounts on any Rift
  server. Never print secrets or tokens, never touch the clipboard.

## When done

Write `GPU_ENCODING_AMD_PC_RESULTS.md`: the machine (GPU, driver or Mesa
version, render node, OS build), each step's numbers with the build mode, what
passed and failed, and what was not run. Commit it, push `gpu-encoding-amd`, and
tell the user the Linux side merges the code into `dev`.
