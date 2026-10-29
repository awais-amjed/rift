# Linux zero-copy sharing (VAAPI) — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wayland shares are captured by Rift's own PipeWire stream and, on Intel
or AMD, encoded from the compositor's DMA-BUF with no CPU copy.

**Architecture:** Rust runs the ScreenCast portal (`ashpd`) and hands the PipeWire
fd and node to a stream written in C inside `librift_ffenc.so`, adapted from OBS.
Each picture comes up to Rust's `share-frames`, which sends a DMA-BUF to ffenc
(`hwmap` to VAAPI, `scale_vaapi`, `h264_vaapi`) or a memory buffer down today's
I420 path, by the feed it is for.

**Tech Stack:** C (libpipewire 0.3, EGL + GBM, libva, FFmpeg 9.0.2 libavfilter),
Rust (`ashpd` 0.13, tokio), the existing `encoder`/`gpu_feed`/`frames` modules.

**Spec:** `docs/gpu-codecs/STEP2_LINUX.md` (read it first; this plan argues from it).

## Global Constraints

- Work on branch `gpu-codecs`; commit locally per task, never push.
- Nothing new is linked into the Rust library: libpipewire, EGL, GBM and libdrm
  are linked only into `librift_ffenc.so`, which Rift opens at run time.
- Code taken from OBS (`1d4d119`) keeps its copyright header and SPDX line and
  says what Rift changed; `assets/licenses/` gains its notice.
- `RIFT_FFENC_ABI` goes from 4 to 5 once, in Task 1, and `ABI` in `ffmpeg.rs` with it.
- If the library does not load, or the portal or PipeWire refuses, the share runs
  on libwebrtc's capturer exactly as today.
- X11, Windows and NVIDIA-drawn screens are unchanged.
- Logs: `log::` in Rust, FFmpeg's log sink in C; never a restore token or fd path.
- `cargo test --release` and `flutter analyze` clean before each commit; docs in
  the commit that changes behaviour (`CALLS.md`, `TESTING.md`).

## Review Focus

- **A window resized mid-share:** the stream renegotiates its size, the picture is
  letterboxed as today, not stretched or black; ffenc rebuilds its graph (Task 5
  live step).
- **A screen none of whose modifiers import:** the stream ends up on memory
  buffers and the share keeps going (Task 3 test with `RIFT_PW_REFUSE_DMABUF`).
- **Stopping a share while a buffer is held** (in the mailbox, or inside
  `send_dmabuf`): no use after free, every buffer goes back (Task 5: twenty
  start/stop cycles on a release build, no PipeWire warnings).
- **The picker cancelled:** the share ends as cancelled at once, without a
  10-second wait and without libwebrtc asking again (Task 2 test).
- **A still screen and a new watcher:** a keyframe within about 100 ms (Task 4 test).

---

### Task 1: ffenc takes a DMA-BUF

**Files:**
- Modify: `native/ffenc/ffenc.h`, `native/ffenc/ffenc.c`, `native/ffenc/build.sh`
- Create: `native/ffenc/test_dmabuf.c`, `native/ffenc/test.sh`
- Modify: `rust/src/screenshare/encoder/ffmpeg.rs` (`ABI` to 5 only)

**Interfaces:**
- Produces (C, `ffenc.h`):
  ```c
  typedef struct RiftDmabuf {
    int32_t width, height;           // the buffer's size
    int32_t crop_x, crop_y, crop_width, crop_height;  // 0,0,0,0 = whole buffer
    uint32_t drm_format;              // DRM fourcc (XRGB8888, ARGB8888, XBGR8888, ABGR8888)
    uint64_t modifier;
    int32_t planes;
    int32_t fds[4]; uint32_t offsets[4]; uint32_t strides[4];
    int32_t transform;                // SPA_META_TRANSFORMATION_*: how to turn it upright
  } RiftDmabuf;
  #define RIFT_FFENC_IMPORT_FAILED (-0x52494D50)  // 'RIMP': this format+modifier won't map
  typedef struct RiftRect { int32_t x, y, width, height; } RiftRect;
  // `place`: where the picture goes inside the encoded size, the rest black
  // (Rust's `resolution::letterbox`); NULL fills it.
  int32_t rift_ffenc_send_dmabuf(RiftFfenc*, const RiftDmabuf*, const RiftRect* place,
                                 int64_t timestamp_us, int32_t keyframe);
  int32_t rift_ffenc_repeat(RiftFfenc*, int64_t timestamp_us, int32_t keyframe);
  ```
  `send_dmabuf` returns once `scale_vaapi`'s output is synced, so the caller may
  give the buffer back; the fds stay the caller's. `repeat` encodes the last
  scaled picture again (`AVERROR(EAGAIN)` if there is none). VAAPI only:
  `AVERROR(ENOSYS)` for any other encoder.

- [ ] **Step 1: Write the failing test** `native/ffenc/test_dmabuf.c`: opens
  `h264_vaapi` on `$RIFT_RENDER_NODE` (default `/dev/dri/renderD129`, the Iris Xe
  here) at 1280x720, makes a 1920x1080 BGRX VA surface, fills it with a known
  colour through `vaDeriveImage`, exports it with `vaExportSurfaceHandle`
  (`VA_SURFACE_ATTRIB_MEM_TYPE_DRM_PRIME_2`), sends it 60 times with
  `rift_ffenc_send_dmabuf` (keyframe on the first), then `rift_ffenc_repeat` 5
  times, and drains `rift_ffenc_receive`. Asserts: 65 packets, the first a
  keyframe, each starting with an Annex B start code; one send with
  `modifier = 0xdeadbeef` returns `RIFT_FFENC_IMPORT_FAILED`; a send with a crop of
  960x540 still returns 0; a send with `place = {160, 0, 960, 720}` also returns 0;
  a 1920x1080 buffer with `transform = SPA_META_TRANSFORMATION_90` into a
  1080x1920 encoder returns 0 (what the pictures look like is checked in Task 5's
  live steps).
- [ ] **Step 2:** `native/ffenc/test.sh OUT_DIR` builds the test against
  `OUT_DIR/librift_ffenc.so` with `-lva -lva-drm` and runs it.
  Run: `native/ffenc/test.sh ~/tmp/rift-scratch/ffenc-build` — Expected: link fails
  on `rift_ffenc_send_dmabuf`.
- [ ] **Step 3: Implement.** `build.sh`: replace `--disable-avfilter` with
  `--enable-avfilter --enable-filter=buffer,buffersink,hwmap,transpose_vaapi,scale_vaapi,pad_vaapi`
  (Linux only), add `libavfilter.a` to the link, add `ffenc.h`'s new test files to
  the stamp. `ffenc.c`: a lazily built filter graph `buffer → hwmap
  (derive VAAPI from the encoder's device) → transpose_vaapi (only for a transform,
  directions mapped as OBS's `push_rotation` and `get_buffer_flip` turn them) → scale_vaapi=place.w:place.h:format=nv12 →
  pad_vaapi=W:H:place.x:place.y:black (left out when `place` fills) → buffersink`,
  rebuilt when the input size, format, crop, transform or place changes; a driver
  whose video processing refuses the turn is logged once and gets the picture
  unturned; the DMA-BUF wrapped as an
  `AV_PIX_FMT_DRM_PRIME` frame (`AVDRMFrameDescriptor`, one object per fd) with
  `crop_*` set; an import error from `hwmap` (`av_buffersrc_add_frame`/sink
  pull failing with `EINVAL`/`ENOSYS`/`EIO`) becomes `RIFT_FFENC_IMPORT_FAILED`;
  the sink's frame is synced with `vaSyncSurface` before returning, kept as `enc->last` for `repeat`, then sent to
  the encoder (h264_vaapi takes frames from the sink's pool on the same device).
  Bump `RIFT_FFENC_ABI` to 5.
- [ ] **Step 4:** Run `native/ffenc/test.sh …` — Expected: `ok: 65 packets`. Then
  `cd rust && cargo test --release encoder` — Expected: pass (ABI 5 matches).
- [ ] **Step 5: Commit** `native/ffenc/*`, `rust/src/screenshare/encoder/ffmpeg.rs`
  — "Let ffenc encode a DMA-BUF through VAAPI".

### Task 2: The portal, from Rust

**Files:**
- Modify: `rust/Cargo.toml` (`ashpd = { version = "0.13", default-features = false, features = ["tokio", "screencast"] }` under `[target.'cfg(target_os = "linux")'.dependencies]`)
- Create: `rust/src/screenshare/portal.rs` (gated `#[cfg(target_os = "linux")]` at its `mod` line in `screenshare/mod.rs`)
- Modify: `assets/licenses/rust_crates.txt` via `scripts/generate_licenses.sh`

**Interfaces:**
- Produces:
  ```rust
  pub(crate) enum PortalKind { Screen, Window }
  pub(crate) enum PortalError { Cancelled, Unavailable(String) }
  pub(crate) struct PortalSession { pub fd: OwnedFd, pub node_id: u32, pub size: Option<Size>,
                                    pub restore_token: Option<String>, /* keeps the session open */ }
  pub(crate) async fn open(kind: PortalKind, restore_token: Option<&str>, cursor: bool)
      -> Result<PortalSession, PortalError>;
  pub(crate) fn error_of(response: ashpd::Error) -> PortalError;  // pure mapping
  ```
  Cursor `Embedded` when `cursor`, else `Hidden`; `persist_mode` `ExplicitlyRevoked`
  only when a token was given (so a test's token renews), else `DoNot`. Dropping
  the session closes it.

- [ ] **Step 1: Write the failing tests** in `portal.rs`:
  `a_cancelled_picker_is_cancelled` (`error_of(ashpd::Error::Response(ResponseError::Cancelled))`
  is `Cancelled`), `a_missing_portal_is_unavailable` (a `zbus` "ServiceUnknown"
  error maps to `Unavailable`), and `#[ignore] live_portal_restores_a_screen`: reads
  a token from `RIFT_PORTAL_TOKEN`, opens `Screen`, asserts `node_id > 0`, a valid
  fd, and a new token, which it writes to `RIFT_PORTAL_TOKEN_OUT`.
- [ ] **Step 2:** `cargo test --release portal` — Expected: fails to compile (no module).
- [ ] **Step 3: Implement** `open`/`error_of` with ashpd's `Screencast` proxy
  (create_session, select_sources, start, open_pipe_wire_remote).
- [ ] **Step 4:** `cargo test --release portal` — PASS. Seed a token once by hand
  (a tiny ignored test `live_portal_seed_token` that opens with no token, the
  owner or I answer the picker), then
  `RIFT_PORTAL_TOKEN=… cargo test --release live_portal -- --ignored` — PASS with no picker shown.
- [ ] **Step 5:** `scripts/generate_licenses.sh` (must pass the licence check);
  commit `rust/Cargo.toml rust/Cargo.lock rust/src/screenshare/{mod,portal}.rs assets/licenses/rust_crates.txt`
  — "Open the ScreenCast portal from Rust".

### Task 3: The PipeWire stream, from OBS

**Files:**
- Create: `native/ffenc/pipewire.c` (from OBS `plugins/linux-pipewire/pipewire.c`), `native/ffenc/dmabuf_caps.c` (from OBS `libobs-opengl/gl-egl-common.c`: `query_dmabuf_formats`, `query_dmabuf_modifiers`, on a GBM device for the render node)
- Modify: `native/ffenc/ffenc.h`, `native/ffenc/build.sh` (compile both, link `-lpipewire-0.3 -lEGL -lgbm -ldrm`; pipewire's cflags from pkg-config), `linux/CMakeLists.txt` (new sources in `DEPENDS`), `.github/workflows/release.yml` and `README.md` (packages `libpipewire-0.3-dev libegl-dev libgbm-dev libdrm-dev`; Arch `pipewire mesa libdrm`), `assets/licenses/` (new `obs_studio.txt`, listed in `README.txt`)
- Create: `rust/src/screenshare/pw_stream.rs` (Linux-gated; symbols from the same library `ffmpeg.rs` opens — move its `Library` handle behind a `pub(super) fn library() -> Result<&'static Library, String>`)

**Interfaces:**
- Produces (C):
  ```c
  typedef enum { RIFT_PW_DMABUF = 1, RIFT_PW_MEMORY = 2 } RiftPwBuffers;
  typedef struct RiftPwPicture {
    RiftDmabuf dmabuf;               // when buffers == RIFT_PW_DMABUF
    const uint8_t* data; int32_t stride;  // when RIFT_PW_MEMORY (BGRx/BGRA, cropped origin)
    int32_t buffers; int32_t width, height;  // after crop
    int64_t pts_ns;
    void* held;                      // the pw_buffer, for rift_pw_release
  } RiftPwPicture;
  typedef struct RiftPwCallbacks {
    void* user;
    void (*picture)(void* user, const RiftPwPicture*);   // PipeWire's thread; must not block
    void (*state)(void* user, int32_t state, const char* error);  // 0 streaming, 1 paused, 2 ended
  } RiftPwCallbacks;
  RiftPwStream* rift_pw_open(int32_t fd, uint32_t node_id, int32_t max_fps, const char* render_node,
                             int32_t buffers, const RiftPwCallbacks*, char* error, size_t error_len);
  void rift_pw_set_buffers(RiftPwStream*, int32_t buffers);          // renegotiates
  void rift_pw_drop_modifier(RiftPwStream*, uint32_t drm_format, uint64_t modifier);  // OBS's renegotiate
  void rift_pw_release(RiftPwStream*, void* held);                    // any thread
  void rift_pw_close(RiftPwStream*);                                  // returns every held buffer
  ```
  Formats offered: BGRx, BGRA, RGBx, RGBA only (10-bit and HDR refused). An
  explicit-sync buffer (`SPA_META_SyncTimeline`, OBS's handling) has its acquire
  point waited on (`drmSyncobjTimelineWait`, on PipeWire's thread, before the
  picture goes up) and its release point signalled in `rift_pw_release`. The
  transform meta is passed up as OBS reads it; `width`/`height` are the upright
  size (swapped for a quarter turn).
  Keeps OBS's newest-buffer rule: older dequeued buffers go back at once; at most
  two held by Rust. With no modifier left for a format, it offers memory buffers.
  `RIFT_PW_REFUSE_DMABUF=1` in the environment makes it offer memory only (test hook).
- Produces (Rust, `pw_stream.rs`):
  ```rust
  #[repr(C)] pub(crate) struct RiftDmabuf { /* field for field as ffenc.h */ }
  pub(crate) enum PwBuffers { DmaBuf, Memory }
  pub(crate) struct PwPicture { /* owns `held`; Drop calls rift_pw_release */ }
  impl PwPicture { pub fn size(&self) -> Size; pub fn dmabuf(&self) -> Option<&RiftDmabuf>;
                   pub fn memory(&self) -> Option<(&[u8], u32)>; pub fn pts_us(&self) -> i64; }
  pub(crate) enum PwEvent { Streaming, Paused, Ended(String) }
  pub(crate) struct PwStream;  // Drop closes
  impl PwStream {
      pub fn open(session: &PortalSession, max_fps: u32, render_node: Option<&str>, buffers: PwBuffers,
                  pictures: Putter<PwPicture>, events: Box<dyn Fn(PwEvent) + Send>) -> Result<PwStream, String>;
      pub fn set_buffers(&self, buffers: PwBuffers);
      pub fn drop_modifier(&self, drm_format: u32, modifier: u64);
  }
  ```

- [ ] **Step 1: Write the failing tests** in `pw_stream.rs`, `#[ignore]`, using
  Task 2's token: `live_pw_stream_gives_dmabufs` (60 pictures in 5 s on a moving
  screen, all `dmabuf().is_some()`, size equals the screen), `live_pw_stream_switches_to_memory`
  (after `set_buffers(Memory)`, within 1 s every picture has `memory()`, with
  `stride >= width * 4`), `live_pw_stream_refused_dmabuf_gives_memory`
  (`RIFT_PW_REFUSE_DMABUF=1`), and `live_pw_stream_closes_holding_pictures`
  (hold 2 pictures, drop the stream first, then the pictures: no crash, no
  PipeWire warning in the log).
- [ ] **Step 2:** `cargo test --release live_pw -- --ignored --test-threads=1` — fails to compile.
- [ ] **Step 3: Implement** the C stream from OBS's functions named in the spec,
  OBS types replaced by Rift's (`RiftPwStream` holding the thread loop, context,
  core, stream, format info, renegotiate event); the GBM/EGL caps query; the Rust
  wrapper (the `picture` callback builds a `PwPicture` and `put`s it; a picture
  `put` returns is dropped, so released).
- [ ] **Step 4:** Run the four live tests — PASS; `native/ffenc/test.sh` still PASS.
- [ ] **Step 5: Commit** — "Run the share's PipeWire stream in ffenc, from OBS's".

### Task 4: The encoder takes a DMA-BUF picture, and repeats on a still screen

**Files:**
- Modify: `rust/src/screenshare/encoder/{mod,worker,ffmpeg}.rs`, `rust/src/screenshare/gpu_feed.rs`, `rust/src/screenshare/latest.rs` (`take_timeout`)

**Interfaces:**
- Consumes: `rift_ffenc_send_dmabuf`, `rift_ffenc_repeat`, `RIFT_FFENC_IMPORT_FAILED` (Task 1); `PwPicture` (Task 3).
- Produces:
  ```rust
  pub(crate) enum EncoderInput { Nv12(Nv12Frame), DmaBuf(PwPicture) }   // encoder/mod.rs
  // Session::encode(&mut self, input: &EncoderInput, keyframe: bool) -> Result<(), EncodeError>
  pub(super) enum EncodeError { Failed(String), ImportFailed { drm_format: u32, modifier: u64 } }
  pub(super) trait Session { …; fn repeat(&mut self, timestamp_us: i64, keyframe: bool) -> Result<(), String>; fn takes_dmabuf(&self) -> bool; }
  impl GpuEncoder { pub fn submit_input(&self, input: EncoderInput); pub fn takes_dmabuf(&self) -> bool;
                    pub fn on_import_failed(&self, f: Box<dyn Fn(u32, u64) + Send + Sync>); }
  Picture::DmaBuf(PwPicture)   // gpu_feed.rs, sent whole; the gate still applies
  pub(super) const REPEAT_AFTER: Duration = Duration::from_secs(1);
  pub(super) const KEYFRAME_POLL: Duration = Duration::from_millis(100);
  ```
  `ImportFailed` does not fail the encoder: the picture is dropped and
  `on_import_failed` is told (the capture drops that modifier). The worker waits
  with `take_timeout(KEYFRAME_POLL)`; with no picture it repeats at once if the
  sink wants a keyframe, else after `REPEAT_AFTER` of quiet.

- [ ] **Step 1: Write the failing tests** in `worker.rs`, with the fake `Session`
  its tests already use: `a_still_screen_is_repeated_each_second` (no input for
  2.2 s → 2 repeats), `a_keyframe_request_on_a_still_screen_repeats_at_once`
  (sink wants a keyframe → a keyframe repeat within 150 ms),
  `an_import_failure_drops_the_picture_and_keeps_the_encoder` (fake returns
  `ImportFailed{..}` → `failed()` stays false, callback told the format and
  modifier). `latest.rs`: `take_timeout_returns_none_when_quiet`.
- [ ] **Step 2:** `cargo test --release worker latest` — FAIL.
- [ ] **Step 3: Implement**; NVENC's session `takes_dmabuf() == false` and errors on
  `DmaBuf` input; VAAPI's passes it to `send_dmabuf`, `repeat` to `rift_ffenc_repeat`.
- [ ] **Step 4:** `cargo test --release` — PASS; plus `#[ignore] live_vaapi_encodes_the_stream`
  in `gpu_live_test.rs` (Task 3's stream into a VAAPI `GpuEncoder` for 3 s: ≥ 150
  packets at 60 fps on a moving screen) — PASS.
- [ ] **Step 5: Commit** — "Let the GPU encoder take a DMA-BUF picture and repeat a still one".

### Task 5: Wayland shares on Rift's own stream

**Files:**
- Create: `rust/src/screenshare/capture_pw.rs` (Linux-gated: the capture loop for this capturer)
- Modify: `rust/src/screenshare/capture.rs` (`run` hands off to `capture_pw::run` on Wayland, falls back to libwebrtc on `PortalError::Unavailable` or a stream that will not open), `frames.rs` (`SendableFrame` becomes `enum Raw { Desktop(DesktopFrame), Pw(PwPicture) }`), `encoder/ffmpeg.rs` (on Wayland with the new capturer, VAAPI candidates before NVENC), `CALLS.md`, `TESTING.md`

**Interfaces:**
- Consumes: Tasks 2–4.
- Produces:
  ```rust
  pub(crate) fn buffers_for(feed: &Feed) -> PwBuffers  // pure: DmaBuf only for Feed::Gpu whose encoder takes_dmabuf
  pub(crate) fn on_wayland() -> bool   // WAYLAND_DISPLAY set and XDG_SESSION_TYPE == "wayland"
  ```
  Per picture on `share-frames`: the feed's wanted buffers differ from the
  picture's → `set_buffers` (once per change) and drop it; `DmaBuf` + `Feed::Gpu`
  → `Picture::DmaBuf` at any size, ffenc scaling it, with `place` from
  `resolution::letterbox(native, target)`; `Memory` → today's ARGB/I420 path (crop origin and stride
  from `memory()`). `PwEvent::Paused` → `on_paused(true)` (now on Linux too),
  `Streaming` → `on_paused(false)`, `Ended` → `SourceClosed`. The 10-second
  first-picture limit starts after the portal's Start returns. Cancelled → the
  share fails as cancelled. Window shares open the portal with `portal_choice`;
  screen shares with none.

- [ ] **Step 1: Write the failing tests** in `capture_pw.rs`: `buffers_for` table
  (Raw → Memory; Gpu with VAAPI → DmaBuf; Gpu with NVENC → Memory), and
  `on_wayland` from given env values (take the env as parameters:
  `on_wayland_from(wayland_display: Option<&str>, session_type: Option<&str>)`).
- [ ] **Step 2:** `cargo test --release capture` — FAIL.
- [ ] **Step 3: Implement** the hand-off and the loop; `CALLS.md`: the Linux
  capture section says Wayland shares run on Rift's own stream (portal from Rust,
  stream from OBS's code in ffenc, DMA-BUF to VAAPI, memory buffers for VP9 and
  NVENC, libwebrtc's capturer when any of it refuses), with today's measurement.
- [ ] **Step 4: Live, on this laptop** (release build; `cargo build --release
  --target x86_64-unknown-linux-gnu` before `flutter build linux --release`;
  Rift as a native Wayland window), with a web viewer and an app viewer:
  1. Whole screen, 1080p60 moving pattern, `threadtop` 20 s: under ~3% of a core
     for the share's threads (record beside step 0's table in `PLAN.md`).
  2. A window: picked once, no second picker, sound still matched; resized
     (letterboxed, no stretch); minimised (watchers told paused); closed (share ends).
  3. Quality changed to VP9 and back mid-share: picture continues each way.
  4. Encoder made to fail (`test_hooks::FAIL_AFTER` through a debug build) → VP9
     on memory buffers.
  5. Twenty start/stop cycles: no crash, no stuck share, no PipeWire warnings.
  6. KDE VM: shares (memory buffers, no VAAPI GPU), or falls back cleanly.
  `TESTING.md` row updated with what was checked and what was not.
- [ ] **Step 5: Commit** — "Share Wayland screens from Rift's own PipeWire stream".
