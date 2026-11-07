// A watched share's pictures decoded on the GPU (ffdec.h).
//
// The copy from CUDA into GL textures (rift_ffdec_copy_to_gl) is
// Moonlight's (moonlight-qt at 1ced9dd, GPL-3.0,
// app/streaming/video/ffmpeg-renderers/cuda.cpp, CUDAGLInteropHelper): the
// decoder's context pushed, each plane's texture registered for writing,
// mapped, copied into and unmapped for every picture. mpv's
// (video/out/hwdec/hwdec_cuda*.c, LGPL-2.1+) does the same. Changed for Rift:
// the registration kept between pictures and made again only for other
// textures or another context; the copy waited for on the decoder's own
// stream, as nvenc_gl.c waits for its copy the other way, so the picture can
// go back to the decoder at once; and every decoder on FFmpeg's CUDA primary
// context, which the runner's copy shares.
//
// Windows decodes with FFmpeg's d3d11va on the runner's own device, the way
// Moonlight's d3d11va.cpp (moonlight-qt, GPL-3.0) does on its own: the
// decoder's surfaces made shader resources as well where the GPU allows it,
// so the runner draws each slice where it lies. Changed for Rift: the device
// is the caller's, and its own multithread lock is FFmpeg's, so the runner's
// drawing and the decoder never use the immediate context at once.
#if defined(_WIN32)
#define COBJMACROS
#endif
#include "ffdec.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <libavcodec/avcodec.h>
#include <libavutil/dict.h>
#include <libavutil/hwcontext.h>

#include "ff_shared.h"
#if defined(__linux__)
#include <libavutil/hwcontext_drm.h>
// After ff_shared.h, whose NVIDIA loader header gives it CUDA's types.
#include <libavutil/hwcontext_cuda.h>
#endif
#if defined(_WIN32)
#include <d3d10.h>
#include <d3d11.h>
#include <dxgi.h>
#include <windows.h>

#include <libavutil/hwcontext_d3d11va.h>
#endif

// Surfaces past what the decoder needs for its references: the newest
// picture waiting for the runner, the one it is drawing, and one on its way
// between the two. Without them the decoder would wait for one back.
#define LENT_PICTURES 4

#if defined(__linux__)
// DRM's fourccs for NV12's two planes, as their own layers (drm_fourcc.h,
// which the library does not otherwise need).
#define FOURCC(a, b, c, d)                                    \
  ((uint32_t)(a) | ((uint32_t)(b) << 8) | ((uint32_t)(c) << 16) | \
   ((uint32_t)(d) << 24))
#define DRM_R8 FOURCC('R', '8', ' ', ' ')
#define DRM_GR88 FOURCC('G', 'R', '8', '8')

// GL's names, which the library otherwise does not need (gl.h).
#define GL_TEXTURE_2D 0x0DE1
#endif

struct RiftFfdec {
  AVBufferRef* device;
  AVCodecContext* codec;
  AVPacket* packet;
  AVFrame* frame;
  // AV_PIX_FMT_VAAPI, AV_PIX_FMT_CUDA or AV_PIX_FMT_D3D11: the only format
  // taken.
  enum AVPixelFormat gpu_format;
  // The GPU had no decoder for the stream, said while choosing how to
  // decode it.
  int no_gpu_decoder;
  char driver[128];
#if defined(_WIN32)
  // The GPU lets the shader read NV12 decoder surfaces, so they are made
  // shader resources too.
  int shader_readable;
#endif
};

#if defined(__linux__)
struct RiftFfdecGl {
  CudaFunctions* cu;
  // Holds the context the textures are registered in.
  AVBufferRef* device;
  CUcontext context;
  uint32_t textures[2];
  CUgraphicsResource resources[2];
};
#endif

static enum AVCodecID codec_id_of(int32_t codec) {
  switch (codec) {
    case RIFT_FFDEC_H264:
      return AV_CODEC_ID_H264;
    case RIFT_FFDEC_VP8:
      return AV_CODEC_ID_VP8;
    case RIFT_FFDEC_VP9:
      return AV_CODEC_ID_VP9;
    case RIFT_FFDEC_H265:
      return AV_CODEC_ID_HEVC;
    default:
      return AV_CODEC_ID_NONE;
  }
}

#if defined(_WIN32)
// The decoder's surfaces, FFmpeg's own pool as it sizes it (with
// LENT_PICTURES more), made shader resources as well where the GPU allows it,
// and only the decoder's where it allows that but not this.
static int d3d11_frames(AVCodecContext* codec, RiftFfdec* dec) {
  int err = 0;
  for (int shader = dec->shader_readable; shader >= 0; shader--) {
    AVBufferRef* frames = NULL;
    err = avcodec_get_hw_frames_parameters(codec, codec->hw_device_ctx,
                                           AV_PIX_FMT_D3D11, &frames);
    if (err < 0) return err;
    AVHWFramesContext* context = (AVHWFramesContext*)frames->data;
    AVD3D11VAFramesContext* d3d11 = context->hwctx;
    if (shader) d3d11->BindFlags |= D3D11_BIND_SHADER_RESOURCE;
    err = av_hwframe_ctx_init(frames);
    if (err >= 0) {
      av_buffer_unref(&codec->hw_frames_ctx);
      codec->hw_frames_ctx = frames;
      return 0;
    }
    av_buffer_unref(&frames);
    if (shader) {
      av_log(NULL, AV_LOG_WARNING,
             "ffdec: no decoder surfaces the shader can read; the runner "
             "copies each\n");
    }
  }
  return err;
}
#endif

// FFmpeg offers the GPU's format first when its hwaccel can take the stream,
// and asks again without it when the GPU then refuses. Software is never
// chosen: decoding it here would cost the CPU what the call's own path
// already costs, without that path's years of use.
static enum AVPixelFormat gpu_only(AVCodecContext* codec,
                                   const enum AVPixelFormat* formats) {
  RiftFfdec* dec = codec->opaque;
  for (const enum AVPixelFormat* f = formats; *f != AV_PIX_FMT_NONE; f++) {
    if (*f != dec->gpu_format) continue;
#if defined(_WIN32)
    if (*f == AV_PIX_FMT_D3D11 && d3d11_frames(codec, dec) < 0) break;
#endif
    return *f;
  }
  dec->no_gpu_decoder = 1;
  return AV_PIX_FMT_NONE;
}

#if defined(__linux__)
// The NVIDIA card that is `node`'s, on CUDA's primary context: the one every
// decoder in the process shares, so the runner's copy finds its textures
// registered in the context each picture lies in, whichever decoder it came
// from. Named in `driver`.
static int open_cuda(RiftFfdec* dec, const char* node) {
  CudaFunctions* cu = NULL;
  if (cuda_load_functions(&cu, NULL) < 0) return AVERROR(ENOSYS);
  CUdevice device = 0;
  char ordinal[16] = "0";
  if (cu->cuInit(0) == CUDA_SUCCESS &&
      (!node || rift_ff_cuda_device(cu, node, &device) == CUDA_SUCCESS)) {
    snprintf(ordinal, sizeof(ordinal), "%d", (int)device);
    char name[96] = "";
    if (cu->cuDeviceGetName(name, sizeof(name), device) == CUDA_SUCCESS) {
      snprintf(dec->driver, sizeof(dec->driver), "%s, through CUDA", name);
    }
  }
  cuda_free_functions(&cu);
  AVDictionary* options = NULL;
  av_dict_set(&options, "primary_ctx", "1", 0);
  int err = av_hwdevice_ctx_create(&dec->device, AV_HWDEVICE_TYPE_CUDA,
                                   ordinal, options, 0);
  av_dict_free(&options);
  return err;
}
#endif

#if defined(_WIN32)
static void lock_device(void* multithread) {
  ID3D10Multithread_Enter((ID3D10Multithread*)multithread);
}

static void unlock_device(void* multithread) {
  ID3D10Multithread_Leave((ID3D10Multithread*)multithread);
}

static void free_lock(AVHWDeviceContext* context) {
  if (context->user_opaque) {
    ID3D10Multithread_Release((ID3D10Multithread*)context->user_opaque);
  }
}

// FFmpeg's D3D11 device on the caller's, with a reference of its own, and
// the device's multithread lock as FFmpeg's: the runner draws on the same
// immediate context from Flutter's raster thread, under the same lock.
// Named in `driver` after its adapter.
static int open_d3d11(RiftFfdec* dec, ID3D11Device* device) {
  if (!device) return AVERROR(EINVAL);
  dec->device = av_hwdevice_ctx_alloc(AV_HWDEVICE_TYPE_D3D11VA);
  if (!dec->device) return AVERROR(ENOMEM);
  AVHWDeviceContext* context = (AVHWDeviceContext*)dec->device->data;
  AVD3D11VADeviceContext* d3d11 = context->hwctx;
  ID3D11Device_AddRef(device);
  d3d11->device = device;
  ID3D10Multithread* multithread = NULL;
  if (SUCCEEDED(ID3D11Device_QueryInterface(device, &IID_ID3D10Multithread,
                                            (void**)&multithread))) {
    ID3D10Multithread_SetMultithreadProtected(multithread, TRUE);
    context->user_opaque = multithread;
    context->free = free_lock;
    d3d11->lock = lock_device;
    d3d11->unlock = unlock_device;
    d3d11->lock_ctx = multithread;
  }
  UINT support = 0;
  dec->shader_readable =
      SUCCEEDED(ID3D11Device_CheckFormatSupport(device, DXGI_FORMAT_NV12,
                                                &support)) &&
      (support & D3D11_FORMAT_SUPPORT_SHADER_SAMPLE);
  IDXGIDevice* dxgi = NULL;
  IDXGIAdapter* adapter = NULL;
  DXGI_ADAPTER_DESC desc;
  if (SUCCEEDED(ID3D11Device_QueryInterface(device, &IID_IDXGIDevice,
                                            (void**)&dxgi)) &&
      SUCCEEDED(IDXGIDevice_GetAdapter(dxgi, &adapter)) &&
      SUCCEEDED(IDXGIAdapter_GetDesc(adapter, &desc))) {
    char name[96];
    if (WideCharToMultiByte(CP_UTF8, 0, desc.Description, -1, name,
                            sizeof(name), NULL, NULL) > 0) {
      snprintf(dec->driver, sizeof(dec->driver), "%s, through D3D11", name);
    }
  }
  if (adapter) IDXGIAdapter_Release(adapter);
  if (dxgi) IDXGIDevice_Release(dxgi);
  return av_hwdevice_ctx_init(dec->device);
}
#endif

static int32_t matrix_of(enum AVColorSpace space) {
  switch (space) {
    case AVCOL_SPC_BT709:
      return RIFT_FFDEC_BT709;
    case AVCOL_SPC_BT2020_NCL:
    case AVCOL_SPC_BT2020_CL:
      return RIFT_FFDEC_BT2020;
    default:
      return RIFT_FFDEC_BT601;
  }
}

RiftFfdec* rift_ffdec_open(const RiftFfdecConfig* config, char* error,
                           size_t error_len) {
  const AVCodec* codec = avcodec_find_decoder(codec_id_of(config->codec));
  // A codec this build decodes nowhere still opens through D3D11, and fails
  // its first picture as one the GPU cannot decode, as on any other GPU
  // that lacks it.
  int nowhere = !codec && codec_id_of(config->codec) != AV_CODEC_ID_NONE &&
                config->api == RIFT_FFDEC_D3D11VA;
  if (!codec && !nowhere) {
    rift_ff_fail(error, error_len, "no decoder for that codec", 0);
    return NULL;
  }
  RiftFfdec* dec = calloc(1, sizeof(*dec));
  if (!dec) {
    rift_ff_fail(error, error_len, "out of memory", AVERROR(ENOMEM));
    return NULL;
  }
  snprintf(dec->driver, sizeof(dec->driver), "an unnamed GPU");
  int err;
#if defined(__linux__)
  if (config->api == RIFT_FFDEC_CUDA) {
    dec->gpu_format = AV_PIX_FMT_CUDA;
    err = open_cuda(dec, config->device);
  } else if (config->api == RIFT_FFDEC_VAAPI) {
    dec->gpu_format = AV_PIX_FMT_VAAPI;
    err = av_hwdevice_ctx_create(&dec->device, AV_HWDEVICE_TYPE_VAAPI,
                                 config->device, NULL, 0);
  } else {
#elif defined(_WIN32)
  if (config->api == RIFT_FFDEC_D3D11VA) {
    dec->gpu_format = AV_PIX_FMT_D3D11;
    err = open_d3d11(dec, config->d3d11_device);
  } else {
#else
  {
#endif
    rift_ff_fail(error, error_len, "no such way to the GPU", 0);
    goto failed;
  }
  if (err < 0) {
    rift_ff_fail(error, error_len, "the GPU did not open", err);
    goto failed;
  }
  if (nowhere) {
    dec->no_gpu_decoder = 1;
    return dec;
  }
  dec->codec = avcodec_alloc_context3(codec);
  dec->packet = av_packet_alloc();
  dec->frame = av_frame_alloc();
  if (!dec->codec || !dec->packet || !dec->frame) {
    err = AVERROR(ENOMEM);
    rift_ff_fail(error, error_len, "out of memory", err);
    goto failed;
  }
  dec->codec->opaque = dec;
  dec->codec->get_format = gpu_only;
  dec->codec->hw_device_ctx = av_buffer_ref(dec->device);
  dec->codec->extra_hw_frames = LENT_PICTURES;
  // A share has no pictures out of order: each comes out as it goes in.
  dec->codec->flags |= AV_CODEC_FLAG_LOW_DELAY;
  dec->codec->thread_count = 1;
  err = avcodec_open2(dec->codec, codec, NULL);
  if (err < 0) {
    rift_ff_fail(error, error_len, "the decoder did not open", err);
    goto failed;
  }
#if defined(__linux__)
  const char* vendor = rift_ff_vaapi_vendor(dec->device);
  if (vendor) snprintf(dec->driver, sizeof(dec->driver), "%s", vendor);
#endif
  return dec;

failed:
  rift_ffdec_close(dec);
  return NULL;
}

const char* rift_ffdec_driver(const RiftFfdec* dec) { return dec->driver; }

#if defined(__linux__)
int32_t rift_ffdec_cuda_decodes(int32_t codec, const char* node) {
  cudaVideoCodec asked;
  switch (codec) {
    case RIFT_FFDEC_H264:
      asked = cudaVideoCodec_H264;
      break;
    case RIFT_FFDEC_VP8:
      asked = cudaVideoCodec_VP8;
      break;
    case RIFT_FFDEC_VP9:
      asked = cudaVideoCodec_VP9;
      break;
    case RIFT_FFDEC_H265:
      asked = cudaVideoCodec_HEVC;
      break;
    default:
      return -1;
  }
  CudaFunctions* cu = NULL;
  CuvidFunctions* cuvid = NULL;
  int32_t answer = -1;
  if (cuda_load_functions(&cu, NULL) < 0) return -1;
  if (cuvid_load_functions(&cuvid, NULL) < 0) goto unloaded;
  CUdevice device = 0;
  CUcontext context = NULL;
  if (cu->cuInit(0) != CUDA_SUCCESS ||
      (node && rift_ff_cuda_device(cu, node, &device) != CUDA_SUCCESS) ||
      cu->cuDevicePrimaryCtxRetain(&context, device) != CUDA_SUCCESS) {
    goto unloaded;
  }
  if (cu->cuCtxPushCurrent(context) == CUDA_SUCCESS) {
    CUVIDDECODECAPS caps = {
        .eCodecType = asked,
        .eChromaFormat = cudaVideoChromaFormat_420,
        .nBitDepthMinus8 = 0,
    };
    if (cuvid->cuvidGetDecoderCaps(&caps) == CUDA_SUCCESS) {
      answer = caps.bIsSupported ? 1 : 0;
    }
    CUcontext popped;
    cu->cuCtxPopCurrent(&popped);
  }
  cu->cuDevicePrimaryCtxRelease(device);
unloaded:
  cuvid_free_functions(&cuvid);
  cuda_free_functions(&cu);
  return answer;
}
#endif

int32_t rift_ffdec_send(RiftFfdec* dec, const uint8_t* data, size_t len,
                        int64_t timestamp_us) {
  if (dec->no_gpu_decoder) return AVERROR(ENOSYS);
  if (len == 0 || len > INT32_MAX) return AVERROR(EINVAL);
  // Copied: FFmpeg's decoders read a little past the end of what they are
  // given, which a received frame's own buffer does not leave room for.
  av_packet_unref(dec->packet);
  int err = av_new_packet(dec->packet, (int)len);
  if (err < 0) return err;
  memcpy(dec->packet->data, data, len);
  dec->packet->pts = timestamp_us;
  err = avcodec_send_packet(dec->codec, dec->packet);
  if (dec->no_gpu_decoder) return AVERROR(ENOSYS);
  return err;
}

int32_t rift_ffdec_receive(RiftFfdec* dec, RiftFfdecPicture* picture) {
  memset(picture, 0, sizeof(*picture));
  if (dec->no_gpu_decoder) return AVERROR(ENOSYS);
  int err = avcodec_receive_frame(dec->codec, dec->frame);
  if (err == AVERROR(EAGAIN)) return 0;
  if (err < 0) return err;
  if (dec->frame->format != dec->gpu_format) {
    av_frame_unref(dec->frame);
    return AVERROR(ENOSYS);
  }
  picture->width = dec->frame->width;
  picture->height = dec->frame->height;
  picture->planes = 2;
  picture->matrix = matrix_of(dec->frame->colorspace);
  picture->full_range = dec->frame->color_range == AVCOL_RANGE_JPEG;
  picture->timestamp_us = dec->frame->pts;
  for (int i = 0; i < 4; i++) picture->fds[i] = -1;
#if defined(_WIN32)
  if (dec->gpu_format == AV_PIX_FMT_D3D11) {
    const AVHWFramesContext* frames =
        (const AVHWFramesContext*)dec->frame->hw_frames_ctx->data;
    if (frames->sw_format != AV_PIX_FMT_NV12) {
      // A 10-bit stream: nothing here draws that.
      av_frame_unref(dec->frame);
      return AVERROR(ENOSYS);
    }
    // The frame holds its slice of the decoder's array, which goes back to
    // the pool only when the frame is let go.
    AVFrame* held = av_frame_alloc();
    if (!held) {
      av_frame_unref(dec->frame);
      return AVERROR(ENOMEM);
    }
    av_frame_move_ref(held, dec->frame);
    picture->memory = RIFT_FFDEC_IN_D3D11;
    picture->d3d11_texture = held->data[0];
    picture->d3d11_slice = (int32_t)(intptr_t)held->data[1];
    picture->held = held;
    return 1;
  }
  av_frame_unref(dec->frame);
  return AVERROR(ENOSYS);
#else
  if (dec->gpu_format == AV_PIX_FMT_CUDA) {
    const AVHWFramesContext* frames =
        (const AVHWFramesContext*)dec->frame->hw_frames_ctx->data;
    if (frames->sw_format != AV_PIX_FMT_NV12) {
      // A 10-bit stream: nothing here draws that.
      av_frame_unref(dec->frame);
      return AVERROR(ENOSYS);
    }
    // FFmpeg's NVIDIA decoder has copied the picture out of its own
    // surfaces into a frame of its pool, so holding it holds nothing the
    // decoder waits for.
    AVFrame* held = av_frame_alloc();
    if (!held) {
      av_frame_unref(dec->frame);
      return AVERROR(ENOMEM);
    }
    av_frame_move_ref(held, dec->frame);
    picture->memory = RIFT_FFDEC_IN_CUDA;
    for (int i = 0; i < 2; i++) picture->pitches[i] = (uint32_t)held->linesize[i];
    picture->held = held;
    return 1;
  }
  // The surface, exported as DMA-BUFs: the map holds the decoded frame, so
  // the surface stays the picture's until it is released.
  AVFrame* mapped = av_frame_alloc();
  if (!mapped) {
    av_frame_unref(dec->frame);
    return AVERROR(ENOMEM);
  }
  mapped->format = AV_PIX_FMT_DRM_PRIME;
  err = av_hwframe_map(mapped, dec->frame, AV_HWFRAME_MAP_READ);
  av_frame_unref(dec->frame);
  if (err < 0) {
    av_frame_free(&mapped);
    return err;
  }
  const AVDRMFrameDescriptor* drm = (const AVDRMFrameDescriptor*)mapped->data[0];
  if (drm->nb_layers != 2 || drm->layers[0].format != DRM_R8 ||
      drm->layers[1].format != DRM_GR88) {
    // Not NV12 as two layers: a 10-bit stream, or a driver that exports it
    // otherwise. Nothing here draws that.
    av_frame_free(&mapped);
    return AVERROR(ENOSYS);
  }
  picture->memory = RIFT_FFDEC_IN_DMABUF;
  for (int i = 0; i < 2; i++) {
    const AVDRMLayerDescriptor* layer = &drm->layers[i];
    const AVDRMPlaneDescriptor* plane = &layer->planes[0];
    const AVDRMObjectDescriptor* object = &drm->objects[plane->object_index];
    picture->formats[i] = layer->format;
    picture->fds[i] = object->fd;
    picture->offsets[i] = (uint32_t)plane->offset;
    picture->pitches[i] = (uint32_t)plane->pitch;
    picture->modifiers[i] = object->format_modifier;
  }
  picture->held = mapped;
  return 1;
#endif
}

void rift_ffdec_release(RiftFfdecPicture* picture) {
  if (!picture || !picture->held) return;
  AVFrame* mapped = picture->held;
  av_frame_free(&mapped);
  picture->held = NULL;
}

void rift_ffdec_close(RiftFfdec* dec) {
  if (!dec) return;
  avcodec_free_context(&dec->codec);
  av_packet_free(&dec->packet);
  av_frame_free(&dec->frame);
  av_buffer_unref(&dec->device);
  free(dec);
}

// ── Into the runner's GL textures (Linux) ───────────────────────────────

#if defined(__linux__)

void rift_ffdec_gl_close(RiftFfdecGl* link) {
  if (!link) return;
  if (link->cu && link->context) {
    CUcontext popped;
    link->cu->cuCtxPushCurrent(link->context);
    for (int i = 0; i < 2; i++) {
      if (link->resources[i]) {
        link->cu->cuGraphicsUnregisterResource(link->resources[i]);
      }
    }
    link->cu->cuCtxPopCurrent(&popped);
  }
  av_buffer_unref(&link->device);
  if (link->cu) cuda_free_functions(&link->cu);
  free(link);
}

// `textures` registered with CUDA in `frames`' context, for writing.
static RiftFfdecGl* link_textures(const AVHWFramesContext* frames,
                                  const uint32_t textures[2]) {
  RiftFfdecGl* link = calloc(1, sizeof(*link));
  if (!link) return NULL;
  const AVCUDADeviceContext* cuda = frames->device_ctx->hwctx;
  link->device = av_buffer_ref(frames->device_ref);
  link->context = cuda->cuda_ctx;
  if (!link->device || cuda_load_functions(&link->cu, NULL) < 0) {
    rift_ffdec_gl_close(link);
    return NULL;
  }
  CUcontext popped;
  CUresult result = link->cu->cuCtxPushCurrent(link->context);
  for (int i = 0; i < 2 && result == CUDA_SUCCESS; i++) {
    link->textures[i] = textures[i];
    result = link->cu->cuGraphicsGLRegisterImage(
        &link->resources[i], textures[i], GL_TEXTURE_2D,
        CU_GRAPHICS_REGISTER_FLAGS_WRITE_DISCARD);
    if (result != CUDA_SUCCESS) link->resources[i] = NULL;
  }
  link->cu->cuCtxPopCurrent(&popped);
  if (result != CUDA_SUCCESS) {
    av_log(NULL, AV_LOG_WARNING,
           "ffdec: CUDA would not take the GL textures (CUDA error %d)\n",
           (int)result);
    rift_ffdec_gl_close(link);
    return NULL;
  }
  return link;
}

int32_t rift_ffdec_copy_to_gl(const RiftFfdecPicture* picture,
                              const uint32_t textures[2], RiftFfdecGl** link) {
  if (!picture || !picture->held || picture->memory != RIFT_FFDEC_IN_CUDA ||
      !textures || !link) {
    return AVERROR(EINVAL);
  }
  const AVFrame* frame = picture->held;
  const AVHWFramesContext* frames =
      (const AVHWFramesContext*)frame->hw_frames_ctx->data;
  const AVCUDADeviceContext* cuda = frames->device_ctx->hwctx;
  RiftFfdecGl* kept = *link;
  if (kept && (kept->context != cuda->cuda_ctx ||
               kept->textures[0] != textures[0] ||
               kept->textures[1] != textures[1])) {
    rift_ffdec_gl_close(kept);
    *link = kept = NULL;
  }
  if (!kept) {
    kept = link_textures(frames, textures);
    if (!kept) return AVERROR_EXTERNAL;
    *link = kept;
  }

  CudaFunctions* cu = kept->cu;
  CUcontext popped;
  CUresult result = cu->cuCtxPushCurrent(kept->context);
  if (result != CUDA_SUCCESS) goto done;
  result = cu->cuGraphicsMapResources(2, kept->resources, cuda->stream);
  if (result == CUDA_SUCCESS) {
    CUresult copied = CUDA_SUCCESS;
    for (int i = 0; i < 2 && copied == CUDA_SUCCESS; i++) {
      CUarray array;
      copied = cu->cuGraphicsSubResourceGetMappedArray(&array,
                                                       kept->resources[i], 0, 0);
      if (copied != CUDA_SUCCESS) break;
      // UV is half the size each way, rounded up, two bytes a sample.
      const size_t width = i ? (size_t)(picture->width + 1) / 2 * 2
                             : (size_t)picture->width;
      const size_t height = i ? (size_t)(picture->height + 1) / 2
                              : (size_t)picture->height;
      CUDA_MEMCPY2D copy = {0};
      copy.srcMemoryType = CU_MEMORYTYPE_DEVICE;
      copy.srcDevice = (CUdeviceptr)frame->data[i];
      copy.srcPitch = (size_t)frame->linesize[i];
      copy.dstMemoryType = CU_MEMORYTYPE_ARRAY;
      copy.dstArray = array;
      copy.WidthInBytes = width;
      copy.Height = height;
      copied = cu->cuMemcpy2DAsync(&copy, cuda->stream);
    }
    // On the decoder's stream, so after it wrote the picture; waited for, so
    // the picture can go back to it as soon as this returns.
    if (copied == CUDA_SUCCESS) copied = cu->cuStreamSynchronize(cuda->stream);
    // Unmapping orders the copy before GL's next use of the textures.
    cu->cuGraphicsUnmapResources(2, kept->resources, cuda->stream);
    result = copied;
  }
  cu->cuCtxPopCurrent(&popped);
done:
  if (result != CUDA_SUCCESS) {
    av_log(NULL, AV_LOG_WARNING, "ffdec: CUDA error %d copying a picture\n",
           (int)result);
    return AVERROR_EXTERNAL;
  }
  return 0;
}
#endif
