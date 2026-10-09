# GPU encoding on Windows through FFmpeg: results

The answer to `GPU_ENCODING_WINDOWS.md`, run Oct 9 2026 by an agent on the
user's dual-boot laptop, booted into Windows: steps 1 to 4. Step 5, the app,
is the user's and has not been run.

**Verdict.** Media Foundation runs past WebRTC's target when the target is below
what the picture costs, so the plan holds. FFmpeg's NVENC and Quick Sync
follow a moved rate within a few percent with no keyframe at a move, and in the
share bench they left the rate gate far less to do. Quick Sync is clean at 60
and 120 fps. NVENC is clean at 60 but reached only about 85 fps at 120 on this
laptop, for a reason inside the share process that was not found (below).
AMF is built and patched but unmeasured, so AMD's GPUs stay on Media
Foundation.

## The machine

| | |
|---|---|
| GPUs | NVIDIA GeForce RTX 3070 Ti Laptop (driver 32.0.16.1074, i.e. 610.74) and Intel Iris Xe, Alder Lake-P (31.0.101.4502) |
| Screen | one 1920x1080 at 165 Hz, wired to the Iris Xe |
| CPU | i7-12700H, 14 cores, 20 threads |
| OS | Windows 11 Home 26200, power plan "Atlas Power Scheme" |
| Server | livekit-server 1.13.7 `--dev` on 127.0.0.1, a fresh one per run; for the capped runs, livekit-server 1.13 in Docker Desktop |
| Toolchain | MSYS2 (UCRT64): gcc 16.2.0, CMake 4.4.4, Ninja, pkgconf |

Which GPU a test process ran on was set with Windows' per-app preference
(`HKCU\Software\Microsoft\DirectX\UserGpuPreferences`, removed after each run).
Media Foundation opens the encoder of the GPU the process runs on. FFmpeg's
NVENC reaches the NVIDIA GPU through CUDA whatever that preference, and its
Quick Sync the Intel one, so the step 4 runs kept the process on the Iris Xe,
which drives the screen.

## 1. Media Foundation, measured (the before)

The share bench (`bench_test.rs`, debug build as the brief says), 120 s
counted, the sharer capturing the **whole screen** with a clip playing in a
borderless 1920x1080 `ffplay` window on top. The clip at 60 fps is
`tools/bench/clip.mp4` (a pan over a Mandelbrot with grain and a test card);
at 120 fps the same clip played at double speed, every frame distinct. The
screen is 1080p, so the "1440p" runs published 1920x1080.

| Run | Encoder | Sent | Mbps against the target, once it held | Rate gate (pictures left out) | Viewer |
|---|---|---|---|---|---|
| 60 fps, 20 Mbps | Intel Quick Sync MFT | 58.9 fps | 0.99 on average, bursts to 1.04 | 338 in 26 bursts, 209 while the target climbed | 56.6 fps, 7 PLIs, one 2 s sample at 0 fps |
| 120 fps, 30 Mbps | Intel Quick Sync MFT | 116.4 fps | 0.99, bursts to 1.09 | 799 in 26 bursts, 384 while it climbed | 114.6 fps, 7 PLIs, 1 freeze |
| 60 fps, 20 Mbps | NVIDIA MFT | 56.3 fps | 0.83 | 644, 629 while it climbed | 57.4 fps |
| 120 fps, 30 Mbps | NVIDIA MFT | 55 to 78 fps | not meaningful | up to 1028, all while it climbed | 55 to 74 fps; **the process crashed** |

- The rate gate leaves pictures out once output runs 0.2 s ahead of the
  target, so pictures left out are Media Foundation over the target. At the
  start of a share WebRTC's target climbs from 1 Mbps, below what the picture
  costs, and both MFTs ran over it: NVIDIA's by about a third of all pictures
  in the first 24 s at 120 fps. Once the target held at the cap, Intel's ran
  over in bursts every few seconds (7 to 30 pictures).
- **The NVIDIA runs are doubtful.** With the process on the NVIDIA GPU the
  screen capture is slower (56 to 79 fps at 120) and the encoder got a nearly
  still picture (0.1 to 1.5 Mbps) though screenshots every 10 s showed the clip
  moving. VP9 from the same process was low too, so the capture, not the MFT,
  is the likely cause. A desktop whose screen is on its NVIDIA card would not
  see this.
- **A crash, twice in two runs:** the NVIDIA MFT at 120 fps, right after
  `encoder: NVIDIA H.264 Encoder MFT closed`, an access violation (0xc0000005)
  in ntdll.dll at offset 0xfa7d (Application Error 1000). The 60 fps run ended
  cleanly. Not investigated, on the user's word that FFmpeg replaces this path.
- **Window capture tops out at about 42 fps here**, H264 and VP9 alike (an
  `ffplay` window, the process on the Iris Xe), where the whole screen gives
  60. The brief's `BENCH_WINDOW` would have hidden the 120 fps question, so
  every run above captured the screen.

## 2. The library on Windows

`native/ffenc/build.sh` now builds on Windows too, in MSYS2's UCRT64 shell:
FFmpeg 9.0.2 with `h264_nvenc`, `h264_qsv` and `h264_amf`, against
nv-codec-headers n11.1.5.4 (drivers from 471.41), AMD's AMF headers 1.5.2 and
Intel's libvpl 2.17.0 built static, each pinned by sha256. A clean build takes
about two minutes. `rift_ffenc.dll` (4.3 MB) exports exactly the eight
`rift_ffenc_*` functions, and `objdump -p` lists only Windows' own DLLs
(KERNEL32, ADVAPI32, bcrypt, ole32 and the UCRT's `api-ms-win-crt-*`). MinGW's
runtime and libstdc++ are inside it. No `--enable-nonfree`.

**What FFmpeg's encoders do with a moved bitrate**, read in the source before
measuring:

- `nvenc.c` reconfigures on a moved `bit_rate` when the GPU reports dynamic
  bitrate, but with a reset and a forced IDR every time. Patched to do neither
  (`nvenc-moving-bitrate-without-keyframe.patch`).
- `qsvenc.c` resets the encoder on a moved rate. The reset failed with
  "incompatible video parameters" whenever the VBV buffer moved too, and
  started a new sequence (a keyframe) while HRD conformance was on. No patch:
  the library opens Quick Sync with the buffer at one second of the share's
  cap, never moves it, and turns HRD conformance off. That needed the cap in
  the library's config, so the ABI went from 1 to 2.
- `amfenc.c` sets the rate once, at open. Patched to send a moved target,
  peak and buffer before the next picture (`amf-encode-moving-bitrate.patch`),
  **unmeasured**.

The round-2 harness (`check.c`), ported to `LoadLibrary`, 2560x1440 at 60 fps,
noise, the rate moved 20 → 5 → 12 Mbps and a keyframe asked for at 7 s. Each
second's Mbps against the rate asked:

| Asked | NVENC unpatched | NVENC patched | Quick Sync |
|---|---|---|---|
| 20 (s 0) | 22.28 | 22.28 | 25.19 |
| 20 (s 1–3) | 20.19–20.63 | 20.19–20.63 | 19.59–20.04 |
| 5 (s 4, the second it fell) | 5.66, **keyframe** | 4.98 | 7.17 |
| 5 (s 5–9) | 5.25–5.36 | 5.23–5.35 | 4.66–5.32 |
| 12 (s 10, the second it rose) | 13.90, **keyframe** | 9.20 | 12.78 |
| 12 (s 11–15) | 11.88–12.51 | 10.71–12.04 | 11.46–12.39 |
| Keyframes | at 0, 4, 7, 10 | at 0 and 7 only | at 0 and 7 only |

- A picture took 6.8 to 7.1 ms on NVENC and 7.7 to 10 ms on Quick Sync at 1440p
  (worst 7.5 and 14), inside the 16.7 ms of 60 fps; at 1080p, paced to 120 fps
  in real time, 4.1 to 4.9 ms and 5.3 to 6.9 (worst 17.2 once), on noise or on
  the clip's own frames alike.
- **still:** 0.01 Mbps on both after the first second, 0.14 (NVENC) and 0.30
  (Quick Sync) after the asked-for keyframe.
- **opens:** 0 of 30 failed on either.

The first build handed FFmpeg the caller's bytes, and FFmpeg copied each into a
fresh 3 MB buffer. In the harness NVENC's time per picture crept from 7.6 to
16.6 ms after about 13 s; in the share bench two of four runs stalled the
whole process for up to 10 s at a time (see 4). The library now keeps four
pictures for the encoder and reuses whichever it has let go of: same bytes
out, 6.8 ms flat, no stall since.

## 3. Into the crate

- `ffmpeg.rs` and `worker.rs` build on Windows. Windows' `GpuEncoder`
  (`encoder/windows_gpu.rs`) is FFmpeg's on the shared encoder thread where
  one opens, else Media Foundation's: when the DLL will not load or no FFmpeg
  encoder opens, for AV1, and for AMD, since AMF is unmeasured.
- **Which encoder:** NVENC, then Quick Sync, the first that opens a 640x360
  probe. Each vendor's driver finds its own GPU, so there is no adapter to
  name: NVENC goes through CUDA to the NVIDIA GPU and Quick Sync's dispatcher
  to the Intel one, whichever GPU Windows runs the process on. A laptop with
  both gets NVENC, as on Linux. `RIFT_FFENC_ENCODER` names the one to try
  instead (`h264_qsv` on such a laptop, `h264_amf` on an AMD GPU).
- `windows/CMakeLists.txt` runs `build.sh` through MSYS2 (`RIFT_MSYS2`, default
  `C:/msys64`) and installs the DLL beside `rift.exe`; without MSYS2 it warns
  and builds the app without it. `scripts/build_windows.ps1` refuses a release
  without the DLL. `release.yml`'s `windows` job installs the MSYS2 packages
  into the runner's own `C:\msys64`. `scripts/vpk_pack.sh win` packs the whole
  Release folder, so it carries the DLL with no change.
  `scripts/build_windows.ps1` was run here and produced `rift.exe` with
  `rift_ffenc.dll` beside it; the workflow itself has not run.
- `live_gpu_h264_is_seen_with_the_key_and_by_nobody_else` passed on both:

  | | Unencrypted | With the key | Without it | Wrong key |
  |---|---|---|---|---|
  | NVENC | 176 of 176 | 182 of 182 | 7 decoded, 0 recognisable | 0 |
  | Quick Sync | 177 of 177 | 177 of 177 | 0 | 0 |

- `cargo test`: 97 pass. The 4 `deep_filter` tests fail in this debug build
  with "DeepFilterNet would not load: running pass codegen", the same 4 on the
  branch without these changes (tract's bug, #2611).

## 4. Measured again (the after)

The step 1 bench, the process on the Iris Xe, after the picture-pool fix:

| Run | Encoder | Sent | Mbps against the target, once it held | Rate gate | Viewer |
|---|---|---|---|---|---|
| 60 fps, 20 Mbps | Quick Sync (FFmpeg) | 60.0 fps | 0.94 (0.76–1.02) | 39, all while the target climbed | 60.0 fps, 2 PLIs, no freeze |
| 120 fps, 30 Mbps | Quick Sync (FFmpeg) | 120.0 fps | 0.90 (0.75–0.98) | 194, all while it climbed | 120.0 fps, no PLI, no freeze |
| 60 fps, 20 Mbps | NVENC (FFmpeg) | 59.9 fps | 0.83 (0.61–0.96) | 59, all while it climbed | 59.9 fps, no PLI, no freeze |
| 120 fps, 30 Mbps | NVENC (FFmpeg) | 88.5 fps | 0.67 (0.60–0.70) | 193, all while it climbed | 88.4 fps, no PLI, no freeze |

Against Media Foundation on the same GPU (Intel): the gate never fired once
the target held, where Media Foundation's ran over every few seconds, and
fired less while it climbed (39 and 59 pictures against 209 at 60 fps, 194
and 193 against 384 at 120). Sharer CPU: 25 to 55% of a core.

**NVENC at 120 fps on this laptop.** Inside the share process each picture
took 11.7 ms in the encoder call, against 4.1 ms for the same library, size and
pacing in the harness, and the time is all in handing the picture over
(`rift_ffenc_send`), not in fetching or delivering what comes out. Not the
content (the clip's own frames: 4.4 to 4.9 ms in the harness), not the
process's GPU preference (the harness at the power-saving GPU: 4.1 ms; the
share on the NVIDIA GPU: 79 fps), not a hidden window (4.1 ms), not the
pipeline depth (one more picture in flight: 92 fps). Quick Sync in the same
process took 6 ms. Unexplained; a desktop whose screen is on its NVIDIA GPU
may not see it, and the in-app test will say what the app does here.

**A capped upload, no admin needed.** LiveKit in Docker Desktop, and a helper
container in its network namespace shaping what arrives there, the sharer's
upload, through an `ifb` device and `tbf` (a queue, so a link that delays
before it drops): 30 Mbit, then 8, then 15. 1080p at 120 fps, 30 Mbps cap,
150 s. In the Media Foundation run the shaper started about 30 s late, so its
phases sit later in the count; read from the samples:

| | Media Foundation (Intel) | Quick Sync (FFmpeg) | NVENC (FFmpeg) |
|---|---|---|---|
| At 30 Mbit | target to 30 in 24 s, then cut to about 15 at the link and held | target climbed to 30 | target climbed to 30 |
| Rate gate while the target climbed | 400 | 134 | 181 |
| The cap falls to 8 | target 16 → 5.4, sent 0.9 to 1.0 of it, nothing queued | target 30 → 19 → 9.5 in 4 s, sent 22 → 5.7, under the target (about 0.7) | target 30 → 2.5 (a 250 ms round trip) then about 5.5, sent under it on average, the gate leaving out 1 to 82 pictures every few seconds |
| fps sent | 103 to 116 | 96 to 116 | 46 to 88 |
| Viewer, whole run | 107.9 fps, 1 freeze, 3 PLIs | 108.8 fps, no freeze, 2 PLIs | 84.4 fps, 2 freezes, 2 PLIs, 12 packets lost when the cap fell |

So on a link that tightens, every encoder here followed the falling target
closely enough that nothing waited in WebRTC's queue. Media Foundation's
measured fault is the overshoot while the target climbs and, on Intel, the
bursts at the cap; whether a friend's 4070 Ti Super's MFT overshot a falling
target the way the Windows reports suggest was not something this laptop
could show. Quick Sync stays well under the target on real content (0.65 to
0.9 of it), which is safe but leaves quality unused: a peak above 100%
(`PEAK_PERCENT`) is the knob to try.

`grep "left out"` in every after-run is above; no run logged an `ffmpeg:` line
or `opening the encoder again`.

## What I would drop, and when

- Media Foundation for H264 on NVIDIA and Intel once a release with FFmpeg has
  been out a while with no fallback seen in users' logs (`encoder: no FFmpeg
  here` or `no H264 from`). It stays for AMD until AMF is measured on the AMD
  PC (`RIFT_FFENC_ENCODER=h264_amf`, the harness and the bench as here), and
  for AV1 for as long as AV1 stays parked.

## Not covered

- **AMF**, built and patched, never run.
- **The app (step 5)**, and with it the sound against the picture.
- **NVENC's slowdown inside the share process**, and whether the app shows it.
- **Real 1440p**: this screen is 1080p.
- **Real 120 fps content**: the clip at double speed, not a game.
- **The Linux build** after the shared `build.sh`, `ffenc.c` and ABI changes:
  WSL here has no compiler or libva headers, and installing them needs sudo.
  `bash -n` passes; the Linux side should rebuild and rerun its harness.
- **The release workflow** with the MSYS2 step.
- Media Foundation's crash and its NVIDIA capture problem, left as found.

## How it was run

Everything stayed on the laptop in `%USERPROFILE%\rift-gpu-test\windows\`: the
bench runner (`bench_run.ps1`: a fresh server per run, the clip, a viewer, the
sharer, a screenshot every 10 s, the encoder chosen, the capped mode), the
harness (`check.c`), every log, and `STEP1.md`. A LiveKit server kept running
across runs let the loopback round trip grow from 1 to 96 ms and held the
target near 5 Mbps, and a fullscreen `ffplay` minimised itself when it lost
focus; both were fixed before the runs above and the runs before the fixes
were discarded.
