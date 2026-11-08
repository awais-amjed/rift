# Step 4 on AMD under Linux: H265, H264 High and the codec ladder

Nov 8 2026, the owner's desktop, `dev` at `bf4fa79c`. H265, H264 in High profile and the codec
ladder (`CALLS.md`, *Stepping a share down*) had passed on Intel and NVIDIA under Linux and on
Intel and NVIDIA under Windows, never on AMD under Linux, where Mesa's radeonsi is its own
driver (the green letterbox bars came from it).

**Verdict: everything passed, and H265 is safe as Auto's pick here.** Both codecs opened on
the RX 9070 XT through VAAPI, encoding and decoding, with clean edges at 1080 and at an odd
size. The ladder moved for a web viewer and back three times, with the Rust watcher's
picture back about 0.6 s after each move. A 1 Mbps upload never stopped the share. Beside
CS2, H265 cost the game what H264 High did, about 3.5% of an uncapped frame rate and 0.1 ms
of p99, nothing at 120 fps, and the share held 60 pictures a second in both. Nothing was
changed in the code.

## The machine

| | |
|---|---|
| CPU | AMD Ryzen 9 7950X (16 cores), 58 GB RAM |
| GPU | AMD Radeon RX 9070 XT (gfx1201, RDNA4), `/dev/dri/renderD128`, draws the screen |
| Second GPU | the Ryzen's iGPU (Raphael), `/dev/dri/renderD129`, no display |
| Screen | one, 5120x1440 at 240 Hz; the runs used its left half |
| OS | CachyOS, kernel 7.3.1-1-cachyos, GNOME Shell 51.1 on Wayland |
| Mesa / libva | Mesa 26.2.5 (`26.2.5-arch3.1`), libva 2.24.1 (VA-API 1.24) |
| App | release build of `dev`, `2.0.0-beta.1+52`, two profiles (`a` shares, `b` watches), native Wayland |
| Server | the laptop's local stack over the LAN (no `LOCAL_DEV.md` on this machine); the watcher's Rust path was minted, so its functions were current |
| Remote desktop | RustDesk not connected for any number below |

`vainfo` on `renderD128`, H264 and HEVC:

| Profile | Decode (`VLD`) | Encode (`EncSlice`) |
|---|---|---|
| H264 Constrained Baseline | yes | yes |
| H264 Main | yes | yes |
| H264 High | yes | yes |
| HEVC Main | yes | yes |
| HEVC Main10 | yes | yes |

(AV1 Profile0 decodes and encodes, Profile2 decodes; AV1 stays parked.) No `EncSliceLP`
entrypoint: AMD has no low-power switch, and the log never says `, low power`.

## Builds

- `native/ffenc/build.sh`, `test.sh`: pass; H264 and H265 each decoded 30 pictures on
  radeonsi, the bars black; CUDA and NVENC skipped.
- `cargo test --release`: 253 passed, 39 ignored.
- `cargo build --release`, `flutter build linux --release`, `scripts/build_web.sh`: built.

## The GPU lines

Both clients, once joined:

```
encoder: VAAPI on /dev/dri/renderD128 (Mesa Gallium driver 26.2.5-arch3.1 for AMD Radeon RX 9070 XT (radeonsi, gfx1201, ACO, DRM 3.64, 7.3.1-1-cachyos)) encodes H264
encoder: VAAPI on /dev/dri/renderD128 (Mesa Gallium driver 26.2.5-arch3.1 for AMD Radeon RX 9070 XT (radeonsi, gfx1201, ACO, DRM 3.64, 7.3.1-1-cachyos)) encodes H265
watching: shares decode on the GPU (/dev/dri/renderD128, through VAAPI)
```

The 9070 XT's node, not the iGPU's; no `no H264 from` or `no H265 from`; nothing says CPU.
Both said they play `vp9, vp8, h264, h265`.

## The runs

Setup as the brief: `a` shares an ffplay `testsrc2` window at 1920x1080 with a clock, `b`
watches through Rust, screenshots every 10 s by the desktop portal (`gnome-screenshot` is
refused on GNOME 51), delay = pattern clock minus the watcher's clock in the same shot.
The codec moves and share dialog were driven by the owner's hand.

| Run | Result | AMD | Intel / NVIDIA |
|---|---|---|---|
| **D.** H265, fast upload, twice | PASS | Dialog H265 · 11 Mbps. `starting ... H265`, `H265 in Main`, `track: publishing H265 from the GPU at 11000000 bps` with no "High profile". `b` decoding H265 on radeonsi. Picture 2.4 s and 0.53 s after Watch; delay 50–67 ms and 33–50 ms; clock moving in every shot. The rate gate reached 11 Mbps by about 10 s, 26 pictures left out at the start. No `no picture`, `stopped working`, `instead` or keyframe waits. Bottom and right edges clean | Windows NVENC: 17–50 ms behind (TESTING.md). Linux: about 0.3 s to a picture, 0.02–0.07 s behind |
| D, odd size | PASS | A window at 1315x746 from the start: published 1314x746, decoded 1314x746, edges clean. A window resized during a share stays at the size it started at, letterboxed (`resolution.rs`, by design) | not run there |
| **E.** H264 High, twice | PASS | Dialog 12 Mbps. `H264 in High`, `track: publishing H264 from the GPU, High profile at 12000000 bps`. `b` decoded H264 on radeonsi. Picture 2.7 s and 0.72 s; delay 50–67 and 33–50 ms. `no sender capability`: **0**. Codec set back to Auto with a share | same lines on both |
| **F.** H265 on 1 Mbps, 90 s | PASS | Limit (`tc` police on the laptop's LiveKit container, applied and lifted there by the owner) on before the share. Picture 4.35 s. `within` 0.59–1.18 Mbps, mostly 0.65–0.9. Left out 117 in the first 5 s (112 near 9 keyframes), then 8–38 per 5 s, about 7 more keyframes. Watcher: one `H265 frames were lost, waiting for a keyframe`, at 0.7 s. Delay: the 4 s shot missed; 9.5–30 s 17–33 ms with one 0.23 s; 30–96 s 16–67 ms with rises of 0.23, 0.43 and 2.1 s, each clearing to about 50 ms. Never stopped | Intel: under 0.05 s from 10 s. NVIDIA: under 0.25 s from 20 s. AMD settled like Intel, with rises like Intel's earlier 3.4 s |
| **G.** Moves mid-share | PASS | H265→H264 0.60 s, →VP9 0.64 s, →H265 0.21 s (watcher's picture back, by log). 360p and back to 1080p: 0.04 and 0.06 s, same track; 30 and 60 fps, same track. Nothing `stopped working`. The owner saw about 0.5 s a codec move, sizes and rates at once | Intel low power about 0.77 s; Windows NVENC about 0.25 s |
| **H.** Web viewer steps it down, three cycles | PASS | Web build in a Chrome of its own (account `cachy3`). In the call, not watching, 44 s: nothing moved. Its Watch: H264 at 12 Mbps at once with the note (drops 15:02:09, 15:06:01, 15:07:06, 15:08:06 UTC); back to H265 after it stopped (15:05:43, 15:06:58, 15:08:00, and a last one the owner saw). `b`'s picture back 0.60–0.63 s after every move. The 30 s itself is the owner's observation: when the web stopped watching is not logged | Intel: Rust 0.8 s down, 0.25 s up; NVIDIA 0.94–0.99 and 0.39–0.46 s |
| **I.** Still, then movement | PASS | A paused pattern window rather than the whole screen (the whole screen would have shared the owner's own apps). Still: 0–8 kbps, 1 picture a second. Unpaused after 20 s: 5.3 Mbps at 1 s, 8.1 at 7 s, 10.1 at 9 s (over 90%), 10.7–11.2 from 11 s; sharp | Intel 10, 10, 18 s; NVENC 10, 10, 8 s |
| **J.** Beside CS2 | PASS | Below | Below |

Encoder time at 1080p60 H265 on the pattern: send 2.3 ms, encode 0.0, deliver 0.1 ms a
picture.

### J. Beside CS2

CS2 (Vulkan, RADV) at 2560x1440 borderless on the left half, de_dust2 offline, no bots,
the owner standing still at one spot facing one way, MangoHud logging 60 s a round
(`no_display`). `a` shared the game's window at 1080p60, sound off; `b` watched with its
window behind the game. "Over 2x" is frames over twice the round's own mean frame time
uncapped, and over 16.7 ms at 120. Every round of every case:

| Case | Cap | Mean fps | p99 frame time | Over 2x | Over 16.7 ms | Share |
|---|---|---|---|---|---|---|
| No share | none, 4 rounds | 778.7 / 785.5 / 787.3 / 780.9 | 2.71–2.74 ms | 1441–1531 (2.55 ms) | 0 | — |
| No share | 120 | 120.0 | 10.11 ms | 0 | 0 | — |
| H264 High, 12 Mbps | none, 4 rounds | 760.0 / 753.1 / 754.4 / 748.8 | 2.80–2.86 ms | 1404–1434 (2.65 ms) | 0 | 60 a second |
| H264 High | 120 | 120.0 | 10.18 ms | 0 | 0 | 60 |
| H265 Main, 11 Mbps | none, 3 rounds | 757.1 / 756.5 / 754.6 | 2.82–2.83 ms | 1432–1460 (2.65 ms) | 0 | 60 |
| H265 Main | 120 | 120.0 | 10.19 ms | 0 | 0 | 60 |

The no-share case's first log (385 fps, the map still settling) was left out at the owner's
word, and its extra round kept. Uncapped means: no share 783, H264 High 754 (−3.7%),
H265 756 (−3.5%). The share's own count: 296–301 pictures a 5 s through every round in
both codecs, dipping to 271–296 once a minute where the gate leaves out 25 pictures near a
keyframe. Send time 3.6–4.9 ms a picture in H264 High; in H265 6.5–7.5 ms during the
first round, then 2.9–4.1 for the rest (not isolated). Longest send 8.1–19.0 ms.

| Beside a game | No share | H264 | H265 |
|---|---|---|---|
| Intel default encoder (glmark2) | 298 fps | 235 (−21%) | 143 (−52%), share at 50 |
| Intel low power (glmark2) | 300 | 265 (−12%) | 265 (−12%) |
| NVIDIA NVENC (glmark2) | 764 | 744 (−3%) | 736 (−4%) |
| **AMD VAAPI (CS2)** | **783** | **754 (−3.7%)** | **756 (−3.5%)**, share at 60 |

So on AMD H265 is no dearer to a game than H264, like NVENC and unlike Intel's default
encoder. Different games, so compare the shape, not the frame rates.

## Not run

- `b` decoding beside the game: its window was behind CS2, and whether its picture was off
  is not logged.
- A whole-screen share at 5120x1440, and a whole-screen H265 share beside the game (the
  game's window was shared).
- The 4 s delay point in F (that screenshot missed).
- A phone viewer, Firefox, a real slow connection (a limiter, not a queue), Windows' AMF in
  H265 or High.
- The server's functions were not copied by this run: the laptop's stack was used as it was.

## Oddities

1. **The web viewer was black at first** with the owner's own Chrome flags
   (`~/.config/chrome-flags.conf`: Vulkan ANGLE and zero-copy VAAPI video). Chrome's log said
   `Importing textures with external sampling into GL is not possible`, and 746 of 748 frames
   were dropped. Launched as `/opt/google/chrome/chrome` with its own profile and no flags, the
   picture came. Chrome's, not Rift's, but someone running those flags gets a black share.
2. **About 43 pictures a second outside the rounds.** With the game's window shared and the
   game not in front (before and after each case), the share counted 213–216 pictures a 5 s;
   with the game in front, 300. Most likely the game drawing less when not focused; not
   isolated.
3. **One 2.1 s rise in F** at 96 s, gone within about 20 s, with no keyframe wait logged then.
4. **H265's send time** was about twice its later value through the first round of that case,
   with the game's frame rate unchanged; not seen again.
5. The owner had a video playing on the right half throughout J, the same in every case, and
   saw CS2 dip under 700 fps as the video changed.
