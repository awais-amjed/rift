# Step 1: zero-copy sharing on Windows — design

Nov 1 2026. The route is the owner's decision (Route C, Nov 1), made after a separate review of an
earlier draft that recommended Route A. The first milestone is built and being measured on branch
`gpu-codecs`; the rest waits on its numbers (*First milestone*). `PLAN.md` step 0 has what today's
path costs. What was not run is said plainly in *What is not known yet*.

## Why

Rift is mostly for gamers. The two failures that matter most (owner):

1. The sharer's game stutters because of the share.
2. A viewer sees stutter, lag or a wrong picture.

A share must also never crash the app, hang on stop or take the call down, and any failure on the
new path falls back to today's.

Today every picture goes GPU → CPU → GPU, while a game wants the same machine: Windows Graphics
Capture (WGC) gives a texture, libwebrtc copies it to memory, `share-frames` converts it to NV12 on
the CPU, and `gpu-encoder` uploads it again through ffenc. The goal: for an H264 share, the picture
stays on the GPU from capture to encoder.

## The route (owner, Nov 1): our own WGC capture

**Windows Graphics Capture, written in Rust with the `windows` crate, in `capture_wgc.rs`.** No
change to the LiveKit fork. It reaches Windows 10 for windows; **a whole screen on Windows 10 stays
on today's path for now** (DXGI, which draws no border, and which does not work from NVIDIA on a
hybrid laptop). Older Windows 11 gets it as well.

### The routes tested

One laptop: Lenovo Legion 82RB, i7-12700H, RTX 3070 Ti Laptop and Iris Xe, Windows 11 25H2, BIOS on
hybrid so Iris Xe draws the 1920x1080 165 Hz screen, on AC. Throwaway tests, Nov 1.

| | A: libwebrtc's texture mode | B: FFmpeg's `gfxcapture` | C: our own |
|---|---|---|---|
| Windows versions | 11 24H2 and later | Older too | Older too |
| Fork change | Yes | No | No |
| Shared window closes | 5 of 5 clean, capture only | **Crashed in 2 of 4** (`0xC0000005`), NVENC | *First milestone* |
| Game window swap, list, picker | Unchanged | Rebuild | List and picker unchanged, `SharedWindow` reused |
| New build needs | None | `avfilter`, WinRT in the MinGW DLL | None: Rust, and a C shader pass |

- **Why not A (owner):** it does not cover enough users.
- **Why not B:** the crash on the moment a shared game closes, which was not root-caused. FFmpeg's
  own source warns of one near it: "letting [`graphicscapture.dll`] get auto-freed during RoUninit
  causes crashes". Stock `scale_d3d11` also failed to create its pool on both GPUs (`E_INVALIDARG`),
  and patched failed on Intel (`0x887A0004`), and the adapter index moved while CS2 ran.

### What was read, and what came from where

Read Nov 1: OBS `libobs-winrt/winrt-capture.cpp` and `plugins/obs-nvenc/nvenc-d3d11.c` (master at
`65c320b`), FFmpeg n9.0.2 `vsrc_gfxcapture_winrt.cpp`, Sunshine `display_wgc.cpp`, `display_vram.cpp`
and its `convert_yuv420` shaders (`68f637a`).

- **Free-threaded frame pool** (`CreateFreeThreaded`), as FFmpeg, Sunshine and libwebrtc: no dispatcher
  queue or message loop. OBS's needs its graphics thread.
- **`graphicscapture.dll` kept loaded and WinRT never left**, from FFmpeg's warning above.
- **Shutdown order**, FFmpeg's: remove both events, close the session, close the pool.
- **Follow the content size** with `Recreate`, as OBS and FFmpeg do; the picture's real size is the
  content size bounded by the texture's.
- **The border and the cursor** set on the session, ignored where Windows has no such setting. No
  `RequestAccessAsync`: libwebrtc and FFmpeg do without it, and it could block.
- **NV12 passes**, Sunshine's way: one pass through an R8 view into Y, one through an R8G8 view at half
  size into UV. The matrix and four-sample far scale are `nvenc_gl.c`'s, so colours match every path.
- **No wait on the GPU.** The earlier draft planned one, for shared handles across devices. Here the
  frame pool and the encoder are on one device, so its queue keeps the order, and OBS lets a frame go
  right after queueing its copy. A check for tears stays in *How it is proven*.

## How it works

```
Today, and every fallback:
  WGC ─▶ libwebrtc maps ─▶ share-frames, libyuv ─▶ gpu-encoder, upload ─▶ NVENC

New:
  WGC, on the encoder's device ─▶ share-frames, hands on ─▶ gpu-encoder:
      shader to NV12 in FFmpeg's D3D11 frame ─▶ NVENC
```

- **One device.** `capture_wgc::run` opens a D3D11 device on the NVIDIA adapter, found by vendor and
  never by its place in the list, for the share's life. An encoder that opens meanwhile takes it
  (`share_device`), since a picture can only be read on its own device. Windows crosses between GPUs
  for us: the screen can be on Intel.
- **The list stays libwebrtc's**, so a share and its picker agree on ids; `monitor_of` turns a screen's
  id into its monitor the way libwebrtc does.
- **Threads.** The frame pool's thread takes the picture and leaves it in a one-picture mailbox, a newer
  one replacing it. `share-frames` hands it to the feed, behind the rate gate. Only `gpu-encoder` touches
  the device's context. `share-capture` watches for a stop, an ended window and a new rate.
- **Holding pictures.** The pool has 4 buffers: the mailbox, the encoder's mailbox, the one being drawn,
  and the one Windows writes. The newest is kept until a feed takes it (a first picture before any feed,
  or one the rate gate left out), then until a newer comes.
- **Still screen.** WGC sends nothing when nothing changes, and today's path repeats pictures, so
  `rift_ffenc_repeat` sends the last NV12 frame: on a viewer's keyframe request, and after a second of
  quiet (`worker.rs`).
- **Rate.** Windows is asked for half a picture's time (`MinUpdateInterval`), since a 165 Hz screen gave
  too few when asked for the whole. `Pacer` takes what arrives down to the rate on average, with slack so
  a source just above it does not beat against it.
- **Shared window.** `SharedWindow` is reused through a small trait (`Recapture`), so closed and swapped
  windows behave as today: it asks Windows directly (`window_win::closed`) and hears `Closed`.
- **Library.** `RIFT_FFENC_ABI` 9: `rift_ffenc_send_d3d11`, `rift_ffenc_takes_d3d11`, the config's
  `d3d11_device`. `d3d11_nv12.c` is built on Windows only; `avfilter` stays out.

### Which GPU encodes on a hybrid

NVENC first, as Windows does today. The Linux ruling (the GPU that draws the screen) does not bind here,
as WGC crosses GPUs. Measure Quick Sync once its input exists, and change the order only if it costs the
game less. *Proposed; the review may have a view.*

### Fallback

| What happens | Result |
|---|---|
| Switch off, VP9, or an encoder other than NVENC so far | Entirely out of the new code. Today's path |
| Whole screen on Windows 10 | Today's path |
| No NVIDIA adapter, device or session will not open | Today's path |
| Converter or encoder will not take D3D11 | NVENC on memory, so `capture_wgc` hands over to libwebrtc's capturer |
| A picture fails once | The last picture again; a passing failure must not end a share |
| Still failing after about a second, or the GPU is gone | The encoder fails, the share moves to VP9, and the capturer hands over: no second picker |

## First milestone (owner, Nov 1)

Capture into NVENC with the converter, beside CS2 and with a viewer, using the review's gate numbers. The
shared window closed at least 20 times, with no crashes allowed. **The numbers go to the owner before the
rest is built.**

**Built for it:** everything above, for NVENC.

**Proven so far (Nov 1, this laptop, test program through a real room, viewer on the same laptop):**

- **The shared window closed 20 times** during a share: 10 closed the ordinary way, 10 killed as a crashing game
  goes. 20 of 20 ended the share with exit 0, no hang, each confirmed on the new path and encoding first.
- **Colours:** four known colours in a window, decoded, within 0.5 of a level of BT.601 limited in Y, U and V.
  Today's path, the same way: within 1.0.
- **CPU, a moving test picture, no game:** whole process 7.1–8.2% of a core against 22.3% today. That picture changes
  about 62 times a second. Today's 59.7 fps at 60 includes repeats where the new path sends what changed.

**CS2, Nov 1, one session, same build with the switch on and off.** Lowest settings, 1920x1080, standing still at
one spot, game in front, H264 through NVENC at 15 Mbit/s (60 fps) and 30 Mbit/s (120 fps), rounds of 90 s, each
share condition twice, no share three times. The viewer is on the same laptop, on both paths, so its decoding is in
every figure.

| | Game fps | Lost | p99 frame | Share process, % of a core | Viewer fps |
|---|---|---|---|---|---|
| No share | 366.5–369.3 | | 4.66–4.77 ms | | |
| Today, 60 fps | 353.9–355.4 | 3.6% | 5.04–5.06 ms | 34.6–38.5 | 59.7 |
| **New, 60 fps** | **357.4–360.0** | **2.5%** | **4.83 ms** | **9.4–11.6** | **59.4–59.7** |
| Today, 120 fps | 342.3–344.1 | 6.7% | 5.35–5.41 ms | 70.1–87.1 | 109.7–114.7 |
| **New, 120 fps** | **355.1–357.5** | **3.1%** | **4.87–5.04 ms** | **5.2–7.0** | **119.8** |

- **Unexplained, and in the new path only:** one of the four new rounds (the first at 60 fps) had nine game frames of
  about 80 ms each, over the minute after that share started: six of them in the 90 s measured, and nothing like it in the
  other three new rounds. Today's rounds had single slow frames of 13.4 and 22.3 ms, no such run. Not understood, and four
  rounds cannot say how often it comes.
- **The GPU, not the CPU, is what is left.** The game's GPU time per frame goes from 1.77–1.89 ms with no share to 2.28–2.40 ms
  on the new path and 2.38–2.50 ms today. So the capture itself, which both paths share, is probably the larger part of what
  remains; not measured apart.
- **Standing still is the easy case for the encoder:** about 0.2 Mbit/s sent. A moving game has not been measured on this path.
- **Keyframes:** the viewer counts 2 freezes a round on every path, the new one too, so the once-a-minute dip follows. Not fixed here.
- **Against step 0:** today's path costs 3.6–6.7% here, as in the route tests, and not step 0's 15–20%. Still unexplained.

**Not built yet, the rest:**

- AMF and Quick Sync input.
- The settings switch shown on Windows (`HostPlatform.capturesShareOnGpu`). On this branch the share already
  obeys the existing setting, so a Windows build takes the new path by default.
- Live tests in `gpu_live_test.rs` for this path (they are Linux's so far), and `CALLS.md` and `TESTING.md`.

## How it is proven

Say what ran on what. **This laptop has no Windows 10, no older 11 and no AMD**; the desktop's RX 9070 XT is
AMF's reference if available.

- **Unit tests:** the routing (`takes_rifts_capture`) and `Pacer`, in `capture_wgc.rs`.
- **Colours:** known colours through the path, decoded and compared against BT.601.
- **Tearing:** a whole-screen flip between two grays, as `tear_check.py` did on Linux, with the GPU idle and full.
- **The D3D11 debug layer:** in a test build, `RIFT_D3D11_DEBUG=1` makes the share's device with it, and the
  capture thread logs what it stored as it exits (`capture: debug layer: … | errors …`). Needs Windows's
  Graphics Tools: without them the device cannot be made, which the share meets as any device failure, on today's
  path (by the code; not tried).
- **CS2, same session, same build, switch on and off:** with a viewer, 1080p60 and 1080p120. Fps, p99, freezes,
  CPU per thread, `send` time, pictures reaching the viewer. Viewer on the same laptop is stated.
- **In the app:** screen and window; quality to VP9 and back; window resized, minimised, closed; game closed
  mid-share; a game that swaps its window; driver reset; Quit mid-share; a late viewer on a still screen; the
  switch off.

## What is not known yet

- Why step 0 (15–20% of the frame rate) and the route tests (4–7%) disagree about today's path. The session and
  the team and weapon at the spot differed. Unexplained.
- What the 80 ms game frames in one new-path round were (*First milestone*).
- The cost in a moving game, with a viewer on another machine.
- Whether a picture can tear on one device with the game at full GPU.
- Whether Quick Sync costs the game less.
- Windows 10, older 11, AMD and older NVIDIA cards: none run. A GTX 1060 and a Windows 10 machine both crashed in
  NVENC or ffenc before, so the fallback matters there.
