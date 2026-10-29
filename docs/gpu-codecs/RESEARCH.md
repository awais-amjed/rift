# GPU encoding and decoding — research

Oct 29 2026. Asked by the owner: "how we can add GPU encoding and decoding in our
app ... that thing about GPU encoded frame going to CPU first ... for H264, H265
and AV1". Research only; nothing built. The plan built on it is `PLAN.md`; the codec ladder
step 4 needs is `CODEC_LADDER.md`; what can be reused from open source projects is
`REUSE.md`.

## Where a picture goes today

### Sharing (desktop, GPU H264)

1. **Capture, libwebrtc** (`capture.rs`, LiveKit's prebuilt m150): the picture is on
   the GPU and is copied to the CPU.
   - Windows WGC: copy into a staging texture, Map, row-by-row memcpy
     (`wgc_capture_session.cc`).
   - Linux PipeWire: the DMA-BUF is imported into EGL and read back with
     glReadPixels (`egl_dmabuf.cc`, `shared_screencast_stream.cc`); there is no
     option to keep it on the GPU.
   - X11: XShm, already CPU.
2. **Convert, CPU** (`frames.rs`, `gpu_feed.rs`): libyuv ARGB→NV12, or ARGB→I420,
   then scale, then I420→NV12 when the size differs.
3. **Upload, GPU**: NVENC reads system memory; VAAPI goes through
   `av_hwframe_transfer_data` (`ffenc.c`).
4. **Encode, GPU**, then the bitstream (~10–60 KB a frame) comes back to the CPU for
   the network. That last copy is unavoidable and cheap. The two big copies are the
   raw picture going down and up: at 1440p120 that is about 1.8 GB/s down in BGRA,
   plus 0.66 GB/s up in NV12.

### Watching (desktop)

flutter_webrtc's prebuilt libwebrtc (webrtc-sdk m150):
- Decodes in software on the CPU: FFmpeg H264, libvpx, dav1d.
- H265: none on Linux (the capability list on Oct 29 had none). On Windows the
  build carries a Media Foundation H265 decoder (`wmf_h265_decoder.cc`, its log
  strings in `libwebrtc.dll` m150.7871.04). It is never given a D3D device, so
  Microsoft's HEVC decoder most likely runs in software, and it copies each frame
  into a CPU I420 buffer either way. Read from the source and the binary, not run.
- `FlutterVideoRenderer::CopyPixelBuffer` converts each frame to ABGR on the CPU
  (`ConvertToARGB`).
- Flutter uploads it as a `PixelBufferTexture`.
- That wrapper API has no decoder-factory hook and no native/GPU frames
  (`include/*.h`), so nothing can be plugged in without rebuilding it.

Measured cost: 117% of a core watching 1080p60 H264 on a Windows laptop (CALLS.md);
High added 33–50% on top. Of the 117%, about 87% is the stream page itself
(converting, uploading and drawing, nearly all on Flutter's raster thread) and
7–30% the decoder, depending on the stream's rate (`watch-draw` branch,
`scripts/perf/WATCH_DRAW.md`). On Linux the convert and upload is about 15–17%.
So the drawing half of step 3 removes most of today's cost by itself; the
wrapper's `RTCVideoFrame` already exposes the I420 planes (`DataY/U/V`).

- **Android:** flutter_webrtc already decodes with MediaCodec and draws through a
  SurfaceTexture, so it is GPU on both ends.
- **Web:** the browser's own decoder.

## What exists to build on

- **WGC texture mode, libwebrtc m150:**
  - `DesktopCaptureOptions::set_allow_wgc_using_texture`, present in the prebuilt
    headers.
  - The frame carries `DesktopFrame::texture()`, a `FrameTexture` (`DXGIDesktopFrame`
    wraps the WGC pool's own ID3D11Texture2D) and `data()` is null.
  - It needs Windows 11 24H2+ (`DoesWgcSkipStaticFrames`), and the cursor is always
    embedded.
  - `d3d_device_luid` picks the adapter the capture device is created on.
  - Added upstream Mar 25 2026 (webrtc 1d5a6e111f). Its non-Windows handle type is
    an fd, but no Linux capturer fills it yet.
- **Rust libwebrtc native buffers:**
  - `NativeBuffer` (`libwebrtc/src/video_frame.rs`) already carries DMA-BUF fds
    (from Jetson work) and a CVPixelBuffer on Apple.
  - webrtc-sys compiles its decoder factory from our fork's C++
    (`video_decoder_factory.cpp`), so we can add decoders.
  - The fork's NVIDIA decoder copies to I420, and it is built from NVIDIA SDK
    samples, so its licence keeps it out of the GPL client.
- **LiveKit's prebuilt for Rust:** built with `rtc_use_h265=true`.
- **LiveKit server:** H265 since 1.8.4, on by default since 1.9.1. We run 1.13.7.
  The server turns AV1 off for Safari (1.8.3) and for Firefox (1.13.11).
- **Encryption:**
  - libwebrtc frame cryptor (webrtc-sdk): H264 and H265 keep each slice's NAL header
    in the clear; AV1 encrypts everything.
  - The JS SDK throws on AV1 ("not yet supported for end to end encryption").
  - The Dart SDK sets up no cryptor for AV1 at all.
  - LiveKit has an experimental branch, `dc/exp/av1_e2ee_support` (Jun 2026), that
    wraps encrypted AV1 in a synthetic temporal unit carrying the real sequence
    header. It is not merged, and it is Rust only.
- **Flutter:**
  - Windows `GpuSurfaceTexture` takes a DXGI shared handle or an ID3D11Texture2D;
    ANGLE opens it on its own device. The texture must be on Flutter's adapter
    (`FlutterDesktopEngineGetGraphicsAdapter`).
  - Linux `FlTextureGL::populate` returns a GL texture name in Flutter's context;
    DMA-BUF goes in through EGL_EXT_image_dma_buf_import.
  - Prior art: minigpu_view (DXGI shared handle), media_kit and fvp (hardware decode
    drawn through GL/ANGLE), mpv_kit_video (Vulkan, then a D3D11 KMT or opaque fd
    into GL).
- **Sunshine (prior art for zero-copy sending):**
  - Windows: DXGI duplication or WGC texture → NT-handle shared texture with a keyed
    mutex → HLSL BGRA→NV12/P010 into the encoder's own input texture, through
    FFmpeg's D3D11 frames for AMF and QSV and NVENC's native D3D11 path.
  - Linux VAAPI: DMA-BUF → EGL texture → GL shader writing NV12 into a VA surface
    exported with `vaExportSurfaceHandle` and imported as an EGL render target.
  - Linux NVIDIA: the same shader into GL textures registered with
    `cuGraphicsGLRegisterImage` → `cuMemcpy2DAsync` into FFmpeg's CUDA frame.
- **FFmpeg (our ffenc is 9.0.2):**
  - Encoders `{h264,hevc,av1}_{nvenc,amf,qsv,vaapi}`.
  - Decoding through hwaccels: d3d11va/d3d12va (all vendors, H264/HEVC/AV1/VP9),
    vaapi, nvdec/cuvid, vulkan (decode on NVIDIA, AMD RADV and Intel ANV).
  - Filters: hwmap DRM_PRIME→VAAPI with scale_vaapi, vpp_qsv, vpp_amf, scale_cuda.

## Found by a second, independent research pass (Oct 29)

Another agent researched the same question on dev without seeing this file.
What it added, checked where marked:

- **Windows capture across GPUs.** WGC display capture works across GPUs (since
  Windows 10 1903; OBS relies on it on laptops). DXGI duplication does not: from the
  discrete GPU of a hybrid laptop it fails with `DXGI_ERROR_UNSUPPORTED` by design
  (Microsoft). Rift's Windows 10 screen path is DXGI, so there the screen's GPU and
  the encoder's must match, or the memory path stays.
- **FFmpeg's own Windows capture, as a reference:** `gfxcapture` (WGC, D3D11 frames,
  takes your device, cursor and border control, crop and letterbox), `ddagrab`
  (DXGI, D3D11 frames only), `scale_d3d11` (GPU scale and convert to NV12/P010).
  NVENC and AMF take D3D11 BGRA frames; `h264_qsv` takes only NV12/QSV frames, so a
  conversion first (`hevc_qsv` takes BGRA). In our FFmpeg 9.0.2.
- **H265 through encryption.** libwebrtc's H26x packet buffer only checks that an
  H265 keyframe carries VPS, SPS and PPS; the PPS-id fix-up that forced the H264
  rewrite is H264-only (`h26x_packet_buffer.cc`). So H265 should need no header
  rewrite, if every keyframe carries its parameter sets. To prove with an H265
  version of the Rust live test.
- **AMD's first AV1 generation (VCN 4.0, RX 7000)** pads any size not aligned to
  64×16 with black (2580×1080 came out 2642×1082; Mesa #9185). Shared windows come
  in any size, so this would show.
- **NVIDIA GeForce** allows 12 encoder sessions at once (NVIDIA's matrix).
- **An upstream decoder hook** is a third route for step 3: flutter_webrtc 1.6.3
  added a hook for native plugins on the sending side (video processors on local
  tracks, #2233); the same for decoders would let Rift ship its own.
- **Windows HEVC availability:** built into Windows 11 from 22H2; Windows 10 and
  earlier 11 need the HEVC Video Extensions.

## Hardware coverage (from memory of vendor tables; check before relying)

| | H264 enc | HEVC enc | AV1 enc | AV1 dec |
|---|---|---|---|---|
| NVIDIA | Kepler+ | GTX 900 (GM20x)+ | RTX 40+ | RTX 30+ |
| AMD | GCN+ | RX 400+ | RX 7000+ | RX 6000+ |
| Intel | Sandy Bridge+ | Skylake+ | Arc, Core Ultra (Meteor Lake)+ | 11th gen (Xe)+ |

Rigs:
- Laptop RTX 3070 Ti + Iris Xe: H264 and HEVC encode, no AV1 encode, AV1 decode.
- Desktop RX 9070 XT: all three.

Who can watch:
- **H265:** Chrome 136+ only with a hardware decoder; Safari; not Firefox WebRTC;
  Android if MediaCodec has it (the SM-A566B does); a Rift desktop only once Rift
  decodes it.
- **AV1:** no web viewer while encrypted; a Rift desktop only with both ends on
  LiveKit's experimental AV1 encryption.

## Sources

- WebRTC "Use GPU texture in desktop capture": https://webrtc.googlesource.com/src/+/1d5a6e111f
- `frame_texture.h`, `desktop_capture_options.h`, `win/wgc_capture_session.cc`,
  `win/dxgi_desktop_frame.h` in https://webrtc.googlesource.com/src/+/main/modules/desktop_capture/
- webrtc-sdk frame cryptor: https://github.com/webrtc-sdk/webrtc/blob/m150_release/api/crypto/frame_crypto_transformer.cc
- LiveKit JS FrameCryptor: https://github.com/livekit/client-sdk-js/blob/main/src/e2ee/worker/FrameCryptor.ts
- LiveKit server changelog: https://github.com/livekit/livekit/blob/master/CHANGELOG.md
- Chrome H265 in WebRTC: https://groups.google.com/a/chromium.org/g/blink-dev/c/3h8lL8a377c
- Flutter Windows texture registrar: https://api.flutter.dev/windows-embedder/flutter__texture__registrar_8h_source.html
- Flutter Windows view (graphics adapter): https://api.flutter.dev/windows-embedder/flutter__view_8h_source.html
- Flutter engine D3D texture interop: https://github.com/flutter/engine/pull/26840
- Flutter Linux FlTextureGL: https://api.flutter.dev/linux-embedder/fl__texture__gl_8h_source.html
- minigpu_view: https://pub.dev/packages/minigpu_view
- mpv_kit_video: https://pub.dev/packages/mpv_kit_video
- Sunshine `src/platform/windows/display_vram.cpp`, `src/platform/linux/{kmsgrab,cuda,vaapi}.cpp`:
  https://github.com/LizardByte/Sunshine
- LiveKit encoders: https://docs.livekit.io/robotics/media/video/encoders/
- LiveKit's AV1 encryption experiment: branch `dc/exp/av1_e2ee_support` of livekit/rust-sdks
