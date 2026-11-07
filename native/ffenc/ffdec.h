// A GPU decoder through FFmpeg, in the same library as the encoders
// (ffenc.h says why the library is one of its own): a watched share's
// pictures, received still encoded (rust/src/watching), decoded on the GPU
// Flutter draws with, never coming to the CPU. Linux: VAAPI on Intel and AMD,
// handing the runner DMA-BUFs; NVIDIA's decoder through CUDA, whose pictures
// the runner has copied into its own GL textures (rift_ffdec_copy_to_gl).
// Windows: D3D11's video decoder on the runner's own device, whose surfaces
// the runner draws where they lie.
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
  RIFT_FFDEC_H265 = 4,
} RiftFfdecCodec;

// How the GPU is reached.
typedef enum {
  RIFT_FFDEC_VAAPI = 0,
  RIFT_FFDEC_CUDA = 1,
  RIFT_FFDEC_D3D11VA = 2,
} RiftFfdecApi;

typedef struct RiftFfdecConfig {
  // RiftFfdecCodec.
  int32_t codec;
  // The GPU to decode on, as a DRM render node; NULL is FFmpeg's default.
  const char* device;
  // RiftFfdecApi.
  int32_t api;
  // D3D11VA: the ID3D11Device to decode on, the runner's, with video support
  // and multithread protection. The decoder holds a reference of its own
  // until it closes. NULL for the others.
  void* d3d11_device;
} RiftFfdecConfig;

// Where a decoded picture lies.
typedef enum {
  // Two DMA-BUF layers, described below.
  RIFT_FFDEC_IN_DMABUF = 0,
  // CUDA's memory, for rift_ffdec_copy_to_gl: no fds.
  RIFT_FFDEC_IN_CUDA = 1,
  // A slice of the D3D11 decoder's NV12 texture array, described below.
  RIFT_FFDEC_IN_D3D11 = 2,
} RiftFfdecMemory;

// The matrix a picture's colour is coded with, as the stream says; BT.601
// when it says none, which is how libwebrtc's own decoder is drawn.
typedef enum {
  RIFT_FFDEC_BT601 = 0,
  RIFT_FFDEC_BT709 = 1,
  RIFT_FFDEC_BT2020 = 2,
} RiftFfdecMatrix;

// One decoded picture, NV12. From VAAPI, as two DMA-BUF layers of one plane
// each: Y as DRM's R8 at the picture's size, interleaved UV as GR88 at half
// the size each way, rounded up. Each imports into EGL as an ordinary
// texture, so one shader draws it whatever the GPU's own layout. From CUDA,
// the same two planes, copied by rift_ffdec_copy_to_gl. From D3D11, one slice
// of an NV12 texture array, coded at the decoder's aligned size (1088 lines
// for 1080), of which the top left `width` by `height` is the picture. The
// array is a shader resource as well as the decoder's where the GPU allows it
// (its BindFlags say), and only the decoder's where it does not.
typedef struct RiftFfdecPicture {
  // The visible picture, crop applied.
  int32_t width;
  int32_t height;
  int32_t planes;
  // RiftFfdecMemory.
  int32_t memory;
  // RiftFfdecMatrix, and 1 for full range rather than limited.
  int32_t matrix;
  int32_t full_range;
  uint32_t formats[4];
  int32_t fds[4];
  uint32_t offsets[4];
  uint32_t pitches[4];
  uint64_t modifiers[4];
  int64_t timestamp_us;
  // The picture's hold on its GPU surface, for rift_ffdec_release.
  void* held;
  // IN_D3D11: the decoder's ID3D11Texture2D array and the picture's slice in
  // it, both held by `held`.
  void* d3d11_texture;
  int32_t d3d11_slice;
} RiftFfdecPicture;

// Open a decoder, or NULL with the reason written into `error`. Opening
// does not yet ask the GPU about the codec: the first picture does, and a
// GPU that cannot decode it fails rift_ffdec_send. So does a codec Windows'
// build decodes nowhere (VP8: no D3D11 GPU offers it, and FFmpeg has no
// d3d11va hwaccel for it).
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

#if defined(__linux__)
// Whether NVIDIA's decoder on `node` takes 8-bit 4:2:0 in `codec`: 1 or 0, or
// negative when it could not be asked. VAAPI's answer comes from libva, and
// opening a decoder would not tell: only the first picture asks the GPU.
RIFT_FFENC_EXPORT int32_t rift_ffdec_cuda_decodes(int32_t codec,
                                                  const char* node);
#endif

#if defined(__linux__)
// Two GL textures registered with CUDA, kept between pictures, since
// registering costs far more than a copy.
typedef struct RiftFfdecGl RiftFfdecGl;

// Copies a picture in CUDA's memory into `textures`: Y into an R8 texture of
// the picture's size, UV into an RG8 one of half the size each way, rounded
// up. On the thread whose GL context holds the textures, current. `*link` is
// the caller's, NULL at first: it is made, or made again for other textures
// or another decoder's context, and kept for the next picture; its textures'
// storage must not change while it lives. Done on the GPU before this
// returns, so the picture may be released at once. 0, or a negative FFmpeg
// error.
RIFT_FFENC_EXPORT int32_t rift_ffdec_copy_to_gl(
    const RiftFfdecPicture* picture, const uint32_t textures[2],
    RiftFfdecGl** link);
// Lets the textures go from CUDA, on the same thread, before they are
// deleted. NULL is nothing.
RIFT_FFENC_EXPORT void rift_ffdec_gl_close(RiftFfdecGl* link);
#endif

#ifdef __cplusplus
}
#endif

#endif  // RIFT_FFDEC_H_
