# Zero-copy sharing from an NVIDIA screen — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Wayland share from a screen the NVIDIA card draws reaches NVENC with the
picture never on the CPU, on for everyone, with one settings switch back to the old
path.

**Architecture:** Below `rift_ffenc_send_dmabuf`, a new `nvenc_gl.c` imports the
DMA-BUF into EGL, draws it into two GL textures as NV12 with one shader pass, and
CUDA copies those into the CUDA frame `h264_nvenc` takes. Everything above stays:
the portal, the stream, the rate gate, the repeat, the fall backs. A pure Rust rule
decides when NVENC goes first and takes DMA-BUFs.

**Tech Stack:** C (EGL, GLES 3 through `eglGetProcAddress`, CUDA through `ffnvcodec`,
FFmpeg 9.0.2), PipeWire 1.2 SPA headers, Rust (`encoder`, `capture_pw`), Dart
(`AppCubit`, settings).

**Spec:** `docs/gpu-codecs/STEP2_NVIDIA.md` (read it first; this plan argues from it).
References are cloned at the commits it names: gpu-screen-recorder `099a55b`,
Sunshine `a679b05`. The throwaway test that proved the route is
`spike_gl.c` in the scratch folder `spike-vk`, with `check.py` beside it.

## Global Constraints

- Branch `gpu-codecs`; commit locally per task, never push. Stage named paths. No
  attribution lines. Commit messages through the scratch `commit-msg.txt`.
- **The share must not make the sharer's game lag or stutter, and watchers must not
  see stutter or lag (owner).** No dropped, black, torn or stale picture, no lost
  cursor, no second picker.
- Rift still starts and shares on a machine without any of this. `librift_ffenc.so`
  gains no new hard library dependency: every GL function comes from
  `eglGetProcAddress`, CUDA from `ffnvcodec`'s loader.
- Intel/AMD's VAAPI path is unchanged. X11 and Windows are unchanged: new code in
  `ffenc.c` is inside `#if defined(__linux__)`, `nvenc_gl.c` is built only in
  `build.sh`'s Linux branch.
- Colours are BT.601 (SMPTE 170M), limited range, as `ffenc.c` tells viewers.
- `RIFT_FFENC_ABI` and `ABI` in `ffmpeg.rs` go from 7 to 8 once, in Task 3.
- Code taken from gsr or Sunshine keeps its copyright header and says what Rift
  changed; `assets/licenses/` gains gsr's and Sunshine's notices (both GPL-3.0).
- No import cache without the owner's word. A missed target is reported with numbers.
- Picker steps and BIOS changes are the owner's: hand over steps and wait. Installing a
  package: ask with the exact command. Never kill or launch the owner's Rift.
- `cargo test --release` and `flutter analyze` clean before each commit; `CALLS.md`,
  `TESTING.md` and `PLAN.md` change in the commit that changes behaviour.

## Decisions this plan makes (the builder's, per the spec)

- **Map per picture, not kept mapped.** gsr keeps the textures mapped; Sunshine maps
  for each picture. CUDA's documentation makes the map the point where GL's work is
  finished for CUDA, drawing into a mapped resource is undefined, and the spike
  measured no cost difference. So Sunshine's way. This replaces the one line of the
  spec that says "kept mapped", and Task 2 corrects it.
- **One shader program, always `GL_TEXTURE_EXTERNAL_OES`.** External sampling accepts
  every import and does nothing extra for RGB, so external-only modifiers need no
  second path. If the bench is slower than the spike's 0.6 ms a picture, add the
  `GL_TEXTURE_2D` program the spec allows.
- **No flip anywhere.** Row 0 of the buffer maps to GL's `y = 0` of the textures, and
  CUDA copies array row 0 to the frame's top row, so the shader's mapping is straight.
  Task 5 proves it on a real picture.
- **`device` in `RiftFfencConfig` turns the GL path on for NVENC.** Non-NULL names the
  render node; NULL means memory as today.
- **Never `eglTerminate`.** The EGL display is shared across the process; only the
  context is destroyed.

## Review Focus

- **A game holding the GPU at 100%:** the share keeps its rate and no picture waits
  long on the sync point or the map; a late picture is dropped by the rate gate, not
  queued (Task 7, benchmark with timings).
- **Quitting Rift during a share on this path:** the process exits at once, with no
  hang in NVIDIA's libraries (Task 3, bench leaves an encoder open and returns from
  `main` under a timeout).
- **A share moved between kinds of buffer on one session:** VP9 and back, or every
  modifier refused, leaves a clean picture and no CUDA error (Task 5, live).
- **A machine with NVENC where EGL or GL will not open:** the library still loads and
  NVENC takes memory as today (Task 3, `RIFT_FFENC_NO_GL=1` and a `readelf` check).
- **A window of odd size, letterboxed or cropped:** no green or coloured edge from the
  half-size UV plane (Task 2, odd crop and placement cases).

---

### Task 1: Explicit sync in every build, and a way to turn it off

**Files:**
- Modify: `native/ffenc/build.sh`, `native/ffenc/pipewire.c`,
  `rust/src/screenshare/pw_stream.rs` (test only), `.github/workflows/release.yml`
  (only if a package is missing), `docs/gpu-codecs/STEP2_LINUX.md`

**Interfaces:**
- Produces: `RIFT_PW_NO_TIMELINE=1` in the environment leaves the timeline out of the
  negotiation, for a test. The log line `pipewire: the compositor syncs explicitly`
  (exists) says which way a share went.

- [ ] **Step 1: Fetch PipeWire 1.2's SPA headers in `build.sh`**

Fetch `https://gitlab.freedesktop.org/pipewire/pipewire/-/archive/1.2.7/pipewire-1.2.7.tar.gz`
through `fetch` with a pinned sha256, as nv-codec-headers is. Copy `spa/include` to
`$prefix/include/spa-1.2` and put `-I$prefix/include/spa-1.2` before
`pkg-config --cflags libpipewire-0.3`. Linux branch only.

- [ ] **Step 2: Remove the version gate in `pipewire.c`**

Delete every `#if PW_CHECK_VERSION(1, 2, 0)` and its `#endif`, and replace the comment
above the first with why the headers are always there. Add the `RIFT_PW_NO_TIMELINE`
check beside `RIFT_PW_REFUSE_DMABUF`: when set, `s->explicit_sync` stays false.

- [ ] **Step 3: Build in the Ubuntu 24.04 builder**

Run: the scratch `linux-build/build.sh`, then in its output
`readelf -Ws --dyn-syms librift_ffenc.so | command grep -i sync`.
Expected: it links there against PipeWire 1.0's library with `-z defs`, which proves no
symbol newer than 1.0 is needed, and `SPA_META_SyncTimeline` code is in the object.
Add any missing package to `release.yml` in the same commit.

- [ ] **Step 4: See which way GNOME 50 on NVIDIA goes**

Ask the owner to reseed the portal token (a picker step). With the moving picture on
screen, run:
`RIFT_RENDER_NODE=/dev/dri/renderD128 cargo test --release live_pw_stream_gives_dmabufs -- --ignored --nocapture`
Expected: DMA-BUFs arrive. Record whether the log says the compositor syncs explicitly,
the modifier it chose, and how long `wait_timeline_point` takes (add a timing to the
log at debug level; it runs on PipeWire's thread and must stay short).

- [ ] **Step 5: Commit**

Stage `native/ffenc/build.sh native/ffenc/pipewire.c` and the doc: in `STEP2_LINUX.md`,
the *Explicit sync* lines now say every build has it, and what this screen negotiated.

---

### Task 2: The GL path, on its own

**Files:**
- Create: `native/ffenc/nvenc_gl.h`, `native/ffenc/nvenc_gl.c`,
  `native/ffenc/nvenc_gl_geometry.h`, `native/ffenc/nvenc_gl_geometry.c`,
  `native/ffenc/test_nvenc_geometry.c`
- Modify: `native/ffenc/test.sh`, `native/ffenc/build.sh`, `linux/CMakeLists.txt`
  (`DEPENDS`), `docs/gpu-codecs/STEP2_NVIDIA.md` (the "kept mapped" line),
  `.github/workflows/release.yml` (`libgles-dev`, for the headers)

**Interfaces:**
- Produces, inside the library only (`nvenc_gl.h`):
  ```c
  typedef struct NvencGl NvencGl;
  // EGL display and surfaceless GLES 3 context on `render_node`, the CUDA context
  // on the same card, FFmpeg's CUDA device on that context, an NV12 CUDA pool of
  // width x height, and the textures registered. Makes the context current on the
  // calling thread. NULL with why in `error`.
  NvencGl* nvenc_gl_open(const char* render_node, int width, int height,
                         char* error, size_t error_len);
  AVBufferRef* nvenc_gl_frames(NvencGl* gl);
  // Makes the context current if it is not, imports `buf`, draws, maps, copies, syncs,
  // unmaps. Returns with `out` holding a frame from the pool and the buffer no longer
  // needed. 0, RIFT_FFENC_IMPORT_FAILED, or a negative FFmpeg error.
  int nvenc_gl_run(NvencGl* gl, const RiftDmabuf* buf, const RiftRect* place,
                   AVFrame* out);
  void nvenc_gl_free(NvencGl** gl);
  ```
- Produces (`nvenc_gl_geometry.h`, no GL or FFmpeg includes):
  ```c
  // The rectangle `place` covers in plane 0 (Y) or 1 (UV, half size), rounded outward.
  // NULL place fills the plane.
  RiftRect nvenc_gl_plane_rect(const RiftRect* place, int out_w, int out_h, int plane);
  // Texture coordinates of the output's top-left, top-right, bottom-left and
  // bottom-right, with the crop applied and the turn undone.
  void nvenc_gl_source_uv(const RiftDmabuf* buf, float uv[4][2]);
  ```

- [ ] **Step 1: Write the geometry test `test_nvenc_geometry.c`**

Plain C with `assert`, compiled alone by `test.sh`:
- 1920x1080, place `{0,140,1920,800}`: plane 0 is the same; plane 1 is `{0,70,960,400}`.
- Place `{1,1,101,51}`: plane 1 is `{0,0,51,26}`.
- NULL place: plane 0 `{0,0,1920,1080}`; plane 1 `{0,0,960,540}`.
- 1000x500 buffer, no crop, the output's top-left samples: transform 0 → `(0,0)`;
  1 → `(0,1)`; 2 → `(1,1)`; 3 → `(1,0)`; 4 → `(1,0)`. `turn_of` in `dmabuf.c` is the
  authority for 1–7: if a case disagrees with it, follow `turn_of` and say so.
- Crop `{100,50,500,250}` with transform 0: top-left `(0.1,0.1)`, bottom-right
  `(0.6,0.6)`.

- [ ] **Step 2: Run it to see it fail**

Run: `native/ffenc/test.sh <out>`. Expected: compile failure, no `nvenc_gl_geometry.h`.

- [ ] **Step 3: Implement the geometry**

- [ ] **Step 4: Implement `nvenc_gl.c`**

Adapt `spike_gl.c`'s proven order, and take from gsr: the CUDA device by PCI bus id
(`src/cuda.c`), the display (`src/egl.c`: `EGL_PLATFORM_DEVICE_EXT` on the render node's
device, falling back to GBM as `dmabuf_caps.c` opens it), the import with and without
modifiers (`gsr_pipewire_video_create_egl_image`), and FFmpeg's CUDA device on that
context (`src/encoder/video/nvenc.c`). Values the plan pins:
- Textures `GL_R8` (full size) and `GL_RG8` (half size), registered with
  `cuGraphicsGLRegisterImage`, one framebuffer each.
- Fragment shaders with `samplerExternalOES`, BT.601 limited, matching libyuv:
  `Y = 16 + 65.481R + 128.553G + 24.966B`, `U = 128 - 37.797R - 74.203G + 112B`,
  `V = 128 + 112R - 93.786G - 18.214B`, with R, G, B in 0–1 and the results over 255.
- UV drawn at half size samples with one bilinear fetch at each UV texel's centre.
- Outside `place`: clear Y to 16/255, UV to 128/255.
- Per picture: `eglCreateImage` → bind → draw plane 0 then 1 → `glFlush` → destroy the
  image → `cuGraphicsMapResources` → `cuGraphicsSubResourceGetMappedArray` ×2 →
  `cuMemcpy2DAsync` ×2 → `cuStreamSynchronize` → unmap → return. Import errors (no image,
  or `glGetError` after binding) return `RIFT_FFENC_IMPORT_FAILED`.
- Time the map and the sync together and log the worst every few seconds at debug level.

Add `nvenc_gl.c` and `nvenc_gl_geometry.c` to the Linux link in `build.sh`, with no new
`-l`. Keep gsr's copyright header and say what changed. Replace "kept mapped" in the spec
with the decision above.

- [ ] **Step 5: Run the geometry test**

Run: `native/ffenc/test.sh <out>`. Expected: geometry passes. VAAPI's `test_dmabuf`
cannot run on this screen, so `test.sh` runs each test only where its encoder opens.

- [ ] **Step 6: Commit**

---

### Task 3: ffenc takes DMA-BUFs for NVENC

**Files:**
- Modify: `native/ffenc/ffenc.h`, `native/ffenc/ffenc.c`, `native/ffenc/dmabuf_caps.c`,
  `native/ffenc/dmabuf_caps.h`, `native/ffenc/pipewire.c`,
  `rust/src/screenshare/encoder/ffmpeg.rs`, `rust/src/screenshare/pw_stream.rs`,
  `assets/licenses/` (gsr, Sunshine)
- Create: `native/ffenc/test_nvenc_dmabuf.c`, `native/ffenc/check_nvenc.py`
- Modify: `native/ffenc/test.sh`

**Interfaces:**
- Consumes: `nvenc_gl_*` (Task 2).
- Produces (`ffenc.h`, ABI 8):
  ```c
  // In RiftFfencConfig.device's comment: for NVENC, the render node of the card whose
  // screen it encodes, which opens its EGL and CUDA side; NULL takes memory only.
  // 1 when rift_ffenc_send_dmabuf works on this encoder.
  RIFT_FFENC_EXPORT int32_t rift_ffenc_takes_dmabuf(const RiftFfenc* enc);
  // rift_pw_open gains, after `render_node`: int32_t external_modifiers
  // (1 offers modifiers EGL imports as external only, for NVENC's GL path).
  ```
  `dmabuf_caps_query` gains `int include_external`.
- Produces (env): `RIFT_FFENC_NO_GL=1` makes `nvenc_gl_open` fail, for a test.

- [ ] **Step 1: Write `test_nvenc_dmabuf.c` and `check_nvenc.py`**

The bench draws into GBM DMA-BUFs with its own GLES context (`spike_gl.c`'s drawing,
`-lGLESv2` for the test only), opens `h264_nvenc` with `device` set, writes the stream to
a file, and prints the CPU and time a picture for `send_dmabuf` as `test_dmabuf.c` does.
`check_nvenc.py` decodes it with the system `ffmpeg` and asserts, within ±4 of each value:
- Quadrants at Y,U,V: red `81,90,240`; green `145,54,34`; blue `41,240,110`; gray `125,128,128`;
  red is top-left.
- 660 pictures at 1080p, a moving bar: each decoded picture's bar is where its picture
  number puts it (0 stale).
- Same cases on both a `0x606…` and a compressed `0xe08…` modifier, in XRGB8888 and
  XBGR8888.
- 2560x1440 scaled into 1920x1080; a 1000x800 buffer letterboxed with its black bars
  at Y,U,V `16,128,128`; an odd crop with place `{1,1,101,51}`, with no chroma beyond ±4
  outside the place.
- `transform` 1: the quadrants turn as `turn_of` says.
- `rift_ffenc_repeat` after a picture gives a decoded picture equal to it, and a keyframe
  when asked.
- `rift_ffenc_send` (memory NV12) on the same open encoder, then DMA-BUF again: both right.
- With `RIFT_FFENC_NO_GL=1`: the open succeeds, `rift_ffenc_takes_dmabuf` is 0,
  `rift_ffenc_send_dmabuf` is `AVERROR(ENOSYS)`, and memory pictures encode.
- A run that returns from `main` with an encoder open exits within 5 s, under `timeout`.

- [ ] **Step 2: Run it to see it fail**

Run: `native/ffenc/test.sh <out>`. Expected: `rift_ffenc_takes_dmabuf` undefined.

- [ ] **Step 3: Wire `ffenc.c`**

In `rift_ffenc_open`, for `API_NVENC` with `device` set: `nvenc_gl_open`, and on success
`enc->frames` is its pool so `open_codec` opens on CUDA frames. If either fails, log a
warning and open as today. Memory pictures then go through the existing
`av_hwframe_transfer_data` branch. `rift_ffenc_send_dmabuf` and `rift_ffenc_repeat` take
`enc->gl` as they take VAAPI, sharing `send_gpu` and `enc->last`. `rift_ffenc_close`
frees the codec first, then `enc->last`, then the GL path. The exit handler still frees
only the codec.

- [ ] **Step 4: External modifiers through `dmabuf_caps_query` and `rift_pw_open`**

`pipewire.c` keeps `external_modifiers` in its stream and passes it on each query.

- [ ] **Step 5: Bump the ABI, update the Rust symbols**

`ABI` to 8; `PwStream::open` gains `external_modifiers: bool`, passed `false` everywhere
for now; `takes_dmabuf` in `ffmpeg.rs` asks the new symbol (VAAPI answers 1).

- [ ] **Step 6: Run the bench**

Run: `native/ffenc/test.sh <out>`. Expected: all pass; about 0.6 ms a picture before NVENC
and CPU near the spike's. Run `readelf -d <out>/librift_ffenc.so | command grep NEEDED`:
no `libGLESv2` or `libGL`.

- [ ] **Step 7: `cargo test --release`, commit**

---

### Task 4: Which GPU encodes, and telling the stream

**Files:**
- Create: `rust/src/screenshare/encoder/gpu_choice.rs`
- Modify: `rust/src/screenshare/encoder/ffmpeg.rs`, `rust/src/screenshare/encoder/mod.rs`,
  `rust/src/screenshare/capture_pw.rs`, `rust/src/screenshare/pw_stream.rs` (tests),
  `rust/src/screenshare/gpu_live_test.rs`, `CALLS.md`

**Interfaces:**
- Consumes: `rift_ffenc_takes_dmabuf`, `external_modifiers` (Task 3).
- Produces:
  ```rust
  pub(crate) struct DrmCard { pub vendor: u16, pub connected: bool, pub render_node: Option<String> }
  /// The NVIDIA card's render node when it has a connected display and no Intel
  /// or AMD card does. `None` keeps today's order.
  pub(crate) fn nvidia_draws_the_screen(cards: &[DrmCard]) -> Option<&str>;
  pub(crate) fn read_cards() -> Vec<DrmCard>;   // /sys/class/drm
  pub(crate) struct DmabufTarget { pub render_node: String, pub external_modifiers: bool }
  pub(crate) fn dmabuf_target() -> Option<DmabufTarget>; // replaces dmabuf_render_node
  ```
  Vendors: `0x10de` NVIDIA, `0x8086` Intel, `0x1002` AMD.

- [ ] **Step 1: Write the failing tests in `gpu_choice.rs`**

`nvidia_draws_the_screen`:
- NVIDIA connected, nothing else → its node.
- NVIDIA connected, Intel with none connected (a desktop with an iGPU) → NVIDIA's node.
- NVIDIA connected, Intel connected → `None`. NVIDIA none, Intel connected (hybrid) → `None`.
- NVIDIA connected, AMD connected → `None`. NVIDIA connected, no render node → `None`.
- A card of an unknown vendor connected beside NVIDIA → NVIDIA's node.
- No cards → `None`.

- [ ] **Step 2: Run to see them fail**

Run: `cargo test --release gpu_choice`. Expected: compile failure.

- [ ] **Step 3: Implement it, and `read_cards`**

`read_cards` walks `/sys/class/drm/card[0-9]*`: `device/vendor`, any
`card*-*/status` reading `connected`, `device/drm/renderD*`.

- [ ] **Step 4: Change `candidates()` and the render node**

On Wayland with the rule true: NVENC first, `device` set to the node, VAAPI after it.
Otherwise today's order, with `device: None`. `dmabuf_target()` returns the VAAPI
candidate's node with `external_modifiers: false`, or NVENC's when its device is set
with `external_modifiers: true`. A NVENC whose GL side failed still answers
`takes_dmabuf` false on the session, so the stream stays on memory. `capture_pw.rs` passes both
to `PwStream::open`. `ENCODER_ENV` still wins. Run `cargo test --release`.

- [ ] **Step 5: Make the live test any encoder's**

Rename `live_vaapi_encodes_the_stream` to `live_gpu_encodes_the_stream` and pass the
target's `external_modifiers`. Add `RIFT_DUMP_H264=<file>` to its sink, test code only.
Run it with the moving picture. Expected: at least 150 frames in 3 s, no refused imports.

- [ ] **Step 6: Commit with `CALLS.md`**

`CALLS.md` says the rule, the path and what falls back.

---

### Task 5: Sync and orientation on a real share

This settles the two things the spike could not. Whether the sub-step at the end is built
depends on what it finds.

**Files:**
- Create: `scripts/perf/tear_check.py` (untracked, like the rest of that folder)
- Modify, only if it tears: `native/ffenc/nvenc_gl.c`, `native/ffenc/pipewire.c`,
  `native/ffenc/ffenc.h` (ABI 9 if the struct changes), `CALLS.md`

**Interfaces:**
- Consumes: `live_gpu_encodes_the_stream`, `RIFT_DUMP_H264`, `RIFT_PW_NO_TIMELINE`.

- [ ] **Step 1: The tear picture and its check**

Full-screen `ffplay -an -fs` of a lavfi picture that changes its whole area every frame
between two dark grays (Y 40 and 80, never a bright flash), with a counter bar along one
edge. `tear_check.py` decodes a dump and fails if any picture's luma is not uniform to
within ±6 apart from the bar (torn), or if the bar's step goes backwards (stale).

- [ ] **Step 2: Orientation**

With `testsrc2` on screen, dump and turn one picture to PNG. Read it. Expected: upright
and not mirrored, whole screen and a window. If it is flipped, fix `nvenc_gl_source_uv`,
add the case to the geometry test, and report why the spike's drawing differed.

- [ ] **Step 3: Tears with the timeline**

Run the live test under `tear_check.py`, 60 s, with the GPU idle and then under a
GPU-loading program. Expected: 0 torn, 0 stale. Anything else is a stopping fault: use
superpowers:systematic-debugging.

- [ ] **Step 4: Tears without the timeline**

The same with `RIFT_PW_NO_TIMELINE=1`. If clean, record it and skip step 5.

- [ ] **Step 5: Only if step 4 tore: wait on the buffer's own fence**

Before drawing: `DMA_BUF_IOCTL_EXPORT_SYNC_FILE` on the buffer's fd, then
`eglCreateSyncKHR(EGL_SYNC_NATIVE_FENCE_ANDROID)` and `eglWaitSyncKHR`, a wait on the GPU.
Run step 4 again. If it still tears or the calls are refused, a stream with no timeline on
NVENC's path goes to memory buffers (`pipewire.c` tells `capture_pw.rs`, ABI 9). Accepting
tears is not an option.

- [ ] **Step 6: Buffers moved mid-share**

A new live test, `live_gpu_stream_moves_to_memory_and_back`: DMA-BUF, then
`set_buffers(Memory)` with NV12 sent, then DMA-BUF. Expected: frames throughout, no CUDA
or FFmpeg error, and `tear_check.py` passes on the dump.

- [ ] **Step 7: Commit, with the findings in `CALLS.md` and the spec's *Sync* section**

---

### Task 6: The settings switch

**Files:**
- Modify: `rust/src/api/screenshare/types.rs`, `rust/src/screenshare/capture.rs`,
  `rust/src/screenshare/capture_pw.rs`, `rust/src/screenshare/session.rs`,
  `lib/logic/cubits/app/` (`AppState`, `AppCubit`), the code calling
  `ScreenshareCubit`'s start, `lib/logic/cubits/screenshare/screenshare_cubit.dart`,
  `lib/presentation/screens/settings/widgets/general_content.dart`, generated bridge files,
  `CALLS.md`, `test/` (state test)

**Interfaces:**
- Produces: `ScreenShareConfig.gpu_capture: bool` and `CaptureRequest.gpu_capture: bool`.
  `AppState.gpuScreenCapture: bool`, persisted, default `true`, with
  `AppCubit.setGpuScreenCapture(bool)`.
- Value: `capture_pw::run` returns `Handoff::Fallback(request)` at once when
  `gpu_capture` is false, for Intel/AMD and NVIDIA alike.
- A share in progress keeps its path; the switch takes effect from the next share (owner
  rule, builder's detail).

- [ ] **Step 1: Write the failing tests**

- A state test: default `true`; `fromJson` of an old state without the key is `true`;
  round trip of `false`.
- A Rust unit test on a small pure `fn takes_rifts_stream(gpu_capture: bool, wayland: bool) -> bool`
  in `capture_pw.rs`: false whenever `gpu_capture` is false, and today's answer otherwise.

- [ ] **Step 2: Run to see them fail**

Run: `flutter test test/<state test>` and `cargo test --release takes_rifts_stream`.

- [ ] **Step 3: Implement it through the bridge**

Regenerate with flutter_rust_bridge 2.13.0 and `dart run build_runner build`. The cubit
takes it as a start argument from the widget that starts the share, reading `AppCubit`;
`ScreenshareCubit` gains no cubit dependency. Linux under Wayland only sees the toggle
(`SettingToggleRow` in `general_content.dart`, gated as `Show "No internet"` is gated):
title `Capture the screen on the GPU`, description
`Keeps your game smoother while you share. Turn it off if a share looks wrong, then start it again.`

- [ ] **Step 4: Drive it**

Debug build with the switch off: the log says libwebrtc's capturer, a window share uses
its saved pick with no second picker, the picture is right. The owner answers any picker.

- [ ] **Step 5: Commit, with the generated files and `CALLS.md`**

---

### Task 7: Measure it and drive the app

**Files:**
- Modify: `docs/gpu-codecs/PLAN.md` (step 0's table), `TESTING.md`, `CALLS.md`,
  `docs/gpu-codecs/STEP2_NVIDIA.md` (status line); the local `MANUAL_TESTING.md`

- [ ] **Step 1: Rebuild and restart the rig**

`cargo build --release`, then the Flutter release bundle, in that order, then the test
clients. The owner answers the picker. Never touch the owner's Rift.

- [ ] **Step 2: CPU at 1080p60, the bar first**

The moving picture, full screen, H264 at 15 Mbit/s, one viewer, `tt <PID> 20`. Measure in
this order: gsr (`gpu-screen-recorder -w portal … -encoder gpu`), Rift with
`RIFT_FFENC_NO_GL=1`, Rift's new path. Expected: the new path close to gsr. A miss goes to
the owner with the numbers, and no cache gets built.

- [ ] **Step 3: The watcher at 1080p120**

Expected: every picture the rate gate lets through reaches the viewer, and ffenc's `send`
in the session's timings stays well under 8.3 ms.

- [ ] **Step 4: The game**

Ask the owner to install a benchmark, with the exact command (proposed:
`sudo pacman -S --needed glmark2 mangohud`). Fps and frame-time spikes from MangoHud's log
with no share, the old path, the new path and gsr. Expected: the new path costs no more
than gsr, and less than the old. Only if the game loses frames, try `EGL_IMG_context_priority`
low, and check the share under a full GPU. Report the wait on the map and sync.

- [ ] **Step 5: Everything a share does**

In the app, with a web viewer and an app viewer: screen and window; quality to VP9 and
back; a window resized, minimised, closed; a late viewer on a still screen; the encoder made
to fail (`RIFT_FFENC_ENCODER`) into the VP9 fall back; sound matched to the window; 20
starts and stops with no PipeWire warnings and no leaked GPU memory (`nvidia-smi`); Rift
quit during a share. The owner answers pickers.

- [ ] **Step 6: Commit the numbers and the `TESTING.md` rows**

Say what was checked and what was not, with the date and how.

---

### Task 8: Intel/AMD after the switch (the owner changes the BIOS)

**Files:**
- Modify: `TESTING.md`, `docs/gpu-codecs/PLAN.md`

- [ ] **Step 1: Hand over the steps and wait**

Say "good point to /compact" first. The owner sets the BIOS to Hybrid and envycontrol to
hybrid, then restarts.

- [ ] **Step 2: Recheck VAAPI**

The Intel path: `native/ffenc/test.sh <out>`, `live_gpu_encodes_the_stream`, and one share
in the app through `tt`. Expected: VAAPI on Intel is chosen, 4.5% of a core as accepted, and
with the settings switch off it uses libwebrtc's capturer.

- [ ] **Step 3: Commit the result**

---

## Not in this plan

Merging to `dev` (owner: only when GPU encode and decode are both done), pushing, and any
release. The KDE VM has no NVIDIA card, so a KDE check of this path waits for a machine
with one; `TESTING.md` says so.
