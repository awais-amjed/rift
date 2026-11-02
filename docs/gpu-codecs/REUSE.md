# GPU encoding and decoding — what we can reuse

Oct 29 2026. Asked by the owner: what already exists, in our own code and in open
source projects, that the plan (`PLAN.md`) can use as is or with small changes.
Licences were read from each repository on Oct 29 (GitHub's licence field, and the
file headers where marked). Nothing here has been built or run.

## The licence rule

Rift's client is GPL-3.0. Code can come in, with its notice, when it is under
GPL-3.0, GPL-2.0-or-later, LGPL-2.1-or-later, MIT, BSD or Apache-2.0. Code with no
licence is all rights reserved and can only be read. Closed SDKs and NVIDIA's
sample code cannot ship in the client.

| Project | Licence (checked Oct 29) | Can we take code? |
|---|---|---|
| OBS Studio | GPL-2.0-or-later (file headers); `obs-qsv11` dual BSD/GPLv2 | Yes |
| Moonlight (moonlight-qt) | GPL-3.0 | Yes |
| Sunshine | GPL-3.0 | Yes |
| FFmpeg 9.0.2 (our ffenc) | LGPL-2.1-or-later as we build it | Already ours |
| media_kit | MIT | Yes |
| LiveKit rust-sdks (our fork's base) | Apache-2.0 | Already ours |
| Shiguredo sora-cpp-sdk | Apache-2.0 | Yes |
| RustDesk `hwcodec`, `flutter_gpu_texture_renderer` | none (`hwcodec` has no licence; the renderer's LICENSE says "TODO") | No, read only |
| fvp | BSD-3 plugin, but its engine libmdk is closed and keyed | No |
| NVIDIA Video Codec SDK samples (`NvDecoder`, `NvEncoder`) | NVIDIA's own licence | No |
| Unity `com.unity.webrtc` | not stated on GitHub; its codecs are built on NVIDIA's samples | No |

So the NVIDIA H264/H265 decoders in our LiveKit fork (`webrtc-sys/src/nvidia/`,
headers say "refer to the NVIDIA end user license agreement") stay out, as
`RESEARCH.md` already says.

## Step 1: zero-copy sharing on Windows

**Usable as is: FFmpeg's own capture, already in our FFmpeg 9.0.2.** ffenc is built
with `--disable-avfilter` today; turning on a few filters gives a whole GPU path:

- `gfxcapture`: Windows.Graphics.Capture into D3D11 frames. It takes a window or
  screen Rift picked (`hwnd`, `hmonitor`), and has `capture_cursor`,
  `capture_border` / `display_border`, crop and `max_framerate` options.
- `ddagrab`: DXGI duplication into D3D11 frames, for Windows 10 screens, where
  Rift already uses DXGI to avoid WGC's border.
- `scale_d3d11`: scale and convert to NV12 on the GPU.
- Encoders that take those frames: `h264_nvenc` and `h264_amf` take D3D11 BGRA;
  `h264_qsv` needs NV12 first (`hevc_qsv` takes BGRA). FFmpeg 9.0.2 also has
  `{h264,hevc,av1}_d3d12va` encoders, which work on any vendor through D3D12.

Unlike libwebrtc's WGC texture mode, which needs Windows 11 24H2, this path
should reach every Windows that has WGC (10 1903 and later), with `ddagrab` for the
Windows 10 screen path. What it changes: the frames would come from ffenc instead of
libwebrtc's capturer, so capture moves out of `capture.rs` for GPU shares. The
window list, the picker and recovering a swapped game window
(`rift-share-window-recover`) have to be checked against it. Each filter's minimum
Windows version and how it reports a closed window are not checked yet.

**Small change: libwebrtc's WGC texture mode** (`RESEARCH.md`), through our fork's
`desktop_capturer.cpp`. Keeps capture where it is, Windows 11 24H2 and later only.

**To copy from, both GPL:**

- OBS `plugins/obs-nvenc/nvenc-d3d11.c` (~260 lines): opens a shared texture,
  waits on its keyed mutex and copies it on the GPU into a texture registered with
  NVENC. That is the hand-over step 1 needs, for NVENC.
- OBS `plugins/obs-ffmpeg/texture-amf.cpp` (AMF) and `plugins/obs-qsv11/` (QSV):
  the same for the other two vendors.
- OBS `libobs-winrt/winrt-capture.cpp`: WGC with the cursor and border switched at
  runtime, copying each frame on the GPU.
- Sunshine `src/platform/windows/display_vram.cpp` and the HLSL shaders under
  `src_assets/windows/assets/shaders/directx/`: BGRA to NV12/P010 and the cursor
  drawn on the GPU, for NVENC, AMF and QSV.

## Step 2: zero-copy sharing on Linux Wayland

FFmpeg has no PipeWire source (`kmsgrab` needs `CAP_SYS_ADMIN`), so the
PipeWire stream stays Rift's own job, as `PLAN.md` says. From there FFmpeg is
usable as is: `hwmap` from DRM_PRIME to VAAPI, `scale_vaapi`, `h264_vaapi`.

**To copy from:**

- **Sunshine `src/platform/linux/portalgrab.cpp` and `pipewire.cpp`** (GPL-3.0):
  - The portal with a saved restore token.
  - A PipeWire stream offering DMA-BUF with each format's modifiers.
  - EGL import, then `vaapi.cpp` or `cuda.cpp`/`cuda.cu` into the encoder.
  - The GL shaders `ConvertY`/`ConvertUV`.

  This is nearly the shape Rift already has (its own portal and restore token),
  so the closest match of any project.
- **OBS `plugins/linux-pipewire/pipewire.c`** (GPL-2.0-or-later):
  - Offers modifiers and renegotiates without one that failed to import.
  - Reads the cursor from PipeWire's metadata.
- **OBS `plugins/obs-ffmpeg/obs-ffmpeg-vaapi.c`, `vaapi_encode_tex`:**
  - Exports the encoder's own VA surface (`vaExportSurfaceHandle`).
  - Imports it as GL textures and draws NV12 into it, so the encoder reads what
    the GPU drew.
- **OBS `plugins/obs-nvenc/nvenc-opengl.c`:** GL textures registered with CUDA
  (`cuGraphicsGLRegisterImage`) and copied on the GPU into NVENC's surface.

## Step 3: GPU decode and draw for desktop watchers

**New since `RESEARCH.md`: LiveKit's pass-through decoder,
[rust-sdks #1515](https://github.com/livekit/rust-sdks/pull/1515)** (open, last
updated Oct 27, Apache-2.0, ~4,400 lines with tests). It hands Rust each received
video frame still encoded, for H264, H265, VP8, VP9 and AV1, with keyframe
requests and the RTP time, instead of decoding it. It is the receive-side twin of
the pass-through encoder Rift already sends with. For route (b) that removes the
C++ decoder-factory work: the Rust receive connection takes the frames and decodes
them with FFmpeg on the GPU (an "ffdec" beside ffenc). Decryption runs before the
decoder in libwebrtc, so the frames should arrive decrypted; to confirm. It could be
taken into our fork now, ahead of upstream.

**Decode and draw, to copy from: Moonlight's
`app/streaming/video/ffmpeg-renderers/`** (GPL-3.0). This is step 3 almost
exactly, ending in its own window instead of a Flutter texture.

- `d3d11va.cpp`: FFmpeg d3d11va decode, its frames bound straight to shaders, and
  YUV→RGB pixel shaders with colour spaces and HDR.
- `vaapi.cpp` and `eglimagefactory.cpp`: VAAPI decode exported as DRM PRIME and
  imported as an EGLImage.
- `cuda.cpp`: NVDEC into GL.
- `eglvid.cpp`: the GL renderer.

**The Flutter end, usable nearly as is: media_kit** (MIT).

- `media_kit_video/windows/angle_surface_manager.cc` and `video_output.cc`: a D3D11
  texture shared with Flutter by DXGI handle through `GpuSurfaceTexture`.
- `media_kit_video/linux/texture_gl.cc`: an `FlTextureGL`, using `eglCreateImageKHR`.

This is the plumbing for the drawing half, which comes first in `PLAN.md`.

**Looked at and not a fit:**

- **Shiguredo sora-cpp-sdk** (Apache-2.0) has libwebrtc decoders for AMD AMF (H264,
  H265, AV1, VP9), Intel VPL and NVIDIA. All three copy each frame back into a CPU
  I420 buffer, and they need the vendors' SDKs, so they are not zero-copy.
- **LiveKit [rust-sdks #1282](https://github.com/livekit/rust-sdks/pull/1282)**
  (open) adds a Windows Media Foundation H264 encoder and decoder. The decoder runs on
  the GPU through D3D11 but reads every frame back to the CPU.
- **webrtc-sdk's Windows H265** ([libwebrtc #133](https://github.com/webrtc-sdk/libwebrtc/pull/133),
  in our flutter_webrtc's libwebrtc) converts its output to CPU I420 too.
- **Upstream flutter_webrtc and webrtc-sdk** have nothing for desktop hardware
  decoding or GPU frames (searched Oct 29). The only new hook is #2233, for senders.
- **RustDesk's `flutter_gpu_texture_renderer`** does the same Windows texture hand-over
  as media_kit, but has no licence.

## Step 4: H265, then AV1

- **Usable as is in FFmpeg 9.0.2:** `hevc_*` and `av1_*` for NVENC, AMF, QSV, VAAPI
  and D3D12.
- **FFmpeg's Vulkan encoders** (`h264/hevc/av1_vulkan`) would be one path for every
  vendor. Reports on Oct 29 say they are not dependable yet: invalid AV1 output on
  NVIDIA, a lost device on Intel Arc. Not a base for now.
- **AV1 through encryption is still unmerged.** LiveKit's JS SDK has
  [client-sdk-js #1782](https://github.com/livekit/client-sdk-js/pull/1782)
  (open, last updated Jun 11). The Rust branch `dc/exp/av1_e2ee_support` is not
  merged either.

### Step 3, checked again Nov 2, after the VAAPI half was built

**rust-sdks #1515, the pass-through decoder in our fork.** By one outside
contributor (himmelroman, whose only other LiveKit work is #1516, a crash fix,
also open). About 4,400 lines with unit tests. An automated review found two
issues; one was fixed with tests, the other answered from libwebrtc's frame
buffer, correctly as far as we read it. A LiveKit maintainer asked another to
lead the review on Oct 17; no human review yet. A recorder project asked for it
on Oct 27. Its CI fails in two places:

- **Windows doesn't link** (`livekit_ffi.dll`, LNK2019): the test-only bridge
  type `DecodeForTest` is compiled on every platform, and MSVC wants the Rust side
  of its `Vec`, which nothing on the Rust side uses. Linux's linker drops the
  unused code, so it passed here. Rift's Windows build will meet the same error
  through the fork, so the fork needs a fix (gate the test helper, or instantiate
  the `Vec` in the bridge) before Windows builds on this commit.
- A macOS data-track test timed out. That test has nothing to do with this PR.

**Decode and draw, compared with Rift's own** (Moonlight at 1ced9dd, mpv at
a687796). Rift's decoder is FFmpeg's standard GPU decode in about 200 lines,
and FFmpeg does the decoding itself. The runner imports each plane into EGL,
as Moonlight and mpv do. What they handle that Rift does not yet:

- **A modifier of `DRM_FORMAT_MOD_INVALID`.** Both leave the modifier out of
  the EGL import then. Rift always passes it. Intel's iHD always gives a real
  one; an older Mesa on AMD may not.
- **The picture's own colour space and range.** Moonlight reads both from the
  decoded frame and passes them to EGL (`EGL_YUV_COLOR_SPACE_HINT_EXT`,
  `EGL_SAMPLE_RANGE_HINT_EXT`). Rift's shader assumes BT.601 limited, which is
  what every Rift sender writes (`ffenc.c`, libyuv). A share from a browser
  with a hardware encoder could say BT.709, and its colours would be slightly
  off. The old path assumes BT.601 too.
- **Driver quirks** (Moonlight's `vaapi.cpp`): iHD crashing under XWayland
  (Rift decodes only under Wayland), i965 needing the pixel format named
  (Intel before Broadwell), and the VDPAU-backed VAAPI driver, which Moonlight
  refuses.

Licences: Moonlight GPL-3.0; mpv's `hwdec_cuda*.c`, `hwdec_vaapi.c` and
`dmabuf_interop_gl.c` LGPL-2.1-or-later. Either can be copied into Rift.

**NVIDIA, the options:**

- **NVDEC through FFmpeg's CUDA decoder, copied into the runner's GL textures
  on the GPU.** This is Moonlight's (`cuda.cpp`, `CUDAGLInteropHelper`) and
  mpv's (`hwdec_cuda.c`, `hwdec_cuda_gl.c`) way. Register the two plane
  textures with `cuGraphicsGLRegisterImage`, then `cuMemcpy2D` each picture
  into them. It covers H264, VP8, VP9, AV1 and H265, on any driver Rift's
  NVENC already needs. One copy a picture stays on the GPU. The copy has to
  run in the runner's GL context, so the runner calls into the FFmpeg library
  for it, as `nvenc_gl.c` already does the other way. **Recommended.**
- **FFmpeg's Vulkan decoder, exported as DMA-BUF into the existing import.**
  One path for every vendor in principle (`h264/hevc/vp9/av1_vulkan` in FFmpeg
  9.0.2, and `vulkan_map_to_drm`). But it has no VP8; Firefox 153's Vulkan
  decoding is still opt-in and wants NVIDIA 595 or later; and nobody shows
  NVIDIA's decoded Vulkan images exported as DMA-BUF. Not a base for now.
- **nvidia-vaapi-driver** (MIT, 0.0.18 in Aug 2026), VAAPI on top of NVDEC.
  With it, Rift's VAAPI path would run on NVIDIA unchanged. But it is a
  separate install that most people don't have, it has no 10-bit, and
  Chromium keeps it off by default. At most a later extra, never the path.
- LiveKit's own NVIDIA decoder in `webrtc-sys/src/nvidia/` stays out
  (NVIDIA's licence), and reads each picture back to the CPU anyway.

## What this changes in the plan

- **Step 1** has a second route: FFmpeg's `gfxcapture`/`ddagrab` inside ffenc,
  which reaches Windows 10 and older 11 too. It moves capture out of libwebrtc. The
  owner chooses, when step 1 is designed.
- **Step 3 route (b)** gets smaller: rust-sdks #1515 delivers the encoded frames,
  Moonlight shows the decode and draw, and media_kit the Flutter texture.
- **Step 2** follows Sunshine's PipeWire capture first, and OBS where Sunshine has
  nothing (modifier fallback, the VAAPI texture hand-over).

## Sources

- OBS Studio: https://github.com/obsproject/obs-studio
- Moonlight: https://github.com/moonlight-stream/moonlight-qt
- Sunshine: https://github.com/LizardByte/Sunshine
- FFmpeg n9.0.2 (`libavfilter/vsrc_gfxcapture.c`, `vsrc_ddagrab.c`, `vf_scale_d3d11.c`,
  `libavcodec/d3d12va_encode_*.c`, `vulkan_encode_*.c`): https://github.com/FFmpeg/FFmpeg/tree/n9.0.2
- media_kit: https://github.com/media-kit/media-kit
- Shiguredo sora-cpp-sdk: https://github.com/shiguredo/sora-cpp-sdk
- LiveKit pass-through decoder: https://github.com/livekit/rust-sdks/pull/1515
- LiveKit Media Foundation codecs: https://github.com/livekit/rust-sdks/pull/1282
- webrtc-sdk Windows H265: https://github.com/webrtc-sdk/libwebrtc/pull/133
- LiveKit JS AV1 encryption: https://github.com/livekit/client-sdk-js/pull/1782
- RustDesk: https://github.com/rustdesk-org/hwcodec, https://github.com/rustdesk/flutter_gpu_texture_renderer
- fvp / mdk-sdk licence: https://github.com/wang-bin/mdk-sdk
- Vulkan encode reports: https://www.rendi.dev/post/ffmpeg-8-0-part-3-failed-attempts-to-use-vulkan-for-av1-encoding-vp9-decoding,
  https://community.intel.com/t5/Graphics/ffmpeg-h264-vulkan-and-hevc-vulkan-Encode-failed-on-A750-Linux/m-p/1651997
- rust-sdks #1515 and its CI: https://github.com/livekit/rust-sdks/pull/1515
- mpv: https://github.com/mpv-player/mpv (video/out/hwdec)
- nvidia-vaapi-driver: https://github.com/elFarto/nvidia-vaapi-driver
- nvidia-vaapi-driver 0.0.18: https://phoronix.com/news/NVIDIA-VA-API-Driver-0.0.18
- Firefox 153 Vulkan decoding: https://daily.dev/posts/firefox-is-adding-vulkan-video-decoding-for-nvidia-gpus-om3p1pumx
