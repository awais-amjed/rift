// A GPU encoder through FFmpeg, as a library of its own: librift_ffenc.so
// with NVENC's and VAAPI's on Linux, rift_ffenc.dll with NVENC's, QSV's and
// AMF's on Windows.
//
// LiveKit's libwebrtc already carries an FFmpeg (Chromium's, decoders only)
// under the same symbol names, so Rift's FFmpeg cannot be linked beside it.
// This library holds a minimal FFmpeg built for it (native/ffenc/build.sh),
// keeps every symbol but these hidden, and is opened at run time by the Rust
// crate (rust/src/screenshare/encoder/ffmpeg.rs). A computer it cannot load on
// simply has no encoder here.
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
#define RIFT_FFENC_ABI 5

typedef struct RiftFfenc RiftFfenc;

typedef struct RiftFfencConfig {
  // FFmpeg's name for the encoder, such as "h264_vaapi" or "h264_nvenc".
  const char* encoder;
  // The GPU to open, as FFmpeg's hardware device names it: a DRM render
  // node for VAAPI. NULL is FFmpeg's default, and the only choice for
  // NVENC, QSV and AMF, whose drivers pick their own GPU.
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

// ── Pictures already on the GPU (Linux, VAAPI) ──────────────────────────
//
// A Wayland share's picture arrives as the compositor's DMA-BUF. It is
// mapped into VAAPI, cropped, turned upright, scaled and placed into NV12 on
// the GPU, and encoded, without coming to the CPU.

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

// Encode one DMA-BUF picture. `place` is where the upright picture goes
// inside the encoded size, the rest black; NULL fills it. Returns once the
// GPU has copied the picture, so the caller may give the buffer back; the
// fds stay the caller's. 0, RIFT_FFENC_IMPORT_FAILED, or a negative FFmpeg
// error; AVERROR(ENOSYS) for an encoder that is not VAAPI's.
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

#ifdef __cplusplus
}
#endif

#endif  // RIFT_FFENC_H_
