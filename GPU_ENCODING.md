# GPU encoding for screen shares on Windows: plan

Status: **phases 0 to 4 done on Windows (H264), Oct 5 2026; AV1 and zero-copy
(phase 5) not started.** Written Oct 4 2026 on the `gpu-encoding` branch.

What came out of doing it, for whoever picks it up next:
- WebRTC's frame dropper still acts on pre-encoded frames: LiveKit's
  pass-through encoder does not claim a trusted rate controller, so a frame
  the dropper judges over the target is dropped after encoding, and an H264
  delta frame dropped breaks the picture until the next keyframe. The fix is
  one line, open upstream as LiveKit rust-sdks PR #1459. Until it lands Rift
  carries that line in `third_party/webrtc-sys` (the user's call, Oct 5 2026;
  `RIFT_PATCHES.md` there says when it goes). With it the live test passed 6
  runs in 6 with no frame dropped, against 4 in 6 without it.
- With the dropper out of the way the encoder runs VBR, so a still screen costs
  little: unconstrained, because under a peak Intel's encoder added keyframes
  nobody asked for, and with a quantiser floor of 18, because without one
  NVIDIA's re-coded a still picture forever at most of the rate. In the app a
  still window went from 8.2 Mbps to 0.6 at the viewer, and the moving clip
  still got its 10 (Oct 5 2026). A share starts at LiveKit's 1 Mbps, and a size
  or rate change re-encodes on the same track rather than publishing a new one.
- Intel's encoder writes a three-byte start code before each slice, and
  LiveKit's encryption authenticates the bytes before the first slice, which a
  receiver rebuilds with four-byte ones: every frame failed to decrypt. Start
  codes are rewritten to four bytes (`encoder/h264.rs`).
- On a laptop with two GPUs, NVIDIA's encoder only opens in a process Windows
  runs on the NVIDIA GPU (ffmpeg's `h264_mf` behaves the same); the next
  encoder in the list, Intel's, is used then. The Rift app itself opened
  NVIDIA's on the test laptop.
- Measured numbers and the bench are in `rust/src/screenshare/bench_test.rs`
  and `gpu_live_test.rs`; what was driven is in `TESTING.md`.
This file is a hand-off. An agent picking it up on Windows should read it first,
then `AGENTS.md`, `CODE_STYLE.md`, and the screen share code it names.

## Why

Users stream games, and the result is grainy or stutters. Windows is where it is
worst, because **LiveKit's Rust SDK has no hardware video encoder on Windows**:

- `webrtc-sys` builds NVENC (NVIDIA) and VAAPI (Intel/AMD) on Linux only, and
  VideoToolbox on Apple.
- On Windows every frame is encoded in software (libvpx VP8/VP9, OpenH264,
  libaom AV1), on the same CPU the game is using.
- Under load the encoder drops to its fastest, lowest-quality settings.
- This holds in the newest release as of Oct 4 2026 (`livekit` 0.9.3,
  `webrtc-sys` 0.3.47).
- LiveKit's hardware encoder page lists no Windows entry:
  <https://docs.livekit.io/robotics/media/video/encoders/>.

LiveKit does take video we have already encoded, its "pre-encoded" path. So the
plan is to encode on the GPU ourselves through **Media Foundation**, the Windows
media API. NVIDIA, AMD and Intel all ship hardware encoders for it, so one
implementation covers all three. We then hand LiveKit the finished frames.

Already done, and not part of this plan:
- Commit a62a1eab added the share's **Prioritise** setting (Smoothness by
  default), WebRTC's degradation preference.
- Commit 693e8997 stopped the stream's sound drifting behind the picture.

## Decisions already made with the user

1. **H264 and AV1 are only ever encoded by the OS or the GPU, never on our CPU.**
   - Without a hardware encoder, the share uses VP9 in software, as today.
   - Reason: patents. H264 is licensed through the Via LA pool.
   - Using the encoder in Windows and the GPU driver means Rift itself ships no
     new H264 encoder; the GPU makers are pool licensees.
   - VP8, VP9 and AV1 are royalty-free.
   - A lawyer looks at this before Rift nears 100,000 downloads a year (the pool's
     free tier).
2. **VP8 and VP9 stay** as CPU options. No GPU encodes VP8, and only Intel encodes
   VP9.
3. **H265 is skipped.** Too many viewers cannot play it (the web outside Safari
   and Edge, Firefox, flutter_webrtc on desktop).
4. **The default codec follows the hardware.**
   - On a PC with a hardware H264 encoder, the default becomes H264, or AV1 if the
     GPU encodes it and every viewer platform can play it (check that first).
   - Elsewhere it stays VP9.
   - The dialog offers H264 and AV1 only where the hardware can encode them.
5. **Do not fork `webrtc-sys`** to add NVENC on Windows. It would cover NVIDIA
   only, and the project dropped its LiveKit fork in Sept 2026 to stay on
   upstream. Carrying one upstream fix in `third_party/webrtc-sys` until it is
   released is not that fork; the user agreed to it on Oct 5 2026.
6. Hint text in the dialog says only what an option is best for, e.g. "Best for
   games and video.", never how it works.

## This machine

- It is the user's laptop, dual-booted. **The Windows test VM used before on the
  Linux side is a separate virtual machine, not this install.**
- So this Windows has none of that setup. See "Setting up" below.
- GPUs, both usable on Windows:
  - **NVIDIA GeForce RTX 3070 Ti Laptop** (Ampere). NVENC encodes H264 and
    H265; no AV1 encoding, which starts at RTX 40.
  - **Intel Iris Xe** (Alder Lake-P). Quick Sync encodes H264 and H265; no AV1
    encoding.
- So H264 can be tested on two vendors' encoders. AV1 cannot be tested here, so
  build it later or leave it behind a check that never succeeds on this laptop.
- **AV1 is tested on the user's desktop later.**
  - It has an **AMD Radeon RX 9070 XT** (RDNA 4), which encodes AV1. It is also a
    third vendor for H264.
  - First check that AMD's driver offers AV1 as a Media Foundation encoder (list
    the encoders, as in Phase 1).
  - If AV1 is only reachable through AMD's own SDK (AMF), that is extra work.
    Raise it with the user rather than adding a second encoder backend on your
    own.

## Setting up (first session)

Install:
- Git.
- **Visual Studio Build Tools 2022** with the C++ workload, **VC tools and ATL**.
  Without ATL the build fails with `atlbase.h` not found.
- **Rust** (stable, MSVC toolchain).
- **Flutter 3.47.5**, the version the Linux side and the Windows VM build with.
- **Inno Setup**, for the installer.

Then:
- Clone the repository from the Forgejo remote (`git.codingfries.com`, repo `rift`)
  and check out `gpu-encoding`.
- The user signs in to Forgejo; never print a token.
- Build like the VM did: `flutter pub get`, then the cargo release build in
  `rust/`, then `scripts/build_windows_installer.ps1`. See `AGENTS.md`, Commands.
- **A Rust change needs a release build of the crate.** cargokit ships whatever
  library is already built, and a stale one fails at launch with a content-hash
  mismatch.
- The installer build is obfuscated (inno_bundle forces `--obfuscate`); that is
  expected.

**There is no Rift server while Linux is not running.** The local Docker stack
lives on the Linux side. Testing without one:
- **Rust live tests:** `cargo test live_ -- --ignored --test-threads=1` in `rust/` runs a real
  share and a viewer against a LiveKit server.
  - Get `livekit-server` for Windows from the LiveKit releases and run it with
    `--dev`.
  - Read `rust/src/screenshare/live_test.rs` for the server URL, keys and the
    `XDG_SESSION_TYPE` note, which is Linux-only.
  - This is the main test bed: no app, no Supabase.
- **The full app needs a server with Supabase.** Ask the user which one to use.
  Do not point a test build at production or the user's Mac mini without asking.

## How the share works today

Rust (`rust/src/screenshare/`):

- **`session.rs`:** one share at a time.
  - Connects its own LiveKit `Room` (a second participant, encrypted with the
    call's key).
  - Creates the `NativeVideoSource` and publishes it.
  - The audio side is `sharing/audio/`.
- **`capture.rs`:** libwebrtc's `DesktopCapturer` (WGC/DXGI on Windows) on a
  thread, paced to the chosen fps by our own timer. Frames arrive as CPU ARGB.
- **`frames.rs`:** ARGB to I420, scales to the target size, then
  `NativeVideoSource::capture_frame`.
- **`resolution.rs`:** `target_size`, the one place the output size is decided.
- **`track.rs`:**
  - `TrackSettings` (height cap, fps, bitrate, codec, priority) and
    `publish_video_track`, which publishes with `TrackPublishOptions`.
  - Simulcast is off, and the codec and degradation preference come from
    settings.
  - `video_encoder` is left at `Auto`.
- **`api/screenshare/types.rs`:**
  - `ScreenShareConfig` and the `VideoCodec` enum (`H264`, `VP8`, `VP9` only).
  - `SharePriority`.
  - `ShareQuality` is what can change mid-share: size, fps, sound.
- After changing the API surface, regenerate the bindings with
  `flutter_rust_bridge_codegen generate`, pinned to 2.13.0. Commit the generated
  files with the source change.

Dart:

- `lib/data/classes/screen_share_settings.dart`: the saved settings. The codec is
  stored as a string; `codecFromName` maps it, and unknown names fall back to VP9.
- `lib/presentation/screens/home/screenshare/`: the dialog, one section per
  setting (`sections/codec_section.dart` and others).
- `lib/logic/cubits/screenshare/screenshare_cubit.dart` builds `ScreenShareConfig`.

## LiveKit's pre-encoded path (verified in `livekit` 0.9.1, `libwebrtc` 0.3.48)

- **Source:** `NativeVideoSource::new_encoded(resolution)` creates a source for
  already-encoded frames. It sends no black keepalive frames.
- **Feeding frames:** `source.capture_encoded_frame(&EncodedVideoFrame { .. })`,
  one call per access unit. The fields:
  - `codec: EncodedVideoCodec` (`H264`, `H265`, `VP8`, `VP9`, `AV1`)
  - `payload: &[u8]`
  - `timestamp_us: i64` (capture time)
  - `frame_type: EncodedFrameType` (key or delta)
  - `resolution`
  - `frame_metadata: Option<..>`
- **Keyframe requests:** `source.take_keyframe_request() -> bool`. A viewer
  joining, or packet loss, asks for one. Poll it each frame and force an IDR when
  it is true.
- **Rate control:** `source.take_rate_control_request() -> Option<EncodedRateControl>`
  carries `{ target_bitrate_bps, framerate_fps }` from WebRTC's bandwidth
  estimate. Poll it each frame and apply it to the encoder. We follow it; we do not
  estimate bandwidth ourselves.
- **Publishing:** set `video_encoder: VideoEncoderBackend::PreEncoded` in
  `TrackPublishOptions`, with the matching `video_codec`.
- **How the pass-through works:** it is `webrtc-sys`'s
  `passthrough_video_encoder.cpp`. It cannot make a keyframe itself, so it
  forwards the request; read it to see exactly what it expects. Specifically:
  - the H264 bitstream format (Annex B start codes is the likely answer)
  - SPS/PPS on every IDR
  - how it fills codec-specific info
- To see the source code, open the crates in the cargo registry:
  - `libwebrtc-<ver>/src/native/video_source.rs`
  - `libwebrtc-<ver>/src/video_frame.rs`
  - `webrtc-sys-<ver>/src/passthrough_video_encoder.cpp`
  - `livekit-<ver>/src/room/options.rs`
- `libwebrtc::native::yuv_helper` has `argb_to_nv12` (libyuv), the format
  hardware encoders take.

## The plan

### Phase 0: measure before building

On this laptop, run a 1080p60 share of a moving game or video with today's
software VP9 and H264 (OpenH264), and note:
- Rift's CPU use.
- Frames actually sent; LiveKit stats or a viewer's received rate.
- How it looks.

That is the number this work has to beat. Write it up as described under "Testing".

### Phase 1: a Media Foundation H264 encoder (Rust, Windows only)

Create `rust/src/screenshare/encoder/` (or similar), with the Windows code in its
own file gated at the `mod` line, as `sharing/audio/windows.rs` is. Use the
`windows` crate, already a dependency; add the `Win32_Media_MediaFoundation`
features.

1. **Find hardware encoders.**
   - Call `MFTEnumEx(MFT_CATEGORY_VIDEO_ENCODER, MFT_ENUM_FLAG_HARDWARE |
     MFT_ENUM_FLAG_SORTANDFILTER, input NV12, output H264)`.
   - Expect both NVIDIA's and Intel's MFT here.
   - Prefer the GPU that also renders the game? Start with the first one sorted.
     Log every candidate with its friendly name.
2. **Hardware MFTs are asynchronous.**
   - Unlock with `MF_TRANSFORM_ASYNC_UNLOCK`.
   - Drive it from its event generator: `METransformNeedInput` and
     `METransformHaveOutput`.
   - Run it on its own thread, and give it the same care on stop as the capture
     thread.
3. **Configure for real-time streaming** through `ICodecAPI`:
   - `CODECAPI_AVLowLatencyMode = true`.
   - **No B-frames** (`CODECAPI_AVEncMPVDefaultBPictureCount = 0`); WebRTC cannot
     carry them.
   - CBR or low-delay VBR rate control.
   - A long GOP with keyframes on request (`CODECAPI_AVEncVideoForceKeyFrame`).
   - The bitrate changed live (`CODECAPI_AVEncCommonMeanBitRate`) whenever a rate
     control request comes in.
   - **Profile:** check what LiveKit negotiates. WebRTC's default is constrained
     baseline (`42e01f`); constrained high (`640c1f`) is also widely accepted.
4. **Input:** keep today's capture, and convert ARGB to NV12 with `argb_to_nv12`
   into an `IMFSample` in system memory. Simple, and it already takes the encoding
   load off the CPU.
5. **Output:** turn each output sample into an `EncodedVideoFrame`:
   - an Annex B payload
   - the keyframe flag from `MFSampleExtension_CleanPoint`
   - the timestamp from the frame's capture time

### Phase 2: wire it into the share

- Choose the path at publish time.
  - If the codec is H264 and a hardware encoder opens, use
    `NativeVideoSource::new_encoded` and `VideoEncoderBackend::PreEncoded`, and
    feed the encoder from `frames.rs`.
  - Otherwise use today's path, unchanged.
- **If the encoder fails to open, or fails mid-share, fall back to software
  VP9.** Republish the track; the quality change already republishes. Tell the
  sharer with a short toast. A share must never go black because of the GPU
  path.
- Poll the keyframe and rate control requests every frame.
- Keep `TrackSettings.priority` working. With pre-encoded frames, WebRTC's
  degradation preference has less to act on. Decide what Smoothness means there:
  probably keep the frame rate and let the bitrate drop.
- Mid-share changes (resolution and fps from the control bar) must reconfigure
  or recreate the encoder.

### Phase 3: what the user sees

- Add a Rust API that reports which codecs this machine can encode in hardware.
  The dialog uses it to offer H264 (and later AV1) only when they can be GPU
  encoded, and to pick the default (decision 4).
- **A saved H264 choice on a PC without a hardware encoder:** do not encode H264
  in software. Fall back to VP9 and show that in the dialog.
- This removes the software H264 option on Windows, which is the point of
  decision 1.
- Keep option hints to "Best for …".

### Phase 4: prove encryption still holds

Screen shares are end-to-end encrypted with the call's key (`ARCHITECTURE.md`
§5, and the comment on `ScreenShareConfig::e2ee_key`). The frame cryptor works on
encoded frames, so pre-encoded frames should be encrypted the same way. **Prove
it, do not assume it.** In a live test:
- A viewer with the right key sees the picture.
- A viewer with a wrong key gets nothing decodable.

A share the server could watch is a security bug.

### Phase 5 (later)

- **AV1** on GPUs that encode it (RTX 40+, AMD RX 7000+, Intel Arc). Same
  Media Foundation path with AV1 output. First check that every viewer platform
  can play AV1: the web, Android, iOS, and flutter_webrtc on desktop.
- **Zero-copy:** capture with Windows.Graphics.Capture straight to a D3D11
  texture, convert to NV12 on the GPU (the D3D11 video processor), and give the
  encoder D3D11 samples through an `IMFDXGIDeviceManager`. This replaces
  libwebrtc's capturer on Windows, so it is a bigger step. It saves the CPU
  copies that Phase 1 still makes.
- 120 fps. libwebrtc caps at 120 (`kMaxFramerateFps`).
- Higher bitrate options.

## Testing

Use the Rust live test with a local `livekit-server --dev` first. Then compare:
- **CPU:** Rift's CPU at 1080p60 with software VP9 against GPU H264, on NVIDIA
  and on Intel.
- **Smoothness:** frames received per second at the viewer.
- **Quality:** a side-by-side look, or screenshots of the same moving scene.
- **Keyframe requests:** a viewer joining mid-share sees a picture within about
  a second.
- **Bandwidth:** throttle the link (or lower the cap) and the bitrate follows the
  rate control requests.
- **Fallback:** force the open to fail (pretend no MFT); the share comes up on
  VP9.
- **Encryption:** Phase 4.

Record what was driven in `TESTING.md`, a row per behaviour, saying what was
checked and what was not, in the commit that makes it true. `MANUAL_TESTING.md`
is a gitignored log kept on the Linux side. On Windows, keep notes in a local
file and say so in the report.

## Rules that apply (from AGENTS.md and the user)

- Rust:
  - `rust/src/api/` is only the bridge. Internals are `pub(crate)` outside it.
  - Log with `log::`, never `println!`.
  - Pure logic gets unit tests (`cargo test`).
- Dart: `flutter analyze` clean and `flutter test` passing before every commit.
- Commits:
  - One logical change per commit, with an imperative subject.
  - Messages end with the co-author line the session gives.
  - Stage specific paths, never `git add -A`.
- Docs change in the same commit that makes them untrue.
- **Push only when the user asks.** No production deploys.
- Keep answers to the user short and plain.
