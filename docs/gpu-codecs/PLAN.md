# GPU encoding and decoding — plan

Oct 29 2026. Proposed, not yet agreed step by step; each step is designed with
the owner before it is built. The owner's ruling: all four get built, on the
`gpu-codecs` branch. Why each step is shaped as it is: `RESEARCH.md`.

## Steps

0. **Measure first.**
   - Split the CPU cost by stage on Windows and Linux. Sharer: capture readback,
     convert, upload. Watcher: decode, ABGR convert, upload/draw.
   - Use the perf kit, 1080p60 and 1440p120.
   - This decides which half pays more.
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
2. **Zero-copy sharing on Linux Wayland.**
   - libwebrtc always reads back, so Rift runs the PipeWire stream itself. It
     already runs the portal picker and holds the restore token on GNOME and KDE.
   - Negotiate DMA-BUF with modifiers.
   - VAAPI: hwmap DRM_PRIME→VAAPI, scale_vaapi to NV12, h264_vaapi.
   - NVIDIA: EGL import, GL shader to NV12, CUDA-GL interop into NVENC (Sunshine's
     way), or Vulkan with hwmap to CUDA.
   - Rift draws the cursor itself from PipeWire's metadata.
   - X11 stays on the CPU.
3. **GPU decode and draw for desktop watchers.** This is what makes High, H265 and
   AV1 worth having.
   - (b) recommended: watch a share through the Rust side.
     - A receive-only Rust connection subscribes to the share's video.
     - Our decoder factory in webrtc-sys: FFmpeg hwaccel (d3d11va / vaapi / nvdec),
       with libwebrtc's software decoders as the fallback.
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

- Which half comes first: the sharer (steps 1–2) or the watcher (step 3).
  Step 0's numbers inform it.
- Step 3: watch through a Rust receive connection (recommended) or rebuild
  flutter_webrtc's libwebrtc.
- H265 decoding: FFmpeg's hevc decoder refusing to run without a hwaccel, or
  the vendors' decoders directly (cuvid, D3D11), so no software H265 ships.
- Whether Windows 10 gets a GPU-side DXGI-duplication capturer, or keeps
  today's path.
