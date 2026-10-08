# GPU encoding results — AMD on Linux

The answer to `GPU_ENCODING_TESTS.md`, run Oct 8 2026 on one AMD machine by an
agent, steps 1–3. Step 4 (the app) was not run.

**Verdict: LiveKit's VAAPI encoder.** AMD's driver makes clean H264 when FFmpeg
drives it, and the same capture and network carry VP9 perfectly, but H264 from
LiveKit's VAAPI encoder stalls the viewer every 8–25 s with no packets lost.
That is the first row of the brief's table: encode with FFmpeg's `h264_vaapi`
ourselves and hand LiveKit the frames pre-encoded, as `gpu_feed.rs` does for NVENC.

## 1. The machine

| | |
|---|---|
| GPU | AMD Radeon RX 9070 XT (Navi 48, gfx1201) at `renderD128`; a Raphael iGPU at `renderD129`, unused |
| Driver | Mesa 26.2.4 (radeonsi), libva 2.24, VA-API 1.24 |
| H264 encode | `VAEntrypointEncSlice` for Constrained Baseline, Main and High |
| Kernel, session | 7.2.9 (CachyOS), GNOME on Wayland; the bench captured an X11 window through XWayland |
| FFmpeg | 9.0.2, with `h264_vaapi` |

Mesa is far past 23.3, so `vaDeriveImage` works and the missing `vaPutImage` in
`upload_surface_yuv` is not reached here.

## 2. The driver alone, with FFmpeg

`testsrc2`, 2560x1440 at 60 fps, 120 s (7200 frames), 20 Mbps, compared frame by
frame with the original.

| Run | Decoder errors | Median PSNR | Worst frame | Outliers (8 dB under median) |
|---|---|---|---|---|
| A: NV12 upload, VBR | none | 45.1 dB | 42.6 dB | 0 |
| B: NV12 upload, CBR, IDR every 5 s | none | 44.0 dB | 42.8 dB | 0 |
| C: I420 upload, CBR | — | — | — | did not encode |

C fails on its first frame: `Failed to end picture encode issue: 6 (invalid
VASurfaceID)`. The driver cannot encode from a surface in I420 format. This is
not LiveKit's path: it creates its surfaces without asking for a format, derives
an NV12 image from them, and interleaves the I420 chroma into it while copying,
which is what A does on the CPU. So A and B stand for the driver, and the driver
is clean. No gameplay clip was at hand, so only the pattern was tried.

## 3. Rift's real path, measured

The share bench into a dev-mode LiveKit server (1.13.9, in Docker) on the same
machine, sharing an `ffplay` window of `testsrc2` at 1920x1080, 60 fps. The
window is 1080p, so every run published 1920x1080 whatever `BENCH_HEIGHT` asked.
Each run is 120 s.

| | H264, 60 fps, 20 Mbps | VP9, 60 fps, 20 Mbps | H264, 30 fps, 8 Mbps |
|---|---|---|---|
| Room | `amd-1` | `amd-2` | `amd-3` |
| Encoder | VAAPI H264 Encoder | libvpx | VAAPI H264 Encoder |
| Encoded / sent | 34.5 fps | 59.9 fps | 29.8 fps |
| Encode time | 6.74 ms/frame | 4.07 ms/frame | 6.10 ms/frame |
| Sharer CPU | 18% of one core | 80% of one core | 11% of one core |
| Sharer keyframes | 18 | 2 | 32 |
| **Viewer decoder** | FFmpeg | libvpx | FFmpeg |
| **Decoded** | 25.5 fps | 59.9 fps | 19.6 fps of 30 |
| **Freezes** | 9 | 0 | 10 |
| **Lost packets** | 0 | 0 | 0 |
| **Viewer keyframes** | 10 | 2 | 16 |
| **PLIs** | 26 | 0 | 46 |
| Received | 19.33 Mbps | 19.16 Mbps | 8.01 Mbps |

The freeze time printed as `0.00 s` in every run, including the H264 runs that
plainly stalled. The bench's freeze-duration figure does not count these stalls,
so the per-2-second samples are the measure. In both H264 runs those show the
same thing every 8–25 s: decoded fps falls to 0 for 2–6 s **while the bitrate
holds at target and nothing is lost**. Then the viewer's PLIs bring a keyframe
and it recovers. The data arrives and the decoder cannot use it. VP9 over the
same capture, server and network never dropped below 60 fps.

The lighter H264 run is worse, not better (46 PLIs against 26), so the trouble
does not come from load. Neither VAAPI nor the viewer's decoder logged an error
on the Rust side. LiveKit's VAAPI code logs through WebRTC's `RTC_LOG`, which
the bench does not show.

Not explained: at 60 fps the VAAPI encoder put out only 34.5 fps, while the same
capture fed libvpx 59.9 fps.

## What this rules in and out

- **Network and capture:** out. VP9 was flawless on both, and H264 lost no packets.
- **AMD's driver:** out for this Mesa. FFmpeg's `h264_vaapi` on the same GPU
  makes clean 1440p60 H264 in both CBR and VBR. Mesa issue 6734 (solid-colour
  frames) did not appear in 14,400 frames.
- **LiveKit's VAAPI encoder:** in. Its stream decodes for a while, becomes
  undecodable, and recovers only on a keyframe. That fits its hand-written
  SPS/PPS/slice headers or reference handling (`vaapi_h264_encoder_wrapper.cpp`)
  more than the driver underneath. Which of those it is was not isolated.

The picture itself was not seen: step 4 was not run, so whether these stalls
show as the reported freezes only, or also as the pixelation and wrong hue, is
not yet proved. The likely next step is the `gpu_feed.rs` route with FFmpeg
`h264_vaapi` and NV12 upload, run through the same bench. VP9 is the fallback
for AMD meanwhile.

## How it was run, and what differed from the brief

- The brief's commands, apart from the following:
  - The bench needed rustc ≥ 1.96 (`kstring` 2.0.5 in `Cargo.lock`). The stable
    toolchain was updated from 1.93.1 to 1.99.0, with the owner's agreement.
  - The machine has an HTTP proxy in its environment. LiveKit's Rust client
    sends `ws://127.0.0.1` through it despite `NO_PROXY`, and its signalling
    times out. The bench ran with the proxy variables unset.
  - `ffplay` was started on its own, not as a background job of the bench script,
    which killed it.
- Recordings and logs were kept on the test machine and not committed.
