// A GPU encoder through FFmpeg, as a library of its own: librift_ffenc.so
// with NVENC's and VAAPI's on Linux, rift_ffenc.dll with NVENC's, QSV's and
// AMF's on Windows.
//
// LiveKit's libwebrtc already carries an FFmpeg (Chromium's, decoders only)
// under the same symbol names, so Rift's FFmpeg cannot be linked beside it.
// This library holds a minimal FFmpeg built for it (native/ffenc/build.sh),
// keeps every symbol but these hidden, and is opened at run time by the Rust
// crate (rust/src/screenshare/encoder/ffmpeg.rs). A computer it cannot load on
// simply has no encoder here. On Linux it also reads a Wayland share's
// PipeWire stream (pipewire.c), so that libpipewire is only ever this
// library's to need.
#ifndef RIFT_FFENC_H_
#define RIFT_FFENC_H_

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define RIFT_FFENC_EXPORT __declspec(dllexport)
#else
#define RIFT_FFENC_EXPORT __attribute__((visibility("default")))
#endif

// Bumped whenever a function or struct below changes, so the crate refuses a
// library from another build instead of calling it wrongly.
#define RIFT_FFENC_ABI 8

typedef struct RiftFfenc RiftFfenc;

typedef struct RiftFfencConfig {
  // FFmpeg's name for the encoder, such as "h264_vaapi" or "h264_nvenc".
  const char* encoder;
  // The GPU to open, as FFmpeg's hardware device names it: a DRM render
  // node for VAAPI. NULL is FFmpeg's default, and the only choice for
  // QSV and AMF, whose drivers pick their own GPU. For NVENC, the render node
  // of the card whose screen it encodes, which opens its EGL and CUDA side;
  // NULL takes memory only.
  const char* device;
  int32_t width;
  int32_t height;
  int32_t fps;
  // Where the rate starts, and the peak it may reach over the average, in
  // percent (100 is constant bitrate).
  int64_t bitrate_bps;
  int32_t peak_percent;
  // Pictures between keyframes when none is asked for.
  int32_t gop;
  // The most the rate will be moved to: what an encoder that cannot resize
  // its buffers once open (QSV) sizes them for.
  int64_t max_bitrate_bps;
  // NVENC's "delay": a picture comes out once this many are encoded or
  // waiting, so 0 and 1 hold none and 2 holds one. Other encoders ignore it.
  int32_t delay_frames;
  // 1 for H264's High profile, 0 for constrained baseline.
  int32_t high;
} RiftFfencConfig;

typedef struct RiftFfencPacket {
  const uint8_t* data;
  size_t len;
  int64_t timestamp_us;
  int32_t keyframe;
} RiftFfencPacket;

// Lines FFmpeg logs, at its own levels (AV_LOG_*).
typedef void (*RiftFfencLog)(int32_t level, const char* line);

RIFT_FFENC_EXPORT int32_t rift_ffenc_abi(void);

// Where FFmpeg's log lines go, for every encoder. NULL keeps them quiet.
RIFT_FFENC_EXPORT void rift_ffenc_set_log(RiftFfencLog log, int32_t max_level);

// Open an encoder, or NULL with the reason written into `error`.
RIFT_FFENC_EXPORT RiftFfenc* rift_ffenc_open(const RiftFfencConfig* config,
                                             char* error, size_t error_len);

// The GPU's driver, as it names itself.
RIFT_FFENC_EXPORT const char* rift_ffenc_driver(const RiftFfenc* enc);

// A new average rate, taken from the next picture on.
RIFT_FFENC_EXPORT void rift_ffenc_set_bitrate(RiftFfenc* enc,
                                              int64_t bitrate_bps);

// Encode one picture: `width * height` bytes of Y, then interleaved UV at
// half size (NV12), tightly packed. The picture is copied to the GPU before
// this returns. 0, or a negative FFmpeg error.
RIFT_FFENC_EXPORT int32_t rift_ffenc_send(RiftFfenc* enc, const uint8_t* nv12,
                                          int64_t timestamp_us,
                                          int32_t keyframe);

// ── Pictures already on the GPU (Linux, VAAPI and NVENC) ────────────────
//
// A Wayland share's picture arrives as the compositor's DMA-BUF. It is
// mapped into VAAPI, or drawn through GL into NVENC's frame, cropped, turned
// upright, scaled and placed into NV12 on the GPU, and encoded, without coming
// to the CPU.

// One DMA-BUF in an 8-bit RGB format, described as PipeWire hands it over.
typedef struct RiftDmabuf {
  // The buffer's size, before any crop or turn.
  int32_t width;
  int32_t height;
  // The part of it that is the picture; all four 0 for the whole buffer.
  int32_t crop_x;
  int32_t crop_y;
  int32_t crop_width;
  int32_t crop_height;
  // DRM's fourcc: XRGB8888, ARGB8888, XBGR8888 or ABGR8888.
  uint32_t drm_format;
  uint64_t modifier;
  int32_t planes;
  int32_t fds[4];
  uint32_t offsets[4];
  uint32_t strides[4];
  // How the compositor turned the buffer, as PipeWire's
  // SPA_META_TRANSFORMATION_* says (0 none, 1-3 by 90 degrees
  // counter-clockwise, 4-7 the same flipped first); undone here.
  int32_t transform;
} RiftDmabuf;

// The buffer's format and modifier would not map into VAAPI on this GPU: the
// caller drops the modifier and asks the compositor for another.
#define RIFT_FFENC_IMPORT_FAILED (-0x52494D50)

typedef struct RiftRect {
  int32_t x;
  int32_t y;
  int32_t width;
  int32_t height;
} RiftRect;

// 1 when rift_ffenc_send_dmabuf works on this encoder: VAAPI's, or NVENC's with
// a `device` whose GL path opened (RIFT_FFENC_NO_GL=1 in the environment refuses
// that, for a test).
RIFT_FFENC_EXPORT int32_t rift_ffenc_takes_dmabuf(const RiftFfenc* enc);

// Encode one DMA-BUF picture. `place` is where the upright picture goes
// inside the encoded size, the rest black; NULL fills it. Returns once the
// GPU has copied the picture, so the caller may give the buffer back; the
// fds stay the caller's. 0, RIFT_FFENC_IMPORT_FAILED, or a negative FFmpeg
// error; AVERROR(ENOSYS) for an encoder that takes none.
RIFT_FFENC_EXPORT int32_t rift_ffenc_send_dmabuf(RiftFfenc* enc,
                                                 const RiftDmabuf* buf,
                                                 const RiftRect* place,
                                                 int64_t timestamp_us,
                                                 int32_t keyframe);

// Encode the last DMA-BUF picture again, for a screen that has not changed
// when a keyframe is wanted or a second has passed. AVERROR(EAGAIN) before
// the first.
RIFT_FFENC_EXPORT int32_t rift_ffenc_repeat(RiftFfenc* enc,
                                            int64_t timestamp_us,
                                            int32_t keyframe);

// The next encoded frame, valid until the next call: 1 with one, 0 when the
// encoder has none ready, or a negative FFmpeg error.
RIFT_FFENC_EXPORT int32_t rift_ffenc_receive(RiftFfenc* enc,
                                             RiftFfencPacket* packet);

RIFT_FFENC_EXPORT void rift_ffenc_close(RiftFfenc* enc);

// ── A Wayland share's PipeWire stream (Linux) ───────────────────────────
//
// The stream the ScreenCast portal opened, read here so its pictures can
// reach the encoder as DMA-BUFs (pipewire.c, from OBS Studio's). Rust opens
// the portal and hands over its PipeWire fd and node.

typedef struct RiftPwStream RiftPwStream;

// The kind of buffer asked for: DMA-BUFs (memory ones still taken when the
// compositor offers only those), or memory only, for the raw path.
typedef enum { RIFT_PW_DMABUF = 1, RIFT_PW_MEMORY = 2 } RiftPwBuffers;

// A memory picture's byte order: B, G, R, then x or alpha (BGRx, BGRA), or
// R, G, B first (RGBx, RGBA).
typedef enum { RIFT_PW_BGRX = 0, RIFT_PW_RGBX = 1 } RiftPwOrder;

typedef struct RiftPwPicture {
  // When `buffers` is RIFT_PW_DMABUF: the buffer, its crop and turn.
  RiftDmabuf dmabuf;
  // When RIFT_PW_MEMORY: rows of four bytes a pixel, in `order`
  // (RiftPwOrder), from the crop's top-left corner, `len` bytes readable;
  // not turned.
  const uint8_t* data;
  size_t len;
  int32_t stride;
  int32_t order;
  int32_t buffers;
  // The picture's size once cropped and turned upright.
  int32_t width;
  int32_t height;
  // How the compositor turned it (SPA_META_TRANSFORMATION_*, as in
  // RiftDmabuf).
  int32_t transform;
  // PipeWire's presentation time, on the monotonic clock.
  int64_t pts_ns;
  // The stream it came from and its buffer, for rift_pw_release.
  RiftPwStream* stream;
  void* held;
} RiftPwPicture;

typedef struct RiftPwCallbacks {
  void* user;
  // On PipeWire's thread, which it must not hold up. The picture is the
  // caller's until rift_pw_release; at most two are held at once, and a
  // newer one while two are goes back unseen.
  void (*picture)(void* user, const RiftPwPicture* picture);
  // 0 streaming, 1 paused (also before the first picture), 2 ended, with
  // why. Ended comes once.
  void (*state)(void* user, int32_t state, const char* error);
} RiftPwCallbacks;

// Opens the stream on `node_id` of the PipeWire remote `fd` (duplicated;
// the caller keeps its own), at most `max_fps` pictures a second. DMA-BUFs
// are offered with the modifiers EGL imports on `render_node`, and those it
// imports only as external when `external_modifiers` is 1, as NVENC's GL path
// can; NULL offers memory only. RIFT_PW_REFUSE_DMABUF=1 in the environment
// offers memory only too, for a test, and RIFT_PW_NO_TIMELINE=1 leaves explicit
// sync out of the negotiation. NULL on failure, with why in `error`.
RIFT_FFENC_EXPORT RiftPwStream* rift_pw_open(int32_t fd, uint32_t node_id,
                                             int32_t max_fps,
                                             const char* render_node,
                                             int32_t external_modifiers,
                                             int32_t buffers,
                                             const RiftPwCallbacks* callbacks,
                                             char* error, size_t error_len);

// Asks for the other kind of buffer; pictures already on their way still
// come in the old kind.
RIFT_FFENC_EXPORT void rift_pw_set_buffers(RiftPwStream* stream,
                                           int32_t buffers);

// A new rate for the share: the compositor is asked for at most this many
// pictures a second from the next negotiation on.
RIFT_FFENC_EXPORT void rift_pw_set_max_fps(RiftPwStream* stream,
                                           int32_t max_fps);

// A modifier the encoder could not import: offered no more, and the stream
// renegotiates. With none left, memory buffers come instead.
RIFT_FFENC_EXPORT void rift_pw_drop_modifier(RiftPwStream* stream,
                                             uint32_t drm_format,
                                             uint64_t modifier);

// Gives a picture's buffer back to the compositor, from any thread.
RIFT_FFENC_EXPORT void rift_pw_release(RiftPwStream* stream, void* held);

// Stops the stream: no callback runs once it returns. Pictures still held
// stay readable until released; the stream is freed with the last.
RIFT_FFENC_EXPORT void rift_pw_close(RiftPwStream* stream);

#ifdef __cplusplus
}
#endif

#endif  // RIFT_FFENC_H_
