// A GPU encoder through FFmpeg, as a library of its own: librift_ffenc.so
// with VAAPI's on Linux, rift_ffenc.dll with NVENC's, QSV's and AMF's on
// Windows.
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
#define RIFT_FFENC_ABI 2

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

// The next encoded frame, valid until the next call: 1 with one, 0 when the
// encoder has none ready, or a negative FFmpeg error.
RIFT_FFENC_EXPORT int32_t rift_ffenc_receive(RiftFfenc* enc,
                                             RiftFfencPacket* packet);

RIFT_FFENC_EXPORT void rift_ffenc_close(RiftFfenc* enc);

#ifdef __cplusplus
}
#endif

#endif  // RIFT_FFENC_H_
