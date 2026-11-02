// A GPU decoder through FFmpeg, in the same library as the encoders
// (ffenc.h says why the library is one of its own): a watched share's
// pictures, received still encoded (rust/src/watching), decoded on the GPU
// Flutter draws with and handed to the runner as DMA-BUFs, never coming to the
// CPU. Linux, VAAPI.
//
// Only a hardware decoder: when the GPU cannot decode the share's codec, open
// fails rather than decoding in software, and the app watches that share the
// way it always has.
#ifndef RIFT_FFDEC_H_
#define RIFT_FFDEC_H_

#include "ffenc.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct RiftFfdec RiftFfdec;

// The codecs a share arrives in.
typedef enum {
  RIFT_FFDEC_H264 = 1,
  RIFT_FFDEC_VP8 = 2,
  RIFT_FFDEC_VP9 = 3,
} RiftFfdecCodec;

typedef struct RiftFfdecConfig {
  // RiftFfdecCodec.
  int32_t codec;
  // The GPU to decode on, as a DRM render node; NULL is FFmpeg's default.
  const char* device;
} RiftFfdecConfig;

// One decoded picture, NV12 as two DMA-BUF layers of one plane each: Y as
// DRM's R8 at the picture's size, interleaved UV as GR88 at half the size each
// way, rounded up. Each imports into EGL as an ordinary texture, so one shader
// draws it whatever the GPU's own layout.
typedef struct RiftFfdecPicture {
  // The visible picture, crop applied.
  int32_t width;
  int32_t height;
  int32_t planes;
  uint32_t formats[4];
  int32_t fds[4];
  uint32_t offsets[4];
  uint32_t pitches[4];
  uint64_t modifiers[4];
  int64_t timestamp_us;
  // The picture's hold on its GPU surface, for rift_ffdec_release.
  void* held;
} RiftFfdecPicture;

// Open a decoder, or NULL with the reason written into `error`. Opening
// does not yet ask the GPU about the codec: the first picture does, and a
// GPU that cannot decode it fails rift_ffdec_send.
RIFT_FFENC_EXPORT RiftFfdec* rift_ffdec_open(const RiftFfdecConfig* config,
                                             char* error, size_t error_len);
// The GPU's driver, as it names itself.
RIFT_FFENC_EXPORT const char* rift_ffdec_driver(const RiftFfdec* dec);
// Decode one access unit, whole, as received. 0, or a negative FFmpeg error;
// AVERROR(ENOSYS) when the GPU cannot decode this stream.
RIFT_FFENC_EXPORT int32_t rift_ffdec_send(RiftFfdec* dec, const uint8_t* data,
                                          size_t len, int64_t timestamp_us);
// The next decoded picture: 1 with one, which is the caller's until
// rift_ffdec_release, 0 when none is ready, or a negative FFmpeg error. The
// fds stay the picture's: they close with its release.
RIFT_FFENC_EXPORT int32_t rift_ffdec_receive(RiftFfdec* dec,
                                             RiftFfdecPicture* picture);
// Lets a picture's GPU surface go back to its decoder. From any thread, and
// after the decoder is closed too.
RIFT_FFENC_EXPORT void rift_ffdec_release(RiftFfdecPicture* picture);
RIFT_FFENC_EXPORT void rift_ffdec_close(RiftFfdec* dec);

#ifdef __cplusplus
}
#endif

#endif  // RIFT_FFDEC_H_
