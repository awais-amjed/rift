# AMF on Windows: results

The answer to `GPU_ENCODING_AMD_WINDOWS.md`, run Oct 11 2026 by an agent on the
user's AMD PC booted into Windows: Part 2. Part 1, the app, is the user's,
added below the same day.

**Verdict.** FFmpeg's AMF encoder, with Rift's patch, follows a moved rate the
way NVENC and Quick Sync do, makes no keyframe at a move, and passes the
encryption live test. In the share bench it beat Media Foundation on the same
GPU everywhere: under half the pictures left out by the rate gate, and a
steadier frame rate, most of all on a capped upload. So AMD's GPUs now encode
through AMF (`encoder/ffmpeg.rs`), with Media Foundation behind it only where
FFmpeg's encoder does not open. One weakness against Quick Sync: AMF overshoots
its first second or two, and still trips the rate gate now and then once the
target has settled or while it falls.

## The machine

| | |
|---|---|
| GPU | AMD Radeon RX 9070 XT, driver 32.0.31041.1004, beside the CPU's own Radeon graphics (32.0.21045.5002) |
| Screen | one 5120x1440 at 240 Hz |
| OS | Windows 11 Pro 26200 |
| Server | livekit-server 1.13.7 on 127.0.0.1, a fresh one per run |
| Toolchain | MSYS2 (UCRT64): gcc 16.2.0, CMake 4.4.4, Ninja, pkgconf; Rust 1.97.1; Flutter 3.47.6 |

AMF names itself only "AMD AMF H.264 Encoder", so the logs cannot say which of
the two AMD GPUs it opened; the user saw it on the RX 9070 XT. NVENC ("Cannot load nvcuda.dll") and Quick Sync ("Error
creating a MFX session") fail on this PC, as they should.

## Part 1, in the app

Run by the user on 1.4.0-beta.9, started with `RIFT_FFENC_ENCODER=h264_amf`:
a share in H264 at 60 fps and at 120 fps both reached the viewer smoothly, with
no crash, encoding on the RX 9070 XT. The log was not read, so the
`encoder: AMF (...)` line and the rate gate's `left out` lines were not
checked, and there was no run through Media Foundation to set beside it.

## Part 2

### The library

`native/ffenc/build.sh` built `rift_ffenc.dll` (4.3 MB) unchanged in about three
minutes, downloads included. It exports the
eight `rift_ffenc_*` functions and needs only Windows' own DLLs.

The round-2 harness (`check.c`, ported to `LoadLibrary`, with keyframes counted
per second and a real-time pacing mode), `h264_amf`, 2560x1440 at 60 fps,
noise, the rate moved 20 → 5 → 12 Mbps and a keyframe asked for at 7 s:

| Asked | AMF | Quick Sync (laptop) | NVENC patched (laptop) |
|---|---|---|---|
| 20 (s 0) | **35.30** | 25.19 | 22.28 |
| 20 (s 1–3) | 19.74–20.09 | 19.59–20.04 | 20.19–20.63 |
| 5 (s 4, the second it fell) | 5.31 | 7.17 | 4.98 |
| 5 (s 5–9) | 5.29–5.57 | 4.66–5.32 | 5.23–5.35 |
| 12 (s 10, the second it rose) | 11.40 | 12.78 | 9.20 |
| 12 (s 11–15) | 11.25–12.09 | 11.46–12.39 | 10.71–12.04 |
| Keyframes | at 0 and 7 only | at 0 and 7 only | at 0 and 7 only |

- The patch works: the rate moves take hold in the second they are asked for,
  with no keyframe. The one fault is the first second, 76% over.
- A picture took 3.7 to 4.3 ms in the harness (worst 15.2, the first). Paced in
  real time: 1.5 ms at 1440p60 (worst 2.2) and 3.1 ms at 1080p120 (worst 6.5),
  against 6.8 to 10 and 4.1 to 6.9 on the laptop. The first second paced made
  34.7 Mbps of 20 and 47.3 of 30 again.
- **still:** 0.36 Mbps in the first second, then 0.01, and 0.13 in the second
  of the asked-for keyframe.
- **opens:** 0 of 30 failed.

### The share bench

`bench_test.rs`, debug build, 120 s counted, the sharer capturing the whole
screen with a 1080p60 Counter-Strike 2 clip in a borderless window over all of
it (at 120 fps the clip at double speed). The screen is 5120x1440, so the 60 fps
runs published 5120x1440 fitted to 4096x1152 (`encoder::MAX_SIZE`) and the 120
fps runs 3840x1080. AMF through `RIFT_FFENC_ENCODER=h264_amf`, Media Foundation
with nothing named (this build's default on AMD then).

| Run | Encoder | Sent | Rate gate: all (while the target climbed) | Viewer |
|---|---|---|---|---|
| 60 fps, 20 Mbps | AMF | 59.2 fps (min 50.5) | 134 (92) | 59.2 fps, 0 PLIs, no freeze, 9.8 Mbps |
| 60 fps, 20 Mbps | Media Foundation | 57.5 fps (min 39.0) | 490 (324) | 57.6 fps, 1 keyframe, no freeze, 10.1 Mbps |
| 120 fps, 30 Mbps | AMF | 117.4 fps (min 91.0) | 472 (324) | 117.7 fps, 0 PLIs, no freeze, 14.0 Mbps |
| 120 fps, 30 Mbps | Media Foundation | 110.6 fps (min 59.0) | 1,507 (1,021) | 111.4 fps, 1 PLI, no freeze, 14.0 Mbps |

The clip costs less than the cap at this size (sent was about half the target
once it held, on both), so the cap itself was seldom what limited the rate.
A first AMF run at 60 fps was discarded: from 40 s on it sent 0.7 to 4 Mbps, a
nearly still picture though the clip had been started, and with no screenshot
to show what was on screen it was run again (the run above).

### A capped upload, without Docker or admin

LiveKit was set to bind its media port on 127.0.0.1 only and advertise
192.168.1.2 (`rtc.node_ip`, `rtc.ips`, ICE over TCP off), and a small UDP relay
of our own listened on 192.168.1.2 and forwarded to it. The client gathers only
its LAN address and Windows does not route between that and loopback, so all
media went through the relay. The relay shaped what the clients sent with a
token bucket and a queue, as `tbf` does (a 10 ms burst, at most 250 ms queued,
then drops), and passed the replies back untouched. Through it with no cap,
WebRTC's target reached 30 Mbps at 40 s, as it does without the relay (50 s).
Two faults in the relay were found and fixed before the runs below: it slept
in Windows' 15.6 ms steps, and its bucket did not refill while idle; both read
to WebRTC as congestion.

1080p at 120 fps, 30 Mbps cap, 150 s, the link 30 Mbit, then 8 from 60 s, then
15 from 100 s:

| | AMF | Media Foundation |
|---|---|---|
| 30 Mbit: sent, rate gate, worst wait in WebRTC | 116.4 fps (min 97), 291, 32 ms | 106.2 fps (min 56.5), 1,130, 36 ms |
| 8 Mbit | 98.5 fps (min 58.5), 822, 55 ms | 75.0 fps (min 18.5), 1,646, **420 ms** |
| 15 Mbit | 106.0 fps (min 69), 858, 65 ms | 85.3 fps (min 45.5), 2,069, 63 ms |
| Viewer, whole run | 107.4 fps, 1 freeze, 0 PLIs | 89.5 fps, 5 freezes, 1 keyframe |

The relay dropped nothing in either run: both encoders came down with the link.
The sharer sent under WebRTC's target on average (3.75 Mbps against 6.11 at 8
Mbit for AMF), so AMF's gate firings there are pictures bigger than their share
of the rate, not a rate it fails to follow.

### The live test

`live_gpu_h264_is_seen_with_the_key_and_by_nobody_else` passed on AMF, named
(`RIFT_FFENC_ENCODER=h264_amf`) and as the default once the change below was in:

| | Unencrypted | With the key | Without it | Wrong key |
|---|---|---|---|---|
| AMF, named | 176 of 176 | 164 of 164 | 7 decoded, 0 recognisable | 0 |
| AMF, the default | 176 of 176 | 175 of 175 | 3 decoded, 0 recognisable | 0 |

`cargo test`: 102 pass; the 4 `deep_filter` tests fail in this debug build as
they do without the change (tract's bug, #2611).

### The change

AMF is no longer left out of `candidates()` in `encoder/ffmpeg.rs`: the order
was NVENC, Quick Sync, AMF, and with nothing named this PC logged "no H264 from
NVENC", "no H264 from Quick Sync", then "AMF (AMD AMF H.264 Encoder) encodes
H264". Afterwards AMF was moved ahead of Quick Sync (NVENC, AMF, Quick Sync),
so a PC with Intel graphics beside an AMD card uses the card, as one beside an
NVIDIA card already did; that order has not been run here. Media Foundation stays for an AMD GPU where FFmpeg's library will not load
or AMF will not open. `windows_gpu.rs`, `encoder/mod.rs`, `ARCHITECTURE.md`,
`RIFT_PATCHES.md` and `TESTING.md` say so.

## What I would drop, and when

- Media Foundation for H264 on AMD once a release with AMF has been out a while
  with no `no H264 from AMF` in users' logs. It stays for AV1 for as long as AV1
  stays parked.

## Not covered

- **The app's log and the sound against the picture**: Part 1 was watched,
  not measured.
- **Sharer CPU** was not measured in these runs.
- **A PC with Intel graphics beside an AMD card**: AMF now comes first and
  should encode on the card, but no such PC has run it.
- **Other AMD GPUs and drivers**: one RX 9070 XT, one driver.
- **AMF's first-second overshoot**, left as found; the rate gate covers it.
- **Real 120 fps content**: the clip at double speed, not a game.

## How it was run

Everything stayed on this PC in `%USERPROFILE%\rift-gpu-test\amd\`: the library
build and its log, the harness (`check.c`) and its output, the bench runner
(`bench_run.sh`: a fresh server per run, the clip, a viewer, the sharer, a
screenshot every 20 s), the relay (`shaper/`) and its LiveKit config, the
summaries (`summarise.sh`, `phases.sh`) and every log.
