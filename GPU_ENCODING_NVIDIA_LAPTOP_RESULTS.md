# GPU encoding tests: the NVIDIA laptop, on Windows — results

The answers to `GPU_ENCODING_NVIDIA_LAPTOP.md`, run Oct 16 2026 on the
`gpu-encoding-nvidia` branch. Like the brief, this file lives on the GPU test
branches only. Logs and streams stayed on the laptop.

## The machine

| | |
|---|---|
| CPU | Intel Core i7-12700H (6 performance, 8 efficiency cores), 32 GB |
| GPUs | Intel Iris Xe (Alder Lake), driver 31.0.101.4502; NVIDIA GeForce RTX 3070 Ti Laptop, driver 610.74 (32.0.16.1074) |
| Screen | 1920x1080 at 165 Hz, wired to the Iris Xe |
| OS | Windows 11 Home 25H2, build 26200.9457, power plan "Atlas Power Scheme", on AC power |
| Tools | MSYS2 UCRT64 (gcc 16.2), Rust 1.98.1, livekit-server 1.13.7 (`--dev`, a fresh one per run), ffmpeg 9.0.2 (gyan.dev) for ffplay, ffprobe and the checks |

Every number is from a **release** build (`cargo test --release`) unless it
says debug. The share bench captured the whole screen with the test process on
the Iris Xe, as before. Pictures came from `clip.mp4` (60 fps) and `clip120.mp4`
(120 fps) in a borderless 1920x1080 ffplay window, or a 67 KB text file
maximised in Notepad. All shares were encrypted.

## 1. Keyframes, encrypted

| Encoder | IDR slice type | Probe (`check_h264.py`) | Live test |
|---|---|---|---|
| FFmpeg NVENC | 2 (others 0) | OK, 0 of 6 | passed, 215/215 frames with the key, none without it or with the wrong one |
| FFmpeg Quick Sync | 7 (others 5) | **FAIL**, 6 of 6 | **failed** on the unreadable-keyframe check, 181/215 frames with the key |
| Media Foundation, Intel MFT | 7 (others 5) | **FAIL** (`ffmpeg -c:v h264_mf` on the same MFT) | its test failed on the same check |
| Media Foundation, NVIDIA MFT | not checked | n/a | does not open with the process on the Iris Xe |

**Why it can't be patched.** Intel's runtime in the driver writes the slice
header, not FFmpeg, so no FFmpeg patch can change it. With the stock ffmpeg CLI,
Quick Sync wrote 7 with `low_power` 0 and 1, the main and high profiles,
2 slices, and `repeat_pps`.

**What was decided.** With the user's go-ahead, the share now rewrites such a
header in Rust (`h264::with_readable_pps_id`, commit `9d9a3047`). It does not
shorten the header, because that would move the slice data, which CABAC and PCM
alignment need left in place. Instead:
- the slice type goes from 7 to 2;
- `idr_pic_id` is lengthened by the 4 bits that saves, still one value for each
  original value;
- the header keeps its length, so everything after it is left bit for bit.

It runs only on keyframes that fail the check, so NVENC's are left alone.

How it was checked:
- **Unit tests** on real Quick Sync bytes.
- **Rewriting whole streams.** All 120 Quick Sync pictures and all 180 Media
  Foundation pictures decoded identically to the originals (`ffmpeg -f
  framemd5`), with no decode errors and every keyframe now readable.
- **Live test.** Quick Sync passed, with 213/214 frames decoded with the key.
- **Media Foundation's test.** It passed, now checking what a share sends. It
  also writes its dump before checking, so a failing stream is kept.
- **In the share.** A temporary log line, not committed, showed every keyframe
  arriving unreadable and leaving readable.

**The churn bench.** 1080p60 at 20 Mbps for 60 s, with a viewer joining every
4 s:

| | Viewer already watching | PLIs | Joiner's first picture, median / slowest |
|---|---|---|---|
| Quick Sync, moving, without the fix | 36.0 fps | 45 | 815 ms / 3.0 s |
| Quick Sync, moving, with the fix | 60.0 fps | 0 | 155 / 222 ms |
| Quick Sync, text, without the fix | 45.0 fps | 18 | 974 ms / 2.1 s |
| Quick Sync, text, with the fix | 55.2 fps | 0 | 381 / 602 ms |
| NVENC, moving | 59.9 fps | 0 | 165 / 208 ms |
| NVENC, text | 59.4 fps | 0 | 316 / 412 ms |

The text runs' short freezes, 24 of them, came from the rate gate (section 4),
not from lost keyframes.

A first "without the fix" binary turned out not to be the old code: no warning,
no PLIs. Its runs were discarded. The binary used above was built from the old
code with a temporary log line, and logged the warning.

## 2. The colour tag

`ffprobe` on the probe's streams found `color_range=tv`, and `smpte170m` for
`color_space`, `color_transfer` and `color_primaries`, on both NVENC and Quick
Sync. Media Foundation's stream reads `unknown`, as expected.

## 3. NVENC reaching only 88 of 120 fps: two causes, both fixed

All runs were at 1080p120, 30 Mbps, `clip120.mp4`.

**The baseline.**
- Release: 77.6 fps at the viewer, 120 s.
- Debug: 87.5 fps, 60 s, so the build mode was not the cause.
- `send` started at 4.1–4.3 ms a picture, then climbed to 11.4–11.9 ms within
  about 10 s. `encode` read 0.0 throughout, because FFmpeg's NVENC waits for
  the bitstream inside `avcodec_send_frame`.
- `nvidia-smi`: P0 (core 1410 MHz, memory 7001 MHz, video 1230 MHz) for the
  first seconds. Then **P8** (210 / 405 / 555 MHz) for the rest of the share,
  with the encoder 46–58% busy. The driver saw 3% GPU load at P0 and dropped
  to idle.
- The C harness's 4.1 ms (Oct 9) came from runs too short to reach P8.

**Cause 1, NVENC's wait at the idle clock.** In FFmpeg's NVENC, `delay` is the
same field as `async_depth`, and a picture comes out once
`ready + pending >= delay`. Holding one picture therefore needs `delay=2`, not
the brief's 1.

| `delay` | `send` | Viewer fps (capture throttled, see below) |
|---|---|---|
| 0 | 11.9 ms | 77.5 |
| 1 | 11.9 ms | 78.2 (no change, as the source says) |
| 2 | 5.4 ms | 94.5 |

**Cause 2, Windows throttling the process.** Quick Sync reached only 88.7 at
120 today, where it reached 120.0 on Oct 9. The Oct 9 debug binary also got
88.8, so the code was not the cause. A temporary counter showed capture
delivering about 106 pictures a second for 5 s, then 91–95, with both the clip
and ffplay's own test pattern.

Turning off Windows' power throttling for the process
(`SetProcessInformation(ProcessPowerThrottling)`, both execution speed and
timer resolution) fixed it:
- capture held 119.5–119.9 pictures a second;
- Quick Sync's viewer got 118.3 fps.

**Both together (final code):**

| | Viewer fps | Notes |
|---|---|---|
| NVENC, `delay` 0, unthrottled | 87.1 | `send` 11.4 ms, P8 |
| NVENC, `delay` 2, unthrottled, 60 s | 118.0 | `send` 1.3–1.5 ms, GPU at P3 (video 585–600 MHz, encoder about 71% busy) |
| **NVENC, final, 120 s** | **118.7** | 24.5 Mbps; memory 6001 MHz, core 660–705 MHz; no freezes, no PLIs; the gate left out 186 pictures, all in the first 30 s while the estimate climbed, none at the cap |
| **Quick Sync, final, 120 s** | **117.7** | 22.0 Mbps, `send` 7.2 ms, no freezes, no PLIs, 25 left out |
| NVENC at 60 fps with churn, final (`delay` 0) | 59.8 | 0 PLIs, joiners 157 / 196 ms |

**Decided and committed.**
- `be06ed47`: the capture thread holds the process unthrottled while a share
  runs, and hands the choice back to Windows when it ends.
- `9b194a14`: NVENC's `delay` is `2` above 60 fps and `0` at 60 and below,
  automatically, with no env var. The library's config gained `delay_frames`,
  so the ABI went from 2 to 3. `gpu_test/ffenc_probe.c` was updated to match.

MMCSS thread priority and moving delivery off the encoder thread were not
tried: `deliver` was 0.1 ms, and the timings were even, without long tails.

## 4. Keyframes against the rate gate

From the churn runs in section 1 (1080p60, 20 Mbps cap, with the fix):

| | Keyframe size | Pictures left out |
|---|---|---|
| NVENC, moving | 47 KB at the start, 183–227 KB once the estimate reached the cap | 15 in the first 15 s, about 9 within 1 s of a keyframe; none after |
| Quick Sync, moving | 52 KB, then 169–210 KB | none |
| NVENC, still text | about 95 KB | 6 in the first 5 s, then none. The estimate stayed at 4.8–5.6 Mbps |
| Quick Sync, still text | 129–214 KB, mostly 150–200 | 10–31 every 5 s, **all** within 1 s of a keyframe, about 280 in 70 s. The viewer decoded 55.2 fps with 24 short freezes, no PLIs. The estimate stayed at 4.7–5.7 Mbps |

So Quick Sync on still text behaves like Linux VAAPI did: big keyframes, and
pictures left out after each. NVENC behaves like Linux NVENC. Nothing was
changed.

## 5. The app

Not run, because it is optional and up to the user.

## Also found

- **The AV1 live test fails on this laptop.**
  `live_gpu_av1_is_seen_with_the_key_and_by_nobody_else` reports "No hardware
  AV1 encoder opened (Intel® Hardware Accelerated AV1 Encoder MFT: left to
  FFmpeg)". It opens through the share's filter, which since `9af75463` ("Keep
  Media Foundation for AMD GPUs only") skips Intel's MFTs. The failure predates
  this work, and AV1 is parked, so it was left alone. The H264 live tests and
  `live_gpu_share_resizes_rejoins_and_falls_back` passed on NVENC and Quick
  Sync with the final library.
- `cargo test --release`: 144 passed, 15 ignored. `flutter analyze`: clean.

## Not run

- The app (section 5).
- AMF and AMD (the AMD PC's brief).
- Media Foundation's NVIDIA MFT, which needs the process on the RTX.
- A capped upload.
- 1440p.
- A real game.
- The throttling fix in the app itself. Its window, unlike the windowless
  test process, is something Windows can judge visible, so whether a real
  share was throttled is inferred, not measured.
- Linux after the ABI bump: `librift_ffenc.so` has to be rebuilt by
  `build.sh`, as the bundle build does.
