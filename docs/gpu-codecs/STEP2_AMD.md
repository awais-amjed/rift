# Step 2 on AMD: Rift's GPU share path on a Radeon under Wayland

Nov 2 2026, the owner's desktop, branch `gpu-codecs` at `601fa6a8`. The GPU share path
(`STEP2_LINUX.md`) had been run only on an Intel iGPU (Iris Xe) and an NVIDIA laptop.
The question was whether sharing makes a game stutter or lose frames on AMD, and whether
the viewer sees a smooth stream.

**Verdict: it passes.** A switch-on share of the whole screen added **0.019 ms** to an
uncapped CS2 frame (the limit is 0.2 ms). With the switch off it added 0.168 ms. No capped
frame went over twice its target in any case, and the viewer held 60 fps with no freeze.
Two faults were found outside the measured path: green letterbox bars on AMD (since fixed and
rerun here), and LiveKit's own VAAPI encoder crashing in one live test's control case. Both
are under *Found*.

## The machine

| | |
|---|---|
| CPU | AMD Ryzen 9 7950X (16 cores), 58 GB RAM |
| GPU | AMD Radeon RX 9070 XT (gfx1201, RDNA4), `/dev/dri/renderD128`, draws the screen |
| Second GPU | the Ryzen's iGPU (Raphael, `raphael_mendocino`), `/dev/dri/renderD129`, no display |
| Screen | one, 5120x1440 at 240 Hz |
| System | CachyOS, kernel 7.3.0-5-cachyos |
| Desktop | GNOME Shell 51.1, Mutter 51.1, Wayland; xdg-desktop-portal 1.22.1, -gnome 51.0 |
| Graphics | Mesa 26.2.5 (radeonsi for VAAPI, RADV for the game), libva 2.24.1 |
| PipeWire | 1.6.10 |
| Toolchain | clang 23.1.4, coreutils 9.12 |

The screen is 32:9, so "1440p" in the share dialog means 5120x1440 (`target_size` keeps the
shape). A 1440p60 share went out at 23 Mbit/s, and 1440p120 at 34.

## The encoder's device

Every run, the live tests and the app alike, opened **VAAPI on renderD128, the RX 9070 XT**
(`encoder: VAAPI on /dev/dri/renderD128 (… AMD Radeon RX 9070 XT …)`). The iGPU's node is
second in order and was never picked. The compositor's DMA-BUFs came as BGRx with AMD's
tiled modifier `0x200000000082305`, explicitly synced, and imported with no refusal.
`test_dmabuf` also passes on the iGPU (modifier `0x200000000401b03`), so a screen drawn
there would import too.

## Build and unit tests

| | |
|---|---|
| `native/ffenc/test.sh` | passes: geometry ok, `test_dmabuf` 65 packets on renderD128 (and on renderD129 with `RIFT_RENDER_NODE`); `test_nvenc_dmabuf` skipped (no NVIDIA) |
| `cargo test --release` | 188 passed, 0 failed, 26 ignored |
| `flutter build linux --release` | built, but needed two changes on this machine (*Found*, 3 and 4) |

The bundle's `librust_lib_rift.so` was checked against the fresh
`cargo build --release --target x86_64-unknown-linux-gnu` by hash. They were the same.

## Live tests

A local `livekit-server --dev` (1.13.7, the binary already on the machine) on 127.0.0.1:7880.
The screen was picked once by hand for the portal token. Each test ran in its own process
with something full screen and moving.

| Test | Result |
|---|---|
| `live_gpu_encodes_the_stream`, 30 s, `testsrc2` | **1780 pictures in, 1780 frames out, 0 refused imports**. `send` 1.8–2.6 ms a picture at 1280x720; the wait on the compositor's sync 136 µs on average and 463 µs at worst |
| `live_gpu_stream_moves_to_memory_and_back`, tear picture | passes: (GPU, memory) pictures (298, 0) (0, 260) (297, 0), 855 frames, 0 refused. `tear_check.py`: **0 torn, 0 stale** over 855 pictures |
| `live_gpu_share_resizes_rejoins_and_falls_back` | passes. 3840x1080 at 91 frames in 3 s, resized to 2560x720, **a late viewer's picture 267 ms after joining**, the failing encoder handed to VP9 without the share ending, and VP9 with no GPU |
| `live_gpu_h264_is_seen_with_the_key_and_by_nobody_else` | **gpu and gpu baseline pass**: 236 and 217 frames seen with the key, 0 without it, 0 with the wrong one. The **software** case aborts every time, in LiveKit's encoder, not Rift's (*Found*, 2) |
| `live_gpu_switch_keeps_nvenc_off_its_gl_side` | not run (NVIDIA only) |

Unlike on the NVIDIA laptop, the memory phase got pictures (260 in 5 s) with a window full
screen. That screen gave a memory stream none.

**The picture.** `live_gpu_encodes_the_stream` was run again for 10 s with `RIFT_DUMP_H264`
over `testsrc2`. That gave 598 frames, Constrained Baseline, signalled BT.601 limited range.
- **Colour:** the colour bars match the source within 4 levels a channel, with no hue shift.
- **No solid frames:** none of the 598 is a solid colour (Mesa issue 6734), and the lowest
  spread in any frame is 61 levels.
- **No faults:** no tearing, no blocks.
- **The bars round it:** the encoder's letterbox around the 32:9 screen was **green**
  (*Found*, 1). It has been black since the fix in *Found*, 1.

`tear_check.py` was never committed from the laptop, so it was rebuilt from the plan's
description (`STEP2_NVIDIA_PLAN.md`, task 5), untracked in `scripts/perf/`. It now finds the
picture in each frame, so letterbox and pillarbox bars are left out. On made-up dumps it
reported 0/0 on the clean one, 18 torn on a torn one, and 179 stale on a reversed one.

## The app

A release build of the branch, signed in as the owner, sharing the whole screen into a call
on the owner's server. A second device watched it. The moving picture was `testsrc2` full
screen. Each share was measured with `threadtop` for 20 s.

| Share | Capture | Encoder pictures | The share's threads | `send` |
|---|---|---|---|---|
| 1440p60, switch on | Rift's stream, DMA-BUF | 297 per 5 s (59.4 fps) | **2.5% of a core** | 7.6 ms |
| 1440p120, switch on | Rift's stream, DMA-BUF | 488 per 5 s (98 fps) | **2.7%** | 5.8 ms |
| 1440p60, switch off | libwebrtc's capturer | 298 per 5 s | **74%** | 8.8 ms |
| 1440p120, switch off | libwebrtc's capturer | 600 per 5 s | **102%** | 5.3 ms |

The share's threads are:
- **Switch on:** `gpu-encoder`, `rift-pipewire`, `share-frames` and `VideoEncoderQue`.
- **Switch off:** `share-frames`, `pipewire-main-l`, `gpu-encoder` and `VideoEncoderQue`.

With the switch off, at 60 fps, `share-frames` took 39.8% and `pipewire-main-l` 26.7%.
At 120 they took 75% and 14%. The GPU's busy share for the whole card was 9% during the
switch-on 1440p60 share.

- **Viewer:** smooth at 1440p60, and at 60 fps through every game round, with no freezes or
  gaps.
- **A late viewer** (stop watching, watch again) waited about **3 s** for a picture, the same
  as on other machines. This is the app viewer starting a stream; `TESTING.md` measured the
  same 3 s on Intel.
- **Asked for 120:** the switch-on share sent about 98 fps. `rift-pipewire` woke about 98
  times a second, so GNOME sent that many pictures; the encoder had room (5.8 ms a picture).
  This is GNOME sending only whole refreshes under the cap (`CALLS.md`), here on a 240 Hz
  screen.
- **Asked for 120, switch off:** libwebrtc's capturer reached 120 at the encoder. That
  capturer repeats its last picture on every tick, so not all of those 120 are new pictures.
- **No viewer frame rate was read at 120**, and the 120 shares were not compared by eye.

## Game cost (the gate)

CS2 on an offline map with no bots, rounds kept from ending, and the player standing at one
spot looking the same way. Each round was 60 s of MangoHud frame times (`log_duration=60`).
In every round with a share, the whole screen was shared at 1440p60 with the second device
watching. Each share's capture kind was read from Rift's log and matched to its round by
time. One round was played with the wrong switch setting; it was found that way and
discarded. One more was discarded at the start, by the owner.

**Uncapped (`fps_max 0`, GPU-limited), 3 rounds each**, in the order none, off, on, off,
none, none, off, on, on:

| Share | Mean frame time, each round | Mean | Added | fps |
|---|---|---|---|---|
| none | 1.686, 1.688, 1.688 ms | 1.687 ms | — | 593 |
| **switch on** | 1.702, 1.705, 1.711 ms | **1.706 ms** | **+0.019 ms** | 586 |
| switch off | 1.853, 1.856, 1.857 ms | 1.855 ms | +0.168 ms | 539 |

| Share | p99 | p99.9 | Worst | Over 2× the median |
|---|---|---|---|---|
| none | 2.82–2.89 ms | 3.70–4.41 ms | 6.5 ms | 69–122 a round |
| switch on | 2.89–2.90 ms | 3.71–4.09 ms | 6.7 ms | 85–92 |
| switch off | 3.34–3.44 ms | 4.25–4.50 ms | 10.7 ms | 239–375 |

The limit was 0.2 ms added per game frame. **The switch-on share added 0.019 ms**, about 1%
of the frame rate. On the NVIDIA laptop it added 0.22–0.26 ms. With the switch off, the
share cost 9% of the frame rate. In the last switch-on round the owner turned the view a
little; that round's 1.711 ms sits with the other two.

**Capped, 1 round each** (the owner chose one round per state for the capped caps; three
were asked for):

| Cap | Share | fps | Mean | p99 | p99.9 | Worst | Over 2× target | Over 16.7 ms |
|---|---|---|---|---|---|---|---|---|
| 60 | none | 64.0 | 15.63 ms | 16.42 | 17.12 | 18.6 ms | 0 | 13 |
| 60 | off | 64.0 | 15.63 ms | 17.18 | 19.07 | 19.6 ms | 0 | 65 |
| 60 | on | 64.0 | 15.63 ms | 16.40 | 16.99 | 18.2 ms | 0 | 6 |
| 120 | none | 120.0 | 8.33 ms | 9.97 | 11.38 | 13.1 ms | 0 | 0 |
| 120 | off | 120.0 | 8.33 ms | 10.37 | 11.62 | 12.5 ms | 0 | 0 |
| 120 | on | 120.0 | 8.33 ms | 10.09 | 10.60 | 11.9 ms | 0 | 0 |

- **What `fps_max 60` gives:** CS2's 60 cap runs at 64 fps, 15.6 ms a frame. So a frame just
  past 16.7 ms is the game's own jitter, and it shows with no share too.
- **No frame went over 50 ms** in any of the 15 rounds.

**A 120 fps share while playing, 1 round.** Uncapped, the owner moving around the map, and
the whole screen shared at 1440p120 (34 Mbit/s) with the switch on and the second device
watching. The player was moving here and still in the rounds above, so this is a check, not
a pair: there was no moving round without a share.

| | This round | Switch-on rounds above (60 fps share, still) | No share (still) |
|---|---|---|---|
| fps | 586.4 | 584.4–587.4 | 592.4–593.2 |
| Mean frame time | 1.705 ms | 1.702–1.711 ms | 1.686–1.688 ms |
| MangoHud 1% / 0.1% low | 329.5 / 239.1 fps | 344.9–345.6 / 244.4–268.8 | 345.9–354.1 / 224.6–266.1 |
| p99 / p99.9 | 3.03 / 4.15 ms | 2.89–2.90 / 3.71–4.09 ms | 2.82–2.89 / 3.70–4.41 ms |
| Worst frame | 6.5 ms | 6.0–6.7 ms | 6.1–6.5 ms |

- **What the game paid:** the 120 fps share cost the same as the 60 fps one, about 0.02 ms a
  frame. No frame went over 16.7 ms. The lower 1% low fits a moving player.
- **What the encoder sent:** 552–576 pictures in each 5 s, **110–115 fps**, at 4.8–6.1 ms a
  picture (8.3 ms at worst).
  - That is more than over the test picture (98). Behind an uncapped game GNOME hands over
    more of its 240 Hz refreshes, as `CALLS.md` found on NVIDIA.
  - The rate gate left out 22 pictures in one 5 s window, 0–1 in the others, and 10 within
    a second of the first keyframe.
  - The log had no warning or error in the round.
- **What the viewer saw:** the owner watched it stay **above 110 fps**.

## Found

1. **Green bars round a letterboxed GPU picture on AMD.**
   - **What:** `pad_vaapi … color=black` leaves the bars green on radeonsi (RGB 0,136,0, an
     all-zero NV12). The cause is that Mesa ignores `output_background_color`.
   - **Shown outside Rift:** the system's own ffmpeg does the same on both GPUs here (an
     upload, then `pad_vaapi`, then a download). So it is Mesa's, not Rift's; Intel's driver
     honours the colour.
   - **Whole-screen shares are not affected:** they keep the screen's shape and are never
     padded.
   - **What is affected:** on any AMD GPU, a window resized mid-share would be letterboxed
     with green bars in place of black. The live tests show it too, since they encode a
     fixed 1280x720.
   - **Fix (Nov 2, built on the laptop, then run on this AMD desktop the same day):** `dmabuf.c` paints each
     surface of the pad's pool black, whole, the first time it comes out, then draws the
     picture onto it again (the pool hands the same surface back). Painting only the bars
     after the picture would be cheaper, but Mesa before 25 writes a whole surface whatever
     rectangle `vaPutImage` is given, which would wipe the picture.
   - **Test for it:** `test_dmabuf.c` encodes 24 placed pictures, pillarboxed then
     letterboxed, decodes them with the system's ffmpeg, and checks in every frame that the
     bars are black (Y 16, UV 128, within 6) and the picture is still there.
   - **Run on the RX 9070 XT (Nov 2, Mesa 26.2.5):**
     - **With the fix:** `native/ffenc/test.sh` passes: `bars: black round 24 placed
       pictures`, and the rest as before (65 packets).
     - **Without it:** the same test against the old `dmabuf.c` (a worktree of f2473ce8 with
       the new `test_dmabuf.c`) fails in all 24 frames. Both bars of every frame read
       `Y 0 U 0 V 0, not black`, and no frame lost its picture. So the test catches the fault,
       and the picture was never the problem.
     - **Live:** `live_gpu_encodes_the_stream` was run with `RIFT_SHARE_SECONDS=10` over
       `testsrc2`, with the 5120x1440 screen letterboxed into 1280x720. It sent 594 pictures
       and got 594 frames out, with 0 refused. In the decoded dump:
       - The bars read Y 15–17 and UV 126–130 in all 594 frames. The dump before the fix read
         Y 0–1 and UV 0–2.
       - The picture's mean Y/U/V is 70.7/127.6/127.2, against 70.6/127.7/127.3 before.
       - No frame is solid.
2. **LiveKit's own VAAPI H264 encoder aborts on this GPU.**
   - **What:** in the **software** case of `live_gpu_h264_is_seen_with_the_key_and_by_nobody_else`,
     glibc reports `*** buffer overflow detected ***` inside `radeonsi_drv_video.so`, from
     `vaRenderPicture` called by `livekit_ffi::VaapiH264EncoderWrapper::Encode`. It happens
     every time (it was rerun alone with `GPU_LIVE_ONLY=software`).
   - **The app never reaches it:** a share's H264 comes from Rift's own encoder or goes out as
     VP9 (`session.rs`, "H264 comes from the GPU or not at all"). Only the test's control case
     uses this encoder.
   - **Proposed:** let that case skip, or use OpenH264, where LiveKit would pick VAAPI on AMD.
     `CALLS.md` already records this encoder stalling on the same GPU (Oct 9).
3. **Cargokit needs `arch`, which this machine lacks.**
   - **What:** CachyOS's coreutils 9.12 ships without `arch` (coreutils installs it only on
     request), so `flutter build linux` stopped at Cargokit's target check.
   - **Workaround used:** an `arch` that runs `uname -m`, on the build's PATH only.
   - **Proposed:** `rust_builder/cargokit/build_tool/lib/src/target.dart` should call
     `uname -m`, which gives the same answer everywhere.
4. **clang 23 stops `flutter_webrtc`'s plugin.**
   - **What:** clang 23 warns `-Wunused-but-set-global` on `g_host_messenger` in
     `flutter_common.cc`, and the plugin builds with `-Werror`.
   - **Workaround used:** `CXXFLAGS=-Wno-error=unused-but-set-global`.
   - **Proposed:** the same flag in `linux/CMakeLists.txt`'s standard settings, or a fix
     upstream in the plugin.
5. **The noise filter on a real-time thread (seen, not this branch's).** `webrtc_audio_mo`
   took 33–35% of a core at SCHED_FIFO during every share. This is the DPDFNet filter on
   libwebrtc's capture thread, which the owner's `audio` group lets run real-time. It
   matches `scripts/perf/results/amd-linux-2026-10-25.md`; branch `perf-testing` moves the
   filter off that thread.

## Not run

- **Sharing a window** in the app: so no resize, minimise or close, and no window letterbox
  seen live.
- **Quality changed mid-share.**
- **A viewer outside the LAN.**
- **A web viewer.**
- **The viewer's frame rate at 120 fps over the test picture**, and no comparison by eye
  between the two 120 shares. Under the game the viewer's frame rate was read: above 110.
- **The share's CPU during the game rounds** (it was measured over the test picture instead).
- **Three rounds per state at the 60 and 120 caps** (one each, the owner's choice).
- **A moving player with no share,** to pair with the moving round at 120.
- **A switch-off share at 120 fps under the game.**
- **`live_gpu_switch_keeps_nvenc_off_its_gl_side`** (NVIDIA only).
