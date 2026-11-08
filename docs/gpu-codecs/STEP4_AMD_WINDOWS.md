# Step 4 on AMD under Windows: H265, H264 High and the codec ladder

Nov 8 2026, the owner's desktop, `dev` at `88e4d2d0`. H265, H264 in High profile and the codec
ladder (`CALLS.md`, *Stepping a share down*) had passed on Intel and NVIDIA under Linux, on NVENC
and Quick Sync under Windows, and on this PC under Linux (`STEP4_AMD_LINUX.md`). AMD's Windows
encoder, AMF, had only ever sent H264 baseline (`STEP1_AMD.md`), and the RX 9070 XT had only
decoded watched shares through D3D11 in H264, VP9 and VP8 (`STEP3_AMD.md`, *On Windows*).

**Verdict: everything passed, and H265 is safe as Auto's pick here, with two things to know.**
AMF wrote real High and Main streams, and the 9070 XT decoded both through D3D11, with clean
edges at 1080 and at an odd size. Codec, size and rate moves came back within 0.1 to 0.7 s, the
web viewer's step down and back held, and a 1 Mbps upload never stopped the share. Beside CS2,
H265 cost the game what H264 High did, and the share held 60 pictures a second in both. The
two things: after a move through VP9 the share stayed on libwebrtc's capturer for good, and the
rate gate then left out about one picture in seven on a busy pattern, so a viewer got about 52 a
second instead of about 56 (oddity 1, fixed the same evening); and on the 1 Mbps upload the
watcher's clock stood still for 1.2 to 3.3 s four times in the first 46 s. Nothing else was
changed in the code.

## The machine

| | |
|---|---|
| CPU | AMD Ryzen 9 7950X (16 cores), 60 GB RAM |
| GPU | AMD Radeon RX 9070 XT, driver 32.0.31041.1004 (dated Aug 17 2026), draws the screen |
| Second GPU | the Ryzen's iGPU, in error in Device Manager, not offered |
| Screen | one, 5120x1440 at 240 Hz |
| OS | Windows 11 Pro 25H2, build 26200.9457 |
| App | release build of `dev` (`scripts/build_windows.ps1`), `2.0.0-beta.1+52`, two profiles: one sharing, one watching through Rust |
| Server | the laptop's local stack over the LAN; the watcher's Rust path was minted, so its functions were current |
| Remote desktop | RustDesk not connected for any number below (checked before each run) |

## Builds

- `native/ffenc/test_windows.sh` (MSYS2 UCRT64, FFmpeg 9.0.2's command line from WinGet to decode):
  `h264_amf` every picture right, send 3.0 ms a picture on average; NVENC and Quick Sync
  skipped.
- `cargo test --release`: passed, none failed.
- `cargo build --release`, `scripts/build_windows.ps1`, and the web build (the worker compiled
  by hand: `scripts/build_web.sh` reads the package path as a Unix one).

## Does AMF honour the profile?

`test_windows.sh` sends baseline only, and the app's `H264 in High` says what Rift asked for.
FFmpeg 9.0.2's command line, AMF's options as `ffenc.c` sets them (`ultralowlatency`,
`latency`, `preencode 0`, `forced_idr`, `vbr_peak`, `qmin 18`, no B-frames), 5 s of
`testsrc2` at 1920x1080 60 fps, read back with `ffprobe`:

| Asked | ffprobe |
|---|---|
| `h264_amf`, High | `h264`, **High**, 1920x1080, no B-frames |
| `h264_amf`, constrained baseline | `h264`, **Constrained Baseline** |
| `hevc_amf` | `hevc`, **Main**, 1920x1080 |

The command line sets `h264_amf`'s own `profile` option and Rift sets the codec context's;
`amfenc_h264.c` takes the context's first and the option only when that is unset, and both
end in the same `AMF_VIDEO_ENCODER_PROFILE`, so the check stands for the app.

## The GPU lines

Both clients, once joined:

```
watching: shares decode on the GPU (AMD Radeon RX 9070 XT, through D3D11)
encoder: no H264 from NVENC: the encoder did not open: Operation not permitted
encoder: AMF (AMD AMF H.264 Encoder) encodes H264
encoder: AMF (AMD AMF HEVC encoder) encodes H265
This device plays (vp9, vp8, h264, h265)
```

NVENC is tried first and does not open; nothing says CPU.

## The runs

`a` shared an ffplay `testsrc2` window at 1920x1080 with a large clock (the stream's own time),
sound off; `b` watched through Rust; screenshots of the two windows together, delay = pattern
clock minus the watcher's clock in the same shot. Share dialog, Watch and moves by the owner's
hand. The shared window is captured with its frame, so a 1920x1080 window went out at 1866x1080.

| Run | Result | AMD Windows (AMF, D3D11) | AMD Linux / NVENC / Quick Sync |
|---|---|---|---|
| **D.** H265, twice | PASS | Dialog H265 · 11 Mbps. `starting 1080p60 at 11 Mbps, H265`, `H265 in Main`, `track: publishing H265 from the GPU at 11000000 bps`, no "High profile". `b`: `decoding H265 on AMD Radeon RX 9070 XT, through D3D11`. Picture 0.46 s after the watch connection. Delay 17–50 ms, clock moving in every shot. No `no picture`, `stopped working`, `instead` or keyframe waits. Bottom and right edges clean at full screen. Send 2.0–2.4 ms a picture | Linux: 2.4 and 0.53 s, 33–67 ms. Windows NVENC 17–50 ms |
| D, late viewer | PASS | Watch about 31 s after the share started: picture 0.41 s after the connection, with a keyframe sent for it | AMF before the keyframe fix 3.5 s, about 1 s after |
| D, odd size | PASS | A 1315x746 window from the start: captured 1317x778, published 1316x778, decoded 1316x778, edges clean at full screen | Linux 1314x746, clean |
| **E.** H264 High, twice | PASS | Dialog 12 Mbps. `H264 in High`, `track: publishing H264 from the GPU, High profile at 12000000 bps`. `b` decoded H264 through D3D11. Picture 0.41 and 0.65 s; delay 16–34 ms. `no sender capability`: **0** | Same lines on Linux AMD, NVENC and Quick Sync |
| **F.** H265 on 1 Mbps, 90 s | PASS, with stalls | Limit on the laptop's LiveKit before the share, lifted after and confirmed. Picture 2.4 s after Watch. `within` 0.53–1.11 Mbps, mostly about 0.85; 142 pictures left out (127 near one of 14 keyframes). No keyframe wait, no error line in either log, never stopped. Delay: shots began 12.6 s after Watch, so none at 4 or 10 s; from 13 to 46 s mostly 30–70 ms, with the watcher 1.3, 1.9, 1.2, 3.3 and 2.4 s behind in five shots (four stalls: the 1.2 and 3.3 s shots show the same frozen clock), each clearing by itself; 55–96 s, 50–70 ms | Linux AMD 17–67 ms from 10 s, rises of 0.23, 0.43, 2.1 s. Intel under 0.05 s from 10 s. NVIDIA under 0.25 s from 20 s. Windows NVENC at 2 Mbps: 2–6 s stutters |
| **G.** Moves mid-share | PASS | H265→H264 0.22 s, →VP9 0.66 s, →H265 0.26 s, each a new track; 360p 0.10 s and 1080p 0.18 s on the same track; 30 and 60 fps on the same track (no picture line to time them; the owner saw them at once). Nothing `stopped working`, no `the first picture failed` | Linux 0.2–0.6 s; Windows NVENC about 0.25 s |
| **H.** Web viewer steps it down, one cycle | PASS | Web build in a Chrome of its own, a fresh profile, no flags, at a local address. Its Watch: H264 High at 12 Mbps at once (the owner saw it and the note), `b` back in 0.24 s. Back to H265 about 26–30 s after it stopped watching, `b` back in 0.70 s (the owner saw it freeze about half a second) | Linux 0.60–0.63 s; NVIDIA 0.94–0.99 and 0.39–0.46 s |
| **I.** Still, then movement | PASS | The paused pattern window. Still: 6–9 pictures per 5 s. Unpaused (watcher's stats, a shot every 2 s): 5.0 Mbps at 2 s, 7.4 at 10 s, 9.2 at 12 s, 11.1 at 14 s, 10.8–11.6 after: **about 13–14 s to 90%**, sharp throughout. New capture sessions while still: 14 in about 35 s and 17 in 38 s (one every 2–3 s, as `STEP1_AMD.md` saw), with no picture lost or keyframe wait in the watcher's log | Linux AMD 9 s; Intel 10, 10, 18 s; NVENC 10, 10, 8 s |
| **J.** Beside CS2 | PASS | Below | Below |

### J. Beside CS2

CS2 at 2560x1440 borderless on the left half, de_dust2 offline, no bots, the owner standing
still at one spot facing one way. PresentMon 2.6.0, 60 s a round, the first and last seconds in
which CS2 was still in the background cut. `a` shared the game's window at 1080p60 (captured
2562x1472, published 1880x1080); `b` watched with its window behind the game. **Share sound was
on in both share cases** (by the owner's choice after the first case went out that way), off
nowhere, so the two codecs compare with each other but carry the cost of capturing CS2's sound.
Uncapped only: the owner skipped 120 fps rounds, which hold 120 here. "Over 2x" is frames over
twice the round's own mean frame time.

| Case | Mean fps | p99 frame time | Over 2x | Over 16.7 ms | Share |
|---|---|---|---|---|---|
| No share | 618.2 / 621.5 / 621.7 | 3.23–3.24 ms | 373–440 | 0 | — |
| H264 High, 12 Mbps | 573.4 / 561.9 / 564.0 | 3.61–3.72 ms | 522–578 | 0 | 296 a 5 s on average, none left out |
| H265 Main, 11 Mbps | 573.5 / 570.2 / 571.0 | 3.62–3.65 ms | 587–616 | 0 | 295 a 5 s on average, 33 left out in all |

Means: no share 620, H264 High 566 (−8.7%), H265 572 (−7.8%). The share's lowest 5 s
(232–244 pictures) fell between rounds, when the game was not in front. Send 3.0–4.7 ms a
picture, longest 17.2 ms. Every frame was a hardware independent flip.

| Beside a game | No share | H264 | H265 |
|---|---|---|---|
| Intel default encoder (glmark2) | 298 fps | 235 (−21%) | 143 (−52%), share at 50 |
| Intel low power (glmark2) | 300 | 265 (−12%) | 265 (−12%) |
| NVIDIA NVENC (glmark2) | 764 | 744 (−3%) | 736 (−4%) |
| AMD VAAPI, Linux (CS2) | 783 | 754 (−3.7%) | 756 (−3.5%), share at 60 |
| **AMD AMF, Windows (CS2, share sound on)** | **620** | **566 (−8.7%)** | **572 (−7.8%)**, share at 60 |

So on AMF, as on VAAPI and NVENC and unlike Intel's default encoder, H265 is no dearer to a game
than H264. The cost is about twice Linux's, with a different capture (Windows Graphics Capture),
sound capture on, and another OS; compare the shape, not the fps. Nov 5's H264 baseline
watching numbers (`STEP3_AMD.md`) are a different case (watching, not sharing).

## Not run

- Capped rounds in J, and J with share sound off.
- `b` decoding beside the game: its window was behind CS2, and whether its picture was off is
  not logged.
- A whole-screen share at 5120x1440, and a whole-screen share beside the game.
- The delay at 4 and 10 s in F (the first shot was at 12.6 s), and H264 on the limit.
- H's second and third cycles (one was asked for), and when the web stopped watching is not
  logged, so its 26–30 s is from the owner's word and the sharer's log.
- A phone or Firefox viewer, a real slow connection (a limiter drops where a real link queues),
  a real driver reset.
- Rust live tests against the laptop's LiveKit: its keys stay on the laptop. The Windows
  capture ones (`live_wgc_*`) ran that evening against a local LiveKit instead, for oddity 1.

## Oddities

1. **More pictures left out after a move through VP9, and the cause: the share never came back
   to Rift's capture.** At a fresh share the gate left out 1 to 22 pictures in each 5 s
   (11 Mbps, the pattern); after G's move from VP9 back to H265, 38 to 45 in every 5 s for as
   long as the share ran, and the same through H's step down and climb back, which ran on the
   same share (H264 13 to 23 against 1 to 8 fresh). The watcher's stats then read 52 to 56 fps.
   It first looked like AMF opened straight at 11 Mbps making bigger bursts than one moved up
   from libwebrtc's start rate. A test program against `rift_ffenc.dll` ruled that out: H265 on
   the moving pattern at 1080p60, opened at 11, opened at 4 and moved to 11, ramped from 1 over
   10 s, or reopened at 11 in the same process, gave the same frames over 20 s (mean 23.5 to
   23.6 KB, p95 24.3, max 24.8 to 25.0, 11.28 to 11.32 Mbps). The sharer's full log showed the
   cause: the move to VP9 logged `capture: this feed reads memory; on to libwebrtc's capturer`,
   and the share never went back. The move to H265 opened AMF without the share's device (no
   `AMF via D3D11.` line), so every picture after it was scaled on the CPU and uploaded, at 1.7
   ms a picture against 2.1 to 2.2 ms on the GPU's. A share now comes back to Rift's session
   when its feed takes the GPU's pictures again (`CALLS.md`, *How Windows captures a screen*;
   `live_wgc_share_comes_back_from_vp9`). Driven the same evening, the same pattern, sharer and
   watcher on the same PC: a fresh H265 share left out 1 to 12 every 5 s; H265 → H264 → VP9 →
   H265 came back to Rift's session 40 ms after the last move, left out 0 to 15, sent at 2.2 to
   2.5 ms; the web viewer's step down to H264 left out 0, and the climb back to H265 0 to 17.
   The watcher's picture came back 0.2 to 0.6 s after each move, with no `stopped working`, `no
   picture` or keyframe wait in either log. Why pictures through memory left out so many more is
   not known; with the share back on the GPU's it no longer matters here.
2. **Stalls on the 1 Mbps upload** (F): five of 19 shots between 14 and 46 s after Watch had the
   watcher 1.2 to 3.3 s behind, its stats reading 0 or 31 fps, four separate stalls that each
   cleared by itself, with no keyframe wait or other line in either log. Settled after that.
3. **VP9 decoded 1864 wide** where H265 and H264 decoded 1866 (run G), the sharer publishing
   1866 in each. VP9 is libvpx on the CPU, not AMF.
4. **The web build's script** reads the LiveKit package's path as a Unix one, which fails on
   Windows; the worker and the build were run by hand.
