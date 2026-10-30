# GPU encoding and decoding — plan

Oct 29 2026. Proposed, not yet agreed step by step; each step is designed with
the owner before it is built. The owner's ruling: all four get built, on the
`gpu-codecs` branch. Why each step is shaped as it is: `RESEARCH.md`. What each
step can take from our own code and from open source projects: `REUSE.md`.

## Steps

0. **Measure first.**
   - Split the CPU cost by stage on Windows and Linux. Sharer: capture readback,
     convert, upload. Watcher: decode, ABGR convert, upload/draw.
   - Use the perf kit, 1080p60 and 1440p120.
   - This decides which half pays more.
   - **Linux sharer, measured Oct 29** (release build, GNOME 50 on Wayland,
     i7-12700H, whole 1920x1080 screen through the portal, a moving test picture
     full screen, H264 1080p60 at 15 Mbit/s, one web viewer). `threadtop` over
     20 s, % of one core, by the share's threads (named for this:
     `share-capture`, `share-frames`):

     | Stage | Thread | NVENC (RTX 3070 Ti) | VAAPI (Iris Xe) |
     |---|---|---|---|
     | Readback (EGL import, glReadPixels) | `pipewire-main-l` | 6.6% | 7.5% |
     | ARGB→NV12 | `share-frames` | 7.3% | 6.8% |
     | Upload and encode | `gpu-encoder` | 6.7% | 9.0% |
     | Copy into the frame | `share-capture` | 0.2% | under 0.1% |

     About 21–23% of a core for the picture's trip through the CPU, which zero-copy
     removes nearly all of. It grows with pixels a second, so 1440p120 (3.6× the
     pixels a second) would be most of a core; this screen cannot show 1440p.
     VAAPI's rate gate left out about a fifth of the pictures (the noisy picture
     overshoots 15 Mbit/s), so its encode figure is for about 48 a second.
     NVENC also *waits* 10 ms in `send` for each picture (ffenc's own timing; 4 ms
     on a still screen), well inside 16.7 ms at 60 fps but more than the 8.3 ms a
     picture has at 120. Zero-copy has to bring that down too, not only the CPU.
   - **After step 2 on Linux, measured Oct 29** (the same laptop, screen, picture,
     rate and viewer, VAAPI, one release build switched between the two paths):
     **4.5% of a core** on Rift's own PipeWire stream (`gpu-encoder` 4.1%,
     `rift-pipewire` 0.3%, `share-frames` 0.1%) against **22.7%** on libwebrtc's
     capturer (9.7%, `pipewire-main-l` 7.2%, `share-frames` 5.7%); the whole
     process 19.1% against 40.1%. Short of the step's "under about 3%": ffenc
     alone, timed in a bench on this driver, spends 0.55 ms of CPU a picture
     (0.25 importing and scaling the DMA-BUF, 0.29 handing it to the encoder),
     3.3% at 60.
   - **Against other recorders, measured Oct 30** (the same laptop, screen,
     picture, H264 on the Iris Xe at 1080p60 and 15 Mbit/s CBR, `threadtop` 20 s,
     twice each, both keeping all 60 pictures): gpu-screen-recorder 6.1.3 costs
     **3.4%** of a core for its whole process, OBS 32.2 **7.8–8.2%** (about 6%
     for the picture: `obs gpu encode` 3.0%, `libobs: graphics` 2.7%, its
     PipeWire thread 0.5%). The "under about 3%" was a design guess, never
     measured against anything; the leanest recorder there is sits at 3.4%.
     **Rift's 4.5% accepted for now (owner, Oct 30).** For later: keep each
     imported buffer instead of importing it again per picture (import once in
     PipeWire's `add_buffer`, drop it in `remove_buffer` or on renegotiation),
     after reading how gpu-screen-recorder gets to 3.4%. Neither OBS nor
     Sunshine keeps them; both import every new picture.
   - **NVIDIA half, measured Oct 30–31** (BIOS set to discrete, RTX 3070 Ti Laptop,
     GNOME 50, 165 Hz, a noisy picture full screen with one small window over it,
     H264 1080p60 at 15 Mbit/s, one viewer; `threadtop` 20 s): **7.5% of a core** for
     the picture's threads on the GL path (`gpu-encoder` 6.8%, CUDA 0.5%, PipeWire
     0.1%, `share-frames` 0.1%) against **10.1%** with the same stream in memory
     (`RIFT_FFENC_NO_GL`: `share-frames` 5.0%, `gpu-encoder` 4.4%, CUDA 0.5%);
     gpu-screen-recorder 15–16% for its whole process, in four of five runs (one
     6.2%, unexplained). `send` 4.4 ms at 60 and about 1 ms at 120, longest 5.1 ms,
     well under the 8.3 ms a picture has at 120. Beside a game (glmark2 terrain,
     full screen, uncapped, GPU at 100%): the frame rate moves within the test's own
     5% drift on every path; the 99th percentile frame is 1.84–2.0 ms on the GL path, 3.81–3.87 ms
     in memory, 1.87–2.33 ms with no share, 1.96–2.53 ms with gpu-screen-recorder.
     glmark2 draws a frame in about 1 ms, so it is not a real game; none was on the
     laptop. No need for a low-priority GL context showed.
   - **Order (owner, Oct 29): Linux first, step 2 before step 1.** This laptop has
     both of Linux's encoders and Wayland, so the step can be built and proved
     here; the Windows VM has no GPU.
   - **Hybrid laptops (owner, Oct 29): encode on the GPU that draws the screen.**
     The compositor's buffers are in the integrated GPU's memory, so VAAPI there
     keeps the picture on one GPU; NVENC would need each picture copied across to
     the NVIDIA card. NVENC stays for a screen the NVIDIA card draws.
1. **Zero-copy sharing on Windows 11 24H2+.**
   - Turn on WGC texture mode (fork: `desktop_capturer.cpp` passes the texture and
     its device out to Rust).
   - Copy on the GPU into the encoder's own pooled texture, so WGC's buffer goes
     back at once.
   - BGRA→NV12 and scaling on the GPU, with ID3D11VideoProcessor (any vendor) or a
     shader. NVENC and AMF can also take BGRA D3D11 frames directly; QSV goes through
     hwmap to QSV.
   - ffenc gains a D3D11 input path: FFmpeg D3D11VA frames on a device on the
     encoder's adapter.
   - Windows 10 and older 11 keep today's path; later, a DXGI-duplication capturer
     kept on the GPU.
   - To prove: a hybrid laptop with the capture device on the NVIDIA adapter while
     the screen is on Intel.
   - Second route (`REUSE.md`): FFmpeg's own `gfxcapture` (WGC) and `ddagrab`
     (DXGI) inside ffenc, with `scale_d3d11`. It reaches Windows 10 and older 11
     too, but moves GPU-share capture out of libwebrtc.
2. **Zero-copy sharing on Linux Wayland.** Designed Oct 29: `STEP2_LINUX.md`.
   - **Order (owner, Oct 29): VAAPI first, then NVIDIA** on this laptop switched
     to NVIDIA-only display in the BIOS.
   - libwebrtc always reads back, so Rift runs the PipeWire stream itself. It
     already runs the portal picker and holds the restore token on GNOME and KDE.
   - Negotiate DMA-BUF with modifiers.
   - VAAPI: hwmap DRM_PRIME→VAAPI, scale_vaapi to NV12, h264_vaapi.
   - NVIDIA: EGL import, GL shader to NV12, CUDA-GL interop into NVENC (Sunshine's
     way), or Vulkan with hwmap to CUDA.
   - Rift draws the cursor itself from PipeWire's metadata.
   - X11 stays on the CPU.
   - Sunshine's PipeWire capture (`portalgrab.cpp`, `pipewire.cpp`, GPL-3.0) is
     nearly this shape; OBS fills the gaps (`REUSE.md`).
3. **GPU decode and draw for desktop watchers.** This is what makes High, H265 and
   AV1 worth having.
   - The drawing half comes first and is needed by every route below: a Flutter
     GPU texture fed by a shader. It can be built and measured before any decoder,
     on the planes today's software decoder already gives (`RTCVideoFrame::DataY/U/V`),
     inside the vendored flutter_webrtc renderer. That alone takes most of
     today's watching cost (about 87% of a core on the Windows laptop,
     `RESEARCH.md`). The hardware decoder then hands it NV12 on the GPU instead.
   - (b) recommended: watch a share through the Rust side.
     - A receive-only Rust connection subscribes to the share's video.
     - LiveKit's pass-through decoder (rust-sdks #1515, open) hands Rust the
       encoded frames; Rust decodes them with FFmpeg hwaccel (d3d11va / vaapi /
       nvdec), falling back to software. Moonlight's renderers show the decode and
       draw, media_kit the Flutter texture (`REUSE.md`).
     - Frames come out as native GPU buffers.
     - A Flutter GPU texture: a DXGI shared handle on Flutter's adapter on Windows,
       FlTextureGL from a DMA-BUF or CUDA-GL on Linux.
     - NV12→RGBA in a shader.
     - Encryption: Rust already has the call key.
     - Costs: a second hidden participant per watcher (the roster must hide it), and
       the share's sound stays on Dart's connection, so the two are not synced.
       Stream A/V grouping is already deferred; measure the drift.
   - (a) the alternative: rebuild webrtc-sdk/libwebrtc for flutter_webrtc with these
     decoders, native frames, a GPU renderer and H265. One connection and lip-sync
     kept, cameras get it too. But Rift then owns a Chromium-toolchain build on
     Windows and Linux.
   - (c) ask upstream (webrtc-sdk/libwebrtc, flutter_webrtc) for a hook that lets a
     native plugin supply its own decoder and receive GPU frames, as 1.6.3 did for
     senders. One connection, no own libwebrtc build; depends on their timing.
     Can be asked in parallel with either of the others.
4. **H265, then AV1, on top of 3.**
   - Enable `hevc_*` and `av1_*` in ffenc.
   - The passthrough encoder advertises the new formats.
   - Check H265's encryption-readable bytes, as `with_readable_pps_id` does for H264.
   - The codec ladder comes back: viewers publish `plays`, and the share steps down
     to what every watcher plays (the parked switch-down spec).
   - AV1 needs LiveKit's AV1 encryption on both ends, so it reaches Rift desktops
     only.
   - Patents: H265 by the GPU only, as H264. Decoding through FFmpeg's hevc decoder
     still ships its software path; refuse without a hwaccel, or use cuvid / D3D11
     directly. Owner's call.

## Open, for the owner

- ~~Which half comes first~~: the sharer, Linux first (owner, Oct 29).
- Step 3: watch through a Rust receive connection (recommended), rebuild
  flutter_webrtc's libwebrtc, or an upstream decoder hook.
- H265 decoding: FFmpeg's hevc decoder refusing to run without a hwaccel, or
  the vendors' decoders directly (cuvid, D3D11), so no software H265 ships.
- Whether Windows 10 gets a GPU-side DXGI-duplication capturer, or keeps
  today's path. FFmpeg's `ddagrab` would be that capturer.
- Step 1: libwebrtc's WGC texture mode (24H2+, capture stays in libwebrtc) or
  FFmpeg's `gfxcapture`/`ddagrab` in ffenc (older Windows too, capture moves).

## Noted for later (not on the hardware path)

From the second research pass (Oct 29); none of these is needed for full
hardware encoding and decoding, so they wait.

- **VP9 shares did not decrypt on the web build: fixed Oct 29 on dev.** The web
  worker left 10 or 3 bytes of a VP9 frame in the clear where LiveKit's native
  and JS cryptors leave none, so a desktop's VP9 share stayed black in the
  browser. Proved and fixed live in Chrome and Firefox
  (`third_party/livekit_client/RIFT_PATCHES.md`, patch 6; `TESTING.md`).
- **Phone and web shares in H264.** They go out as the SDK's default VP8 with
  simulcast, often encoded on the CPU; H264 has a hardware encoder on nearly every
  phone. But a phone's or browser's encoder may put the keyframe's PPS id past
  what encryption leaves readable, and Rift cannot rewrite it inside the SDK. Test
  each with `h264::idr_readable_when_encrypted` before changing the default.
- **Web drawing:** `--dart-define=WEBRTC_USE_HTML_ELEMENT_VIEW=true` shows the
  browser's `<video>` directly instead of a Flutter frame per video frame. Check
  the stage's blurred overlays before using it.
- **flutter_webrtc 1.6.3** moved Windows and Linux to libwebrtc m150.7871.07 to drop
  a compromised eMudhra root certificate. Rift pins .04 for the logging fix
  (`third_party/flutter_webrtc/RIFT_PATCHES.md`); worth a look.
