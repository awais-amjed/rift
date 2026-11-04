# Step 1 on AMD: the Windows GPU share path on AMF

Nov 2–3 2026, branch `gpu-codecs`. Proves what `STEP1_WINDOWS.md` left for an AMD card: Rift's own Windows Graphics
Capture session, the D3D11 NV12 converter and FFmpeg's `h264_amf` taking the picture on the GPU. Everything below ran
with `RIFT_FFENC_AMF_TEXTURES=1`.

**Verdict: AMF passes every test and the game-cost gate, at about a fifth of NVENC's cost. The variable
(`RIFT_FFENC_AMF_TEXTURES`) stayed in at first,** because a late viewer waited about 3.5 s on this path and under 1 s
with the switch off. That wait was the viewer's, not AMF's, and was fixed Nov 4 (*A late viewer*, below), and the
variable came out the same day: AMF takes the picture on the GPU like NVENC and Quick Sync. The late viewer is not yet
retried on this machine since.

## The machine

The owner's desktop: RX 9070 XT (driver 32.0.31041.1004), Windows 11 build 26200, one 5120x1440 screen at 240 Hz. The
Ryzen's integrated GPU shows in Device Manager with an error (`CM_PROB_FAILED_POST_START`) and DXGI does not list it,
so `adapter_of(0x1002)` could only pick the 9070 XT; a PC where both AMD GPUs work is not tested. The viewer in the
app was a laptop on the same network. A release build of `gpu-codecs` as a test client (`RIFT_PROFILE`), not the
owner's own Rift.

## How it is proven

- **ffenc on its own** (`native/ffenc/test_windows.sh`, Nov 2): passed on `h264_amf`, every check of
  `check_d3d11.py`; `send_d3d11` took 3.07 ms a picture on average, longest 6.93. NVENC and Quick Sync skipped, as
  they should be. ffmpeg.org could not be reached from the machine, so the build used the tarball fetched for the
  earlier AMF run, through `RIFT_FFMPEG_TARBALL`, which `build.sh` checks against its sha256.
- **Unit tests** (`cargo test --release`, Nov 2): all passed.
- **Live tests** (`gpu_live_test.rs`, a local LiveKit `--dev`, Nov 2): every Windows test passed on AMF, and the log
  of each showed AMF via D3D11 on Rift's session.

  | Test | Result |
  |---|---|
  | `live_gpu_h264_is_seen_with_the_key_and_by_nobody_else` | 233 of 233 unencrypted, 217 of 217 with the key, 0 without it or with the wrong one |
  | `live_gpu_share_resizes_rejoins_and_falls_back` | Passed; the late viewer's first picture in 277 ms (274 ms without the gate, on libwebrtc's capturer) |
  | `live_wgc_switch_keeps_the_share_off_the_gpu` | Passed, on and off |
  | `live_wgc_window_share_ends_when_the_window_closes` | Five closes heard in 20–41 ms, the stop returned in 12–14 ms |
  | `live_wgc_still_window_reaches_a_late_viewer` | The late viewer's first picture in 69 ms; 3 new sessions in the 8 s still (NVENC: none) |
  | `live_wgc_silent_session_moves_to_libwebrtc` | Handed over at 11.8 s |
  | `live_wgc_session_back_after_a_silence` | Pictures back from a new session at 4.8 s, no hand-over |
  | `live_wgc_failing_gpu_moves_to_vp9` | On VP9 1.5 s after the failures began |
  | `live_wgc_swapped_window_refused_once_is_followed`, `live_wgc_swapped_window_moves_to_vp9` | Passed |
  | `live_wgc_encoder_failing_on_a_still_picture_moves_to_vp9` | On VP9 1.1 s later |
  | `live_wgc_silent_from_the_start_moves_to_libwebrtc` | The share started in 4.5 s |

  Without `RIFT_FFENC_AMF_TEXTURES` the log named no AMF texture path, and the resize test ran on libwebrtc's
  capturer, as it should.
- **In the app** (Nov 2, the owner sharing, the laptop watching):
  - The whole screen at 1440p60, 23 Mbps: 5120x1440 encoded at 4096x1152 (AMF's widest is 4096), the viewer at about
    60 fps; 4–5 stutters, each when WebRTC's target fell on loss (once from 23 to 1.06 Mbit/s). `gpu-encoder` 1.7% of
    a core, `share-frames` 0.3%.
  - 1440p120, 34 Mbps: 112–116 pictures a second encoded, the viewer above 110. `gpu-encoder` 8.0% of a core.
  - A window: resized, minimised and restored, and closed (the share ended 74 ms after the close), all as on NVENC.
  - VP9 went to libwebrtc's capturer (`GPU capture does not fit this share`), and H264 afterwards back to Rift's
    session with AMF via D3D11. The switch off: `GPU capture is off; libwebrtc's capturer`.
  - Quit from the tray mid-share: the share stopped in 28 ms and the process exited.
  - A late viewer: *A late viewer*, below.

## The game-cost gate (CS2)

Nov 2–3. CS2 on de_dust2 offline with no bots, lowest settings, uncapped, in front, the player standing still at
one spot. PresentMon 2.6.0 on `cs2.exe` and `threadtop` on the test client, 75 s a round. The whole screen shared as
H264 and watched on the laptop. The first and last second or so of each round, where CS2 was still in the background
(about 44 fps), are cut: each round keeps 73.6–74.9 s. One no-share round where the game lost focus midway is left
out. No-share rounds are the same test whatever share follows, so all four serve as the baseline.

| Round | CS2 fps | p99 ms | GPU busy ms | Share's CPU (of a core) |
|---|---|---|---|---|
| No share (4 rounds) | 546.1–557.3, mean 549.6 | 2.21–2.22 | 1.79–1.83 | – |
| Switch on, 1080p60, 15 Mbps | 539.9, 540.7 | 2.31, 2.34 | 1.85 | about 7% |
| Switch off, 1080p60, 15 Mbps | 465.3, 463.4 | 3.48, 3.61 | 2.10 | about 66% |
| Switch on, 1080p120, 23 Mbps | 535.3, 535.2 | 2.36, 2.38 | 1.87 | about 12% |
| Switch off, 1080p120, 23 Mbps | 436.3, 435.2 | 4.10, 4.12 | 2.17–2.18 | about 92% |

1080p on this screen is 3840x1080. The 120 fps rounds ran at 23 Mbps, the app's choice, not the 30 planned. Every
frame of every round was *Hardware: Independent Flip*; no frame over 16.7 ms, so none near 80 ms. The viewer saw 60
and 120 fps, with no freeze.

**Added per game frame** (`(1 / no-share fps) × lost / (1 − lost)`, limit 0.2 ms):

| | 60 fps | 120 fps |
|---|---|---|
| Switch on (AMF, Rift's capture) | **0.03 ms** (0.06 against the best baseline) | **0.05 ms** (0.07) |
| Switch off (today's path) | 0.33 ms | 0.48 ms |
| NVENC on the laptop, for comparison (`STEP1_WINDOWS.md`) | 0.17–0.18 ms in Hybrid, 0.25–0.29 in Discrete | |

The switch-on share passes. With the switch off the share costs more than the limit, but that is today's path.

**Moving around the map** (no no-share round to compare with, so no cost figure): 1440p120 at 34 Mbps (4096x1152)
509 fps, p99 3.07 ms; 1080p120 at 23 Mbps 511 fps, p99 3.05 ms; no frame over 16.7 ms; the share's threads about 13%
of a core. AMF's `send` took about 6 ms a picture (longest 13 ms, against 8.3 ms a picture at 120). The rate gate left
out 6–10 pictures a second to keep within the rate, so about 110–115 went out, and the viewer stayed around and above
110 fps.

## A late viewer

- **A late viewer waited about 3.5 s on this path, under 1 s with the switch off.** The owner, in the app, five tries
  each: with the switch on, 3–4 s from the click to the picture, the viewer's loading dots for about 3 s first, once
  the app's background showing for about a second; with the switch off, under a second every time. On both paths the
  sharer's log has a keyframe within about 100 ms of the server asking for the layer, and the live tests' late viewer
  gets its first picture in 277 ms against 274 ms. **Found Nov 4:** the viewer in the app watched through the call's
  connection, where the loading dots wait for a keyframe decoded after decryption begins, and the keyframe sent at the
  subscribe goes by before it. With nothing asking for another, the dots gave up at 3 s. The NVENC laptop's 3.1 s and
  Linux's (`STEP2_AMD.md`) were the same wait. The viewer now asks for a keyframe when decryption begins
  (`CALLS.md`, *Starting to watch through the call*). Why the switch-off path was faster was not checked; a keyframe
  that came after decryption began would do it. Not yet retried on this machine.

## Not explained


- **The picture rate fell before WebRTC's target did**, twice at 1440p60. Not followed further.
- **A still window gets a new session every 2–3 s on AMD** (3 in 8 s), where NVENC got none: WGC gave no picture
  for 2 s, so `QuietWatch` opened another. Why it does on AMD and not on NVIDIA is not known. No picture was lost and nothing was handed over.
- **A repeated picture of a still screen takes 9–14 ms in `send`**, against about 2 ms on the switch-off path.
- **An error line when a 1440p120 share stopped:** `failed to negotiate the publisher … Failed to set local offer`,
  6 ms after the stop began and just before `Disconnected … ClientInitiated`. The stop was still clean (39 ms) and the
  next share started normally: a renegotiation racing the close.

## Not tested

A second working AMD GPU in the same PC, other AMD cards, Windows 10, a viewer outside the LAN, the sound against the
picture, a driver reset on AMD.
