# Step 2, NVIDIA half: zero-copy sharing from an NVIDIA-drawn screen — design

Oct 30 2026. Designed with the owner and approved Oct 30; built on branch `gpu-codecs`, measured
and driven in the app Oct 30–31 (`PLAN.md` step 0, `TESTING.md`). The second half of step 2
(`STEP2_LINUX.md`, which built the Intel/AMD half). What is the owner's is marked
so; the rest is the builder's call, and says so where it is a judgement.

## Why

Rift is for people who game (owner, Oct 30), and a gamer on Linux with an NVIDIA
card has the screen drawn by NVIDIA. Their share today takes the slow road even
with the new capturer: NVENC cannot take the compositor's DMA-BUF, so the stream
asks for memory buffers, the compositor reads every picture back, `share-frames`
converts it with libyuv, and `gpu-encoder` uploads it to the card again. That is
the 21–23% of a core step 0 measured (`PLAN.md`), growing with pixels a second,
and NVENC waits about 10 ms a picture in `send` on top: inside 16.7 ms at 60 fps,
more than the 8.3 ms a picture has at 120. All of it is spent while a game wants
the same CPU and GPU.

## What it must not do (owner, Oct 30)

- **The sharer's game must not lag or stutter because of the share.**
- **Watchers must not see stutter or lag.**

Either one makes the step a failure even if every picture arrives. Every anti-goal
of `STEP2_LINUX.md` holds too: no dropped, black or torn picture, no lost cursor,
no picker asked twice, and Rift still starts and shares on a machine without any
of this.

## Goals

- A Wayland share (screen or window) from a screen the NVIDIA card draws is encoded
  by NVENC with the picture never on the CPU.
- Everything a share does today still works, as listed in `STEP2_LINUX.md`
  (*Goals*): the picker and saved pick, window sound, quality changed mid-share, a
  resized, minimised or closed window, the fall back to VP9, keyframe and bitrate
  requests, the rate gate, a still screen repeated for late watchers.
- Intel and AMD keep their finished VAAPI path unchanged.

## Not in this step

- X11 shares and Windows (step 1); watching (step 3); H265 and AV1 (step 4).
- A hybrid laptop whose screen Intel draws keeps VAAPI on Intel (owner, Oct 29).
  NVENC with DMA-BUFs is for a screen NVIDIA draws.
- Keeping each imported buffer between pictures (the import cache deferred on Oct
  30, `PLAN.md` step 0): this half imports every picture, as gpu-screen-recorder,
  OBS and Sunshine do. If the measurement below falls short, that is the idea to
  try first, with care: the `media-pp` crate's notes report stale pictures from
  cached EGL images on NVIDIA and none from fresh ones (driver 595.84, about 7,000
  pictures; read Oct 30, not reproduced here).

## Success

Measured on this laptop, now set to NVIDIA-only display in the BIOS (Oct 30), the
way step 0 was (release build, `threadtop` 20 s, the moving test picture full
screen, H264 at 15 Mbit/s, one viewer):

- **CPU:** close to gpu-screen-recorder recording the same picture on the same
  screen with NVENC. gsr is measured first and its number is the bar (the
  Intel half was judged the same way: 4.5% against gsr's 3.4%, accepted Oct 30).
  Rift today, on its memory path, is measured too, so the gain is shown.
  *Builder's call:* a miss is reported to the owner with the numbers, as the
  Intel half was; the import cache is not built inside this step without the
  owner's word.
- **The game:** a GPU benchmark that reports its frame rate stands in for a game
  (there is none on this laptop). Its frame rate and frame-time spikes with no
  share, with today's path, with the new one and with gsr. The new path costs the
  benchmark no more than gsr does, and less than today's. The builder asks the
  owner before installing a benchmark, with the exact command.
- **The watcher:** at 1080p120 (this screen runs at 165 Hz; it cannot show 1440p)
  every picture the rate gate lets through reaches the viewer, and the time ffenc
  spends in `send` stays well under 8.3 ms. 1440p120 needs a 1440p screen.

## How it works

### The route (owner, Oct 30)

The owner chose the route gpu-screen-recorder and Sunshine take, over FFmpeg's
Vulkan path. Comparison put to the owner:

- **Chosen: EGL, a GL shader, CUDA.** The DMA-BUF is imported into EGL as a
  texture, one shader pass draws it into two GL textures as NV12 (Y, then UV at
  half size), CUDA reads those textures (`cuGraphicsGLRegisterImage`) and copies
  them into the CUDA frame `h264_nvenc` takes. This is what NVIDIA gamers on Linux
  already run every day through Sunshine, and it needs no new library: EGL and GL
  come with NVIDIA's driver, CUDA is already loaded for NVENC, and the CUDA–GL
  calls are in the `ffnvcodec` loader ffenc already builds with.
- **Not chosen: FFmpeg on Vulkan** (`hwmap` to Vulkan, `scale_vulkan` to NV12,
  transfer to CUDA). Less code of our own, but ffenc would need a SPIR-V compiler
  at build time (FFmpeg dropped compiling shaders at run time in July 2026) and
  Vulkan headers of 1.3.277 or newer, and no project was found running that chain
  on NVIDIA, so a fault there is ours alone to find. Measured below.

**The two routes tested side by side (Oct 30, throwaway tests).** A 1080p60 moving
picture in a real DMA-BUF on this RTX 3070 Ti, driver 610.57, into `h264_nvenc`,
with FFmpeg 9.0.1. Each test drew its own picture, about 1.3% of a core of the
figures below.

| | EGL + GL + CUDA | FFmpeg's Vulkan chain |
|---|---|---|
| CPU, whole test | 3.4–3.5% of a core | 10.7% |
| Time before NVENC | 0.6 ms a picture | 1.5 ms |
| Worst picture | 5.9 ms | 7.4 ms |
| Colours (BT.601 limited) | right | right |
| Stale pictures in 660 | none | none |
| Compressed modifiers (`e08…`) | import | refused: Vulkan does not list them |
| Same size in as out | works | fails, see below |

The chain also needs a device made with `disable_multiplane=1`, and at the same
size `scale_vulkan` hands the work to libswscale's new Vulkan path, which refused
this conversion. It takes its own shader only when both width and height change, so
1080p to 1080p, the usual share, would need a patch to FFmpeg. So the owner's choice
stands on measurement as well. These tests do not settle sync, since each drew its
own picture, nor which way up a real compositor's picture arrives: the two routes
disagreed on that here. Both are checked first on a real share (*Sync*, *Proof*).

### Reuse (owner rule, Oct 29: code other people already run, wherever it fits)

Read Oct 30 at gpu-screen-recorder `099a55b` (GPL-3.0, C, on FFmpeg like ffenc;
the leanest recorder measured on Oct 30) and Sunshine `a679b05` (GPL-3.0, C++):

- **The NVENC side** is gsr's `src/encoder/video/nvenc.c`: a CUDA device context
  for FFmpeg on gsr's own CUDA context, an NV12 CUDA frame pool, two GL textures
  (`GL_R8`, `GL_RG8`) registered with CUDA, and per picture two
  `cuMemcpy2DAsync` from the textures' arrays into the frame, then a sync. The
  textures are mapped for each picture, as Sunshine does, not kept mapped as gsr
  keeps them: drawing into a mapped resource is undefined, the map is where GL's
  work is finished for CUDA, and the spike measured no cost between the two.
- **The CUDA device** is gsr's `src/cuda.c`: the CUDA device for the render node,
  found by its PCI bus id, so CUDA and EGL are on the same card.
- **The EGL display and import** are gsr's `src/egl.c` (an EGL display on the
  render node's EGL device, `EGL_PLATFORM_DEVICE_EXT`, falling back to GBM as
  ffenc's `dmabuf_caps.c` already opens it; a surfaceless GL context) and the
  DMA-BUF import in gsr's `src/pipewire_video.c`
  (`gsr_pipewire_video_create_egl_image`, with and without modifiers).
- **The shader** is gsr's `src/color_conversion.c`: RGB to NV12 in one pass per
  plane, with the crop, the turn (its rotation matrix) and the placement in the
  target, which covers what `scale_vaapi`, `transpose_vaapi` and `pad_vaapi` do on
  the VAAPI side. The colours must match what ffenc tells viewers: BT.601
  (SMPTE 170M) limited range, as `ffenc.c` sets for every encoder. gsr's shader
  has only BT.709 matrices, so the BT.601 one is written for it (builder's
  call, found by the builder check).
- **External-only modifiers:** `dmabuf_caps.c` leaves them out for VAAPI. On
  NVIDIA the import is EGL's, and gsr samples such a buffer as an external
  texture (`GL_TEXTURE_EXTERNAL_OES`); the shader takes both, so those modifiers
  are offered on this path (builder's call).
- Sunshine's `src/platform/linux/cuda.cpp` and `graphics.cpp` are the second
  reference: where gsr and Sunshine differ, the builder notes which was taken and
  why.
- Each file brought in keeps its copyright header and says what was changed,
  as `pipewire.c` and `dmabuf_caps.c` do.

### Where it sits

Everything above `rift_ffenc_send_dmabuf` stays as built: the portal, the
PipeWire stream, the rate gate, the repeat of a still screen, the fall backs, the
Rust side. The change is below it:

```
PipeWire DMA-BUF ─▶ ffenc (gpu-encoder thread)
                    VAAPI:  hwmap ─▶ scale/transpose/pad_vaapi ─▶ h264_vaapi   (as built)
                    NVENC:  EGLImage ─▶ GL shader to NV12 ─▶ CUDA copy ─▶ h264_nvenc   (new)
```

- `rift_ffenc_send_dmabuf` and `rift_ffenc_repeat` work for NVENC as they do for
  VAAPI, with the same contract: the call returns once the GPU has copied the
  picture, so the buffer goes back to the compositor at once; the last NV12
  frame is kept for a repeat.
- The GL context and the CUDA calls live on the `gpu-encoder` thread, the one
  that calls ffenc. Nothing new runs on PipeWire's thread.
- `takes_dmabuf()` becomes true for NVENC when the screen is NVIDIA's and the
  NVENC session opened its EGL and CUDA side; otherwise NVENC takes memory as
  today.

### Which GPU encodes

The rule stays the owner's (Oct 29): encode on the GPU that draws the screen.
Today the order on Wayland is VAAPI on each render node, then NVENC, and only
VAAPI is offered DMA-BUFs. On a PC whose screen NVIDIA draws beside an Intel or
AMD chip with no screen (a desktop with an iGPU, or a laptop in discrete mode
with the iGPU still present), VAAPI would be picked and handed buffers from
another card, which fail to import and fall to memory: no worse than today, but
no gain.

*Builder's call, kept narrow because no such machine is here to prove it on
(this laptop in discrete mode shows no Intel chip at all):* NVENC goes first, and
takes DMA-BUFs, only when the NVIDIA card has a connected display and no Intel or
AMD card does (DRM connector status, as gsr picks its card). Every other machine
keeps today's order, so a hybrid laptop with a monitor on each GPU is unchanged.
The rule is a pure function over the cards found, unit-tested with made-up
cards, and `CALLS.md` says it.

### Sync

NVIDIA's driver relies on explicit sync, and today's release build syncs
implicitly: it is built on Ubuntu 24.04, whose PipeWire 1.0 headers lack the
sync timeline, so `pipewire.c`'s explicit-sync code is compiled out
(`STEP2_LINUX.md`). gsr has no explicit sync and still records cleanly on NVIDIA
under GNOME, so implicit may be enough here, but a torn or stale picture is what
the owner named as failure.

- **First task:** settle it. *Builder's call:* build ffenc against PipeWire 1.2's
  SPA headers in every build (they are headers only, and a 1.0 runtime simply
  never negotiates the meta), and check on this screen that a release-built
  library takes the explicit path with GNOME 50 on NVIDIA.
- **Without a timeline** (PipeWire 1.0, an older driver or compositor), a picture
  must still never be torn or stale. *Builder's call:* check it by forcing the
  timeline off on this screen with the moving test picture. If it tears, wait on
  the buffer's own fence before drawing: export it from the DMA-BUF
  (`DMA_BUF_IOCTL_EXPORT_SYNC_FILE`) and make the GL context wait on it
  (`EGL_ANDROID_native_fence_sync`, a wait on the GPU, not the CPU). If that
  cannot be made clean, a stream without a timeline takes memory buffers on
  NVIDIA. Accepting tears, as gsr does, is not an option (owner's anti-goal).
- **Settled Oct 30**, on an RTX 3070 Ti and GNOME 50, with `tear_check.py`'s picture
  (the whole screen flipping between two grays, 60 s each, about 3250 pictures; the
  check caught made-up tears and stale pictures first): 0 torn and 0 stale, with the
  timeline and without it, with the GPU idle and at 100% from a costly shader. So no
  fence wait was built, and a stream with no timeline stays on the GL path. Under the
  load the compositor's sync took 1.5 ms on average and 3.9 ms at worst, on PipeWire's
  thread, and the GPU wait 5 ms at worst. A shared screen and a shared window are both
  upright and not mirrored.
- **Memory buffers under a fullscreen window (found by this check, Oct 30).** While a
  fullscreen window fills the screen, GNOME sends a memory stream no picture at all,
  and one small window over it brings them back. So GNOME's direct scanout is the
  likely cause. DMA-BUFs flow throughout. A share on such a screen now opens on
  DMA-BUFs (`first_buffers`), or one begun over a fullscreen window would never learn
  its size. Seen with a fullscreen test picture, not yet a game. **Still open:** what
  stays on memory (VP9, or NVENC when the GL side does not open) gets no pictures while
  a fullscreen window fills this screen.

### Keeping the game smooth

- The share's GPU work is one small shader pass and a copy per picture, plus
  NVENC, which is its own hardware. *Builder's call:* measure the benchmark with a
  default-priority GL context first. Only if the game loses frames, try a
  lower-priority context (`EGL_IMG_context_priority`), and check that the share
  itself does not then stutter under a full GPU.
- The CPU wait per picture (`cuStreamSynchronize`, gsr's "TODO: needed?") is timed;
  it must stay well under a picture's time at 120 fps.

### Who gets it (owner, Oct 30)

On for everyone, with one switch in settings that goes back to the old path, for
Intel/AMD and NVIDIA alike. Someone whose machine misbehaves can fix it themselves.
*Builder's call:* the switch takes effect from the next share.

### When it is not used

Any refusal falls back to today's path, never to no share:

- ffenc cannot open EGL or CUDA on the card, or the GL texture will not register:
  NVENC takes memory buffers, as today.
- A modifier fails to import: dropped and renegotiated, as built for VAAPI; with
  none left, memory buffers.
- The encoder fails mid-share: the VP9 fall back, as today.
- The settings switch is set to the old path: libwebrtc's capturer, as before step 2.

## Proof

- Unit tests for the pure parts: which GPU is chosen, the shader's placement
  maths (crop, turn, letterbox) against `resolution::letterbox`.
- The ffenc bench (`native/ffenc/test.sh` style) importing a real DMA-BUF on this
  card, with the CPU per picture split as step 0 did for VAAPI.
- The live tests in `gpu_live_test.rs` on NVENC with DMA-BUFs (room test, resize,
  still screen repeat).
- Driven in the app on this laptop: whole screen and a window, 1080p60 and
  1080p120 moving picture through `threadtop`; the benchmark numbers above;
  quality changed to VP9 and back; a window resized, minimised and closed; the
  encoder made to fail; a late viewer on a still screen. Picker steps are the
  owner's to answer by hand.
- The Intel/AMD path rechecked once the laptop is back in hybrid mode (owner
  switches the BIOS), since the GPU choice changes for everyone.
- `CALLS.md`, `TESTING.md` and `PLAN.md` step 0 updated in the commits that
  change behaviour, with the measured numbers.

## Left to the builder

- The ABI change (`RIFT_FFENC_ABI` bumped) and how NVENC's open learns the render
  node (today `device` is NULL for NVENC).
- 10-bit and HDR: refused at negotiation, as on VAAPI.
- How the CUDA context and FFmpeg's CUDA device are shared (gsr hands FFmpeg its
  own context).
- Build changes: GL headers for ffenc in `native/ffenc/build.sh` and the Linux
  build's packages; licence notices if anything new ships.
