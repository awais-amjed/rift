# GPU encoding for screen shares on Windows: plan

Status: **phases 0 to 4 done on Windows (H264), Oct 5 2026; zero-copy (phase
5) not started.** Written Oct 4 2026 on the `gpu-encoding` branch.
**AV1 is parked (Oct 5 2026): the GPU encodes it, but no viewer can get it
encrypted. See "AV1: parked". H264 on the GPU is the result of this branch, and
it was proved on AMD the same day.**

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
- A hardware H264 encoder has a largest picture. AMD's opened anything up to
  4096 wide and nothing wider, so a 5120x1440 screen shared at 2K or 4K fell
  back to VP9 on the CPU (178% of a core, against 52% on the GPU). A GPU share
  is now scaled to fit 4096x2304, H264 level 5.1's largest frame
  (`encoder::MAX_SIZE`): that screen goes out at 4096x1152, on the GPU, with
  the sharer's app at 86% of a core (Oct 5 2026). AMD also opened 96x54, so a
  tiny window stays on the GPU too.
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
     GPU encodes it and every viewer platform can play it (check that first;
     on Oct 5 2026 none could get it encrypted, see "AV1: parked").
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
- **AV1 was tried on the user's desktop**, which has an **AMD Radeon RX 9070
  XT** (RDNA 4), and parked. See "AV1: parked".

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
   - **Profile: constrained baseline (`42e01f`), on purpose.** High was
     measured and set aside (Oct 5 2026):
     - **The gain is real.** Both GPUs take High in Media Foundation (CABAC
       and the 8×8 transform on, still no B-frames). On a 1080p60 video clip
       at 8 Mbps it scored 1.4 dB (NVIDIA) and 1.8 dB (Intel) higher luma
       PSNR at the same rate. Scrolling source code took 17 to 19% fewer
       bits at the same quality.
     - **Getting it to viewers is not.** LiveKit's pass-through encoder
       offers only `42e01f`, and the Rust SDK's `create_sender` puts `42e01f`
       first, so offering High means patching both. Firefox subscribes with
       constrained baseline only and gets no video when High is negotiated
       (rust-sdks issue #1492), and the server forwards a share as sent.
       Sending High under the `42e01f` label might decode in Chrome, Safari
       and the desktop app, but it breaks negotiation and is unproven on
       Firefox and Android.
     - Revisit if LiveKit offers High for pre-encoded tracks, or with AV1,
       which needs the same check on every viewer platform.
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

- **AV1:** parked until LiveKit can carry it encrypted; see "AV1: parked".
- **Zero-copy:** capture with Windows.Graphics.Capture straight to a D3D11
  texture, convert to NV12 on the GPU (the D3D11 video processor), and give the
  encoder D3D11 samples through an `IMFDXGIDeviceManager`. This replaces
  libwebrtc's capturer on Windows, so it is a bigger step. It saves the CPU
  copies that Phase 1 still makes.
- 120 fps. libwebrtc caps at 120 (`kMaxFramerateFps`).
- Higher bitrate options.
- H264 High profile, once viewers can negotiate it (see Phase 1's profile
  note).

## AV1: parked

Decided with the user on Oct 5 2026, after steps 0 to 2 below and part of 3.
**The encoder works; the problem is getting AV1 to viewers encrypted, and that
is LiveKit's to fix, not Rift's.**

What exists:
- `encoder/media_foundation.rs` makes H264 or AV1 (`GpuCodec`), and
  `encoder/av1.rs` reads AV1 frame headers.
- `each_hardware_encoder_makes_one_shown_av1_frame_a_sample` passes on AMD.
- The share itself is not offered AV1: `VideoCodec` has no `AV1`,
  `gpu_codecs()` reports H264 only, and `GpuCodec::for_share` maps nothing to
  AV1. So the app is as it was.

What was found (RX 9070 XT, driver 32.0.31041.1004, debug build):
- **The encoder is sound.**
  - AMD writes plain low-overhead OBUs: a temporal delimiter, a sequence header
    on keyframes, then one frame OBU.
  - Every sample is one newly shown frame, and the keyframe flag matches the
    frame header. ffmpeg decodes the stream, Main 4:2:0.
  - Keyframes come when asked for.
  - It follows live bitrate changes: 8 to 2 to 6 Mbps on the game clip, each
    within about a second.
  - CPU in the bench was about H264's: 55% of a core.
- **Its rate control is not H264's.**
  - It keeps `base_q_idx` fixed at 26 and moves per-block deltas instead.
  - It reads back a quantiser floor but ignores it: the output is the same
    byte for byte from 1 to 100.
  - It gives the same output in CBR, peak-constrained and unconstrained VBR.
  - Quality mode ignores the bitrate (77 Mbps whether asked for 8 or 2), so it
    cannot be used.
  - On a still picture it sends about 70-byte frames for four seconds, then
    bursts and holds 1.5 Mbps on the unchanging picture. Any bitrate change
    drops it back to 0.07 Mbps, and WebRTC changes the rate often, so the real
    cost may be lower. In the bench, a still screen sent 1.4 Mbps against
    H264's 0.18.
- **Encrypted AV1 reaches no viewer.**
  - Unencrypted, the Rust live test's viewer decoded every frame (177 of 177).
  - With encryption, a viewer with the right key got none.
  - libwebrtc's own libaom AV1 failed the same way through this SDK, so it is
    not the GPU path.
  - The server logged "sending PLI for layer lock" over and over, and the
    sender made a keyframe on every request.
- **Why, from LiveKit's sources (Oct 5 2026):**
  - LiveKit's native frame cryptor (`frame_crypto_transformer.cc` in
    webrtc-sdk, which the Rust, Flutter, Swift and Android SDKs share) leaves
    no AV1 byte unencrypted.
  - So the server can only find an AV1 keyframe through the Dependency
    Descriptor RTP header extension, which travels outside the encrypted
    payload.
  - The JS SDK adds that extension to its offer for SVC codecs
    (`ensureVideoDDExtension`).
  - The Rust SDK does not, not even rust-sdks main as of Oct 3 2026. The
    publisher's offer here had no Dependency Descriptor.
  - The pass-through encoder already fills the AV1 frame information the
    extension is built from (`passthrough_video_encoder.cpp`), so negotiating
    it may be all the Rust side lacks. That is untried.
- **Web viewers cannot have it at all:** the JS SDK's frame cryptor throws "av1
  is not yet supported for end to end encryption". The Rust SDK has no backup
  codec either, so a web viewer would see nothing.
- LiveKit's AV1 tracking issue (livekit/livekit #942) lists the Rust-based SDKs
  as not started.

What would bring it back, in order:
1. LiveKit's JS SDK encrypting AV1, without which web viewers see nothing.
2. The Rust SDK negotiating the Dependency Descriptor for AV1. It might be
   carried in `third_party` the way the frame-dropper fix is, if it comes
   before LiveKit ships it.
3. `live_gpu_av1_is_seen_with_the_key_and_by_nobody_else` passing. It is the
   check, and it fails today.
4. Then Step 3's wiring, Step 4's viewers, and the still-screen cost.

AV1 hardware decoding is no reason to hurry: GPUs from before about 2020
lack it, and older phones would decode in software.

## AV1 on the desktop: the plan as written

Written Oct 5 2026, for an agent on the user's Windows desktop, and followed
as far as "AV1: parked" says. Read the rest of this file first: AV1 follows the
H264 path almost step for step, and the decisions, setup and rules above all
hold.

### Why AV1, and why there

- AV1 compresses better than H264 constrained baseline and is royalty-free.
  Viewers support it far more widely than H265 (decision 3).
- Decision 1 still holds: **AV1 is only encoded by the GPU**, never by libaom on
  our CPU. Without a GPU AV1 encoder, AV1 is not offered.
- The laptop's GPUs cannot encode AV1. The desktop's **AMD Radeon RX 9070 XT**
  (RDNA 4) can. It is also the first AMD GPU the H264 encoder runs on; so far it
  has only run on NVIDIA and Intel.
- **Windows only.** On Linux, LiveKit's own VAAPI encoder makes H264 only, and
  its NVENC AV1 needs an RTX 40. AV1 on AMD under Linux would need a VAAPI
  encoder of our own. That is a separate task; do not start it here.

### Step 0: set up, then prove H264 on AMD

- Set up as in "Setting up (first session)". Also install ffmpeg (ffprobe
  checks streams).
- **H264 first.** Run the existing tests on AMD before writing any AV1 code:
  - `cargo test each_hardware_encoder_makes_decodable_h264 -- --ignored
    --nocapture` in `rust/`. It writes each encoder's stream to
    `GPU_ENCODER_DUMP` if that is set.
  - The live tests against a local `livekit-server --dev`
    (`live_test.rs`, `gpu_live_test.rs`), including the encryption test.
  - The bench (`bench_test.rs`) for CPU, fps and bitrate.
- Fix anything AMD's H264 encoder does differently, and record it here. On
  Intel, these turned up: three-byte start codes, keyframes nobody asked for,
  and how the quantiser floor behaved.
- **Done Oct 5 2026: AMD's H264 needed no change.** The RX 9070 XT (driver
  32.0.31041.1004) passed the encoder test, the live tests including
  encryption, and the bench, with the numbers in `TESTING.md`. Its rate
  control held a moving game clip to the target. The encoder reads low latency
  back as `-1`, which is a `VARIANT_TRUE`, not a refusal.
- The laptop's test clips are not in the repository. Make one from any 1080p60
  video: `ffmpeg -i clip.mp4 -t 3 -vf scale=1920:1080 -r 60 -pix_fmt nv12 -f
  rawvideo clip.nv12`. Then set `GPU_ENCODER_SOURCE` to it.
- The desktop has the CPU's own Radeon graphics beside the 9070 XT, and Media
  Foundation lists AMD's H264 encoder three times, all named the same and none
  carrying an adapter LUID. Each opened in a test process and made the same
  stream byte for byte, so which GPU each one is was not settled. Unlike the
  laptop's NVIDIA encoder, none refused to open.

### Step 1: is there an AV1 encoder in Media Foundation?

- List the hardware encoders whose output is `MFVideoFormat_AV1`, the way
  `hardware_h264_encoders` lists H264. Log each one's name and vendor, and note
  the AMD driver version.
- **If AMD offers no AV1 encoder there, stop and ask the user.** AV1 would then
  be reachable only through AMD's own SDK (AMF), which is a second encoder
  backend. Do not add that on your own.
- **Answered Oct 5 2026: it does.** On driver 32.0.31041.1004, a hardware
  NV12-to-AV1 listing returns one encoder, `AMDav1Encoder` (`VEN_1002`), and it
  activates. No AMF backend is needed. Asked for everything, Media Foundation
  lists no software AV1 encoder there, so nothing on the CPU can be picked up
  by mistake.

### Step 2: the encoder

- Make `encoder/media_foundation.rs` work for both codecs; do not copy it. The
  codecs differ in:
  - the output subtype;
  - the profile;
  - which encoders are listed.
- These stay as they are:
  - the asynchronous event loop;
  - NV12 input;
  - forcing keyframes;
  - live rate changes;
  - the fallback.
- Mind `CODE_STYLE.md`'s file size budget; split the file if it grows past it.
- `encoder/h264.rs` (start codes, parameter sets) stays H264-only. AV1 has no
  start codes.
- **Profile:** AV1 Main (profile 0), 8-bit 4:2:0. It is the only AV1 profile
  LiveKit's pass-through offers (`AV1Profile0` in
  `third_party/webrtc-sys/src/passthrough_video_encoder.cpp`).
- **Real time:**
  - Low-latency mode, and no frame reordering (B-picture count 0).
  - Check that every output sample is exactly one shown frame: no hidden frame
    held back for a later `show_existing_frame`, since WebRTC sends one frame
    per sample.
  - Check with `ffprobe -bsf:v trace_headers` on a dumped stream.
- **Rate control:** unconstrained VBR with a quantiser floor, as for H264. The
  floor was tuned for H264, though: `MIN_QP` 18 is on H264's 0 to 51 scale.
  - Find out what scale the AV1 encoder's QP setting uses, then measure again.
  - Target: a still window falls well under 1 Mbps at the viewer, and the moving
    clip still gets its bitrate. Do not copy 18 across.
- **Frames to LiveKit:** one `EncodedVideoFrame` per output sample, with
  `EncodedVideoCodec::AV1`. LiveKit's pass-through fixes up the bytes before
  sending them (read `third_party/webrtc-sys/src/av1_bitstream.cpp`):
  - It accepts plain OBUs, Annex B, or IVF frame headers.
  - It drops temporal delimiters and padding.
  - It puts the last sequence header back on a keyframe that lacks one.
- A frame it cannot parse is refused, and WebRTC's log says
  "PassthroughVideoEncoder received an AV1 frame that WebRTC cannot
  packetize". Watch for that line.
- **The keyframe flag** comes from `MFSampleExtension_CleanPoint`, as for H264.
  Check it against the frame header's frame type.

### Step 3: wire it in

- **Rust:**
  - `VideoCodec` gains `AV1` in `api/screenshare/types.rs`. Regenerate the
    bindings.
  - `track.rs` maps the new codec.
  - `gpu_codecs()` in `encoder/mod.rs` reports AV1 when an AV1 encoder opens.
  - `session.rs` takes the GPU path for AV1 as it does for H264; today that
    check is `settings.codec == VideoCodec::H264`.
  - `gpu_feed.rs` sends the right `EncodedVideoCodec`.
- **Fallback:** an AV1 encoder that fails to open, or fails mid-share, falls
  back to software VP9 with the toast, as H264 does. It never falls back to
  libaom.
- **Dart:**
  - `codecFromName` in `screen_share_settings.dart` takes `AV1`. Its comment
    about "an old build's AV1" changes in the same commit.
  - `codecsOffered` offers AV1 only where the GPU encodes it, on every platform,
    because no CPU encodes AV1 (decision 1).
  - The hint says only "Best for …" (decision 6).
- **Default (decision 4):** AV1 becomes the default only after Step 4 shows that
  every viewer can play it. Until then H264 stays the default where the GPU
  encodes it, and AV1 is an option.

### Step 4: can every viewer play it?

The server forwards a share as sent, without transcoding. livekit 0.9.1's Rust
SDK also has no backup codec. So a viewer that cannot decode AV1 sees nothing.

Check each of these and record the result, with the date and how you checked:
- **The Rift desktop app** (flutter_webrtc 1.6.2) on Windows, Linux and macOS.
- **Rift on the web** in Chrome, Edge, Firefox and Safari. Safari may decode AV1
  only on hardware with an AV1 decoder; check it, do not assume it.
- **The Android and iOS apps**, including an older phone.
- **With encryption**, because every share is encrypted. Decoding AV1 is not
  the same as decrypting it. Run Phase 4 again with AV1 in the Rust live test,
  then check a web viewer.

Viewers other than the Rust test need the full app and a server. Ask the user
which server to use.

### Step 5: measure and record

- **As in "Testing":**
  - CPU;
  - frames per second at the viewer;
  - keyframe on join;
  - following the bitrate;
  - fallback.
- **Quality against H264 at the same bitrate:**
  - Use luma PSNR on the same clip, as was done for H264 High.
  - Also test scrolling text.
  - Align frames before scoring, because encoders can drop frames at the start.
- **The still-screen bitrate** at the viewer.
- **Records:** add rows to `TESTING.md`, and update this file in the commit that
  makes it true. Commit locally, and **push only when the user asks.**

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
