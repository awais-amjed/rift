# Step 3 on AMD: watching a share decoded on a Radeon

Nov 3 2026, the owner's desktop, branch `gpu-codecs` at `0907de68`, then `b7773c4c`. The
watcher's GPU decode path (`STEP3_PLAN.md`, `CALLS.md`, *Watching a share through Rust*) had
run on an Intel iGPU (Iris Xe, VAAPI) and an NVIDIA laptop (NVDEC), never on AMD. The
question was whether the stream is smooth and whether watching makes the watcher's own
game stutter.

**Verdict: it works on AMD, and costs less than the call's path.** H264 and VP9 decoded on
the RX 9070 XT through VAAPI with the right colours, at every size sent, through resizes,
minimising, Stop watching and rejoining. A watcher's whole process went from 54–57% of a
core to 32–34% for H264 at 53 pictures a second, and from 54–58% to 41–42% for VP9 at 60.
Watching through Rust while playing CS2 uncapped added **0.10 ms** to a game frame
(the call's path, 0.16 ms; the sharing gate was 0.2 ms), and no frame went over 16.7 ms in
any case. VP8, which AMD's VCN cannot decode, fell back to the call's connection as
designed. One test change came of it (*Found*, 1). The 5120x1440 whole-screen share was not
run (*Not run*).

## The machine

| | |
|---|---|
| CPU | AMD Ryzen 9 7950X (16 cores), 58 GB RAM |
| GPU | AMD Radeon RX 9070 XT (gfx1201, RDNA4), `/dev/dri/renderD128`, draws the screen |
| Second GPU | the Ryzen's iGPU (Raphael), `/dev/dri/renderD129`, no display |
| Screen | one, 5120x1440 at 240 Hz |
| System | CachyOS, kernel 7.3.1-1-cachyos |
| Desktop | GNOME Shell 51.1, Mutter 51.1, Wayland |
| Graphics | Mesa 26.2.5 (radeonsi for VAAPI and GL, RADV for the game), libva 2.24.1 |
| Flutter | 3.47.7, the Linux release build |

`vainfo` on renderD128, decode (`VAEntrypointVLD`) profiles: H264 Constrained Baseline,
Main and High; HEVC Main and Main10; JPEG Baseline; VP9 Profile 0 and 2; AV1 Profile 0
and 2. **No VP8.**

The sharer was Dave on the laptop (Rift Test, the laptop's stack with the watch functions),
encoding H264 on its Intel iGPU through VAAPI, or VP8 and VP9 through libwebrtc. The
watcher was the owner's account on this desktop (`RIFT_PROFILE=amd`).

## The decoder's device and its pictures

- **The device:** every run, the live tests and the app, logged
  `watching: shares decode on the GPU (/dev/dri/renderD128, through VAAPI)`. That is the
  RX 9070 XT, which draws the screen. The iGPU was never picked.
- **The export:** ffdec exported each picture as two layers of one DMA-BUF: Y as `R8` and UV
  as `GR88` at an offset, both with AMD's tiled modifier `0x0200000000082305`. Never one
  combined layer. Seen in a scratch copy of `test_ffdec` that printed each layer.
- **The import:** EGL imported both layers. `test_ffdec` gave back its four colours at
  1920x1080 (30 pictures), and the same scratch copy did so at 2560x1440.
- **5120x1440 not tested this way:** the scratch copy could not make a 5120x1440 H264
  stream, because AMD's VAAPI H264 encoder refused to open at that width (`Invalid
  argument`).

## The tests

- **The library:** `native/ffenc/build.sh`, then `test.sh`, passed:
  - `test_dmabuf`: the bars black, 65 packets;
  - `test_ffdec`: 30 pictures decoded on the GPU and drawn from their DMA-BUFs;
  - `test_ffdec cuda` and the NVENC tests reported a skip (no CUDA here).
- **Unit tests:** `cargo test --release` passed, 210 tests.
- **Live tests** against a local `livekit-server --dev` (1.13.7), each run on its own:

| Test | Outcome |
|---|---|
| `live_watch_` (CPU decode, the baseline) | passed, 2 tests |
| `live_watched_sound` (a null sink, its monitor recorded) | passed. −15.2 dBFS in each ear in turn, as sent; silent at volume 0; −21.3 at half (6 dB down); nothing once unwatched |
| `live_gpu_watch` before the change | **failed at VP8:** `the GPU cannot decode this Vp8`, then no picture (*Found*, 1) |
| `live_gpu_watch` after it | passed. VP8 lacking in the driver, so lost with that reason and nothing drawn; VP9 90 pictures in 3 s, H264 90–91, all at 640x360 |
| `live_share_is_decoded_by_a_viewer_then_stops_cleanly` | passed, with `XDG_SESSION_TYPE=x11` as its module doc says (without it the portal waits for a click) |

## In the app

Release build. The watcher on this desktop, the sharer Dave on the laptop, both on Rift
Test. The owner drove both and watched with the stream's stats open.

- **The first Watch from the sidebar** (joining and watching in one press) showed the
  picture at once (the 0907de68 fix).
- **The colours:**
  - right on ffplay's `testsrc2` bars in H264 and VP9: no wrong hue, blacks neither
    washed out nor crushed, no green or pink frames, the edges clean;
  - over H264 at 120 fps they looked wrong, but that was the sender (below), and the
    call's path showed the same.
- **Formats:**
  - **H264:**
    - a whole-screen share, 1920x1080 at 53–55 a second;
    - a window share, 1304x894 and 1376x780;
    - at 120 fps the laptop sent only 60–64 a second at 0.5–2 Mbit/s (below).
  - **VP9:** whole screen at 60 a second, and at **120 a second through Rust**, 13.7
    Mbit/s.
  - **1440p:** not run. The laptop's screen is 1920x1080.
- **VP8:**
  - The log showed:
    1. FFmpeg's `No support for codec vp8`;
    2. `watching: not decoding on the GPU: the GPU cannot decode this Vp8`;
    3. the watch connection closed.
  - The picture then came through the call's connection, as designed.
  - The fallback held for the rest of the call: the next share, VP9, came through the call
    too, until the app was restarted.
- **Resizing** the shared ffplay window: the picture's shape followed each resize, the
  owner saw. The log, though, kept one size per share, where on the Iris Xe each new size
  was logged (not explained).
- **Minimising and restoring:** `pictures off`, then `pictures on` 3.1 s later at the
  restore, and the picture was back.
- **Stop watching and Watch again:** the watch connection closed, and a new one opened.
- **Leaving and rejoining:** the picture came back each time.
- **A late viewer** (the share running 10 s or more before Watch): the first picture came
  0.34–0.99 s after the watch connection received the share, over five watches, and
  within a second of the press to the owner's eye. On Intel and NVIDIA it was about 3 s.
- **The sound:** a song from another window on the laptop played. The stream's volume
  slider, mute and unmute worked.
- **Nothing fell back,** apart from VP8. The server-side message
  (`the server does not mint watch connections`) never appeared.

The 120 fps H264 share was the sender's doing:
- **What the laptop sent:** the share was set to 1080p at 120 fps, but the laptop sent 60–64
  pictures a second at 0.5–2 Mbit/s.
- **What it looked like:** blocky, which looked like wrong colours. The call's path showed
  the same.
- **Where it was encoded:** Dave's log on the laptop shows H264 encoded through VAAPI on its
  Intel iGPU (hybrid mode). A RustDesk session was also sending from the laptop at the time.
- **At 60 fps** the same share ran at 13–14 Mbit/s and looked right.

## The cost

The watcher's whole process, from `/proc` per thread, 3 × 20 s per case, release build.
Dave shared the whole 1920x1080 screen with ffplay's `testsrc2` full screen; the watcher
had the stream large with the stats open. `RIFT_WATCH_DECODE=cpu` keeps the Rust
connection and decodes with libwebrtc; `RIFT_WATCH_PATH=call` is the old path.

| Watcher, whole process | Rust, GPU decode | Rust, CPU decode | The call's path |
|---|---|---|---|
| H264, 53 a second, 13–14 Mbit/s | **32–34%** of a core | 49–51% | 54–57% |
| VP9, 60 a second, 10.3 Mbit/s | **41–42%** | 48–52% | 54–58% |
| VP9, 120 a second, 13.7 Mbit/s | 37–41% | not run | not run |

- **What decoding on the GPU removes:**
  - libwebrtc's decoder thread (`VideoDecoderQueue`): 10% of a core for H264 and 7% for
    VP9 on either CPU path;
  - about 5–6 points of the raster thread: 8–10% on the call's path, 2–4% through Rust.
- **Rust's connection with CPU decoding** keeps the decoder but loses the call's
  conversion and upload. Its raster thread is 4–5%.
- **A thread in every case:** `webrtc_audio_module`, the call's own audio, took 14–19% of
  a core whether watching or not. So the whole-process figures carry it.
- **What is left:** the main thread is 7–14% and the raster thread 2–4% on the Rust path,
  well under NVIDIA's 12–17% each. The window here redraws only part of a 5120-wide screen
  at the picture's rate.

An earlier H264 pass on a changing screen (2.6 and 13.9 Mbit/s in different rounds) gave
35–39% through Rust, 47–52% through the call and 48–50% decoding on the CPU. It was redone
on the fixed pattern above.

## The watcher's game

CS2 at 2560x1440 in a borderless window on half the ultrawide, with the Rift window
watching Dave's 1920x1080 H264 share on the other half. The game was Dust II offline, in
warmup with no bots, standing still at one spot. Each round was 60 s of MangoHud frame
times (`log_duration=60`, overlay off). The stream held 53 a second in both watching
cases, as sent, with no stutter the owner could see.

| Uncapped, 60 s each | Rounds | Mean fps | Mean frame time | p99 | Worst | Over 16.7 ms |
|---|---|---|---|---|---|---|
| Not watching | 3 | 766–769 | 1.300–1.305 ms | 2.75–2.76 ms | 4.6–10.6 ms | 0 |
| Watching through Rust | 3 | 709–712 | 1.405–1.411 ms | 3.07–3.12 ms | 4.9–5.3 ms | 0 |
| Watching through the call | 2 | 681–693 | 1.444–1.469 ms | 3.35–3.40 ms | 6.6–9.0 ms | 0 |

- **Through Rust:** 0.10 ms added to a game frame.
- **Through the call:** 0.16 ms.
- **The count asked for** (frames over twice the target) has no target uncapped. So it is
  given as frames over 16.7 ms, twice a 120 fps frame: none in any case.
- **Rounds lost:** one round each of *not watching* and *through the call* left no log.
  Shift+F2 toggles MangoHud's logging, so a second press stops it. The missing
  not-watching round was made up later, with the call's build running but not watching.

Capped at 120 (`fps_max 120`), one round not watching and one watching through Rust
held 120.0 fps. Their p99 was 10.1 and 10.5 ms, the worst 11.1 and 11.7 ms, and no frame
went over 16.7 ms. At about 700 fps uncapped, a 120 cap leaves the GPU mostly idle, so
these cannot show a cost (the owner's call). The other capped rounds were not run.

## Found

1. **`live_gpu_watch` failed at VP8 on AMD** (fixed in the test, `b7773c4c`).
   - **Why it failed:** the test looped over VP8, VP9 and H264 and expected each to decode
     on the GPU. AMD's VCN has no VP8 decoder, so VP8 lost the watch connection with
     `the GPU cannot decode this Vp8`. That is the product's right answer, and the test's
     wrong expectation.
   - **The change:** the test now asks libva which codecs the GPU decodes (`Gpu::decodes`,
     test-only, `VAEntrypointVLD` for each codec's profiles). A codec the driver lacks
     must lose the watch connection with that reason and draw nothing; the others must
     decode as before. The reasons the connection was lost for are kept for the tests
     (`session::lost_reasons`), since there is no app to tell.
   - **Through CUDA nothing is asked,** and every codec must decode, as before.
   - **Checked both ways:** made to say VP9 was lacking, the test failed with
     `VP9, which the driver lacks: the watch connection lost with "the GPU cannot decode
     this Vp9"`.
   - **On the way:** libva's AMD driver would not initialise on a render node opened
     read-only, so the probe opens it read-write.
2. **Building:** Cargokit runs `arch`, which this machine does not have, so
   `flutter build linux` failed with `ProcessException: … Command: arch`. The build here
   used a shim on `PATH` that runs `uname -m`. Nothing in the repository was changed.

## Not run

- **A 5120x1440 whole-screen share.** It needs a sharer on this desktop, and so a second
  account. The decoder was not tried at that size either (above).
- **1440p shares,** because the sharer's screen is 1920x1080.
- **H264 at 120 a second through Rust:** the sender sent 60–64 (above).
- **The capped game rounds** beyond one each, and every case at 120 fps.
- **Freezes over 50 ms** in the stream were not measured, only judged by eye: none seen.
  Nothing here records the gaps between pictures without a change to the code.
- **AV1 and HEVC,** which the GPU decodes but Rift does not send.
