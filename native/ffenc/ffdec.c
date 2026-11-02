// A watched share's pictures decoded on the GPU (ffdec.h).
#include "ffdec.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <libavcodec/avcodec.h>
#include <libavutil/hwcontext.h>
#include <libavutil/hwcontext_drm.h>

#include "ff_shared.h"

// Surfaces past what the decoder needs for its references: the newest
// picture waiting for the runner, the one it is drawing, and one on its way
// between the two. Without them the decoder would wait for one back.
#define LENT_PICTURES 4

// DRM's fourccs for NV12's two planes, as their own layers (drm_fourcc.h,
// which the library does not otherwise need).
#define FOURCC(a, b, c, d)                                    \
  ((uint32_t)(a) | ((uint32_t)(b) << 8) | ((uint32_t)(c) << 16) | \
   ((uint32_t)(d) << 24))
#define DRM_R8 FOURCC('R', '8', ' ', ' ')
#define DRM_GR88 FOURCC('G', 'R', '8', '8')

struct RiftFfdec {
  AVBufferRef* device;
  AVCodecContext* codec;
  AVPacket* packet;
  AVFrame* frame;
  // The GPU had no decoder for the stream, said while choosing how to
  // decode it.
  int no_gpu_decoder;
  char driver[128];
};

static enum AVCodecID codec_id_of(int32_t codec) {
  switch (codec) {
    case RIFT_FFDEC_H264:
      return AV_CODEC_ID_H264;
    case RIFT_FFDEC_VP8:
      return AV_CODEC_ID_VP8;
    case RIFT_FFDEC_VP9:
      return AV_CODEC_ID_VP9;
    default:
      return AV_CODEC_ID_NONE;
  }
}

// FFmpeg offers the GPU's format first when its hwaccel can take the stream,
// and asks again without it when the GPU then refuses. Software is never
// chosen: decoding it here would cost the CPU what the call's own path
// already costs, without that path's years of use.
static enum AVPixelFormat gpu_only(AVCodecContext* codec,
                                   const enum AVPixelFormat* formats) {
  for (const enum AVPixelFormat* f = formats; *f != AV_PIX_FMT_NONE; f++) {
    if (*f == AV_PIX_FMT_VAAPI) return *f;
  }
  RiftFfdec* dec = codec->opaque;
  dec->no_gpu_decoder = 1;
  return AV_PIX_FMT_NONE;
}

RiftFfdec* rift_ffdec_open(const RiftFfdecConfig* config, char* error,
                           size_t error_len) {
  const AVCodec* codec = avcodec_find_decoder(codec_id_of(config->codec));
  if (!codec) {
    rift_ff_fail(error, error_len, "no decoder for that codec", 0);
    return NULL;
  }
  RiftFfdec* dec = calloc(1, sizeof(*dec));
  if (!dec) {
    rift_ff_fail(error, error_len, "out of memory", AVERROR(ENOMEM));
    return NULL;
  }
  int err = av_hwdevice_ctx_create(&dec->device, AV_HWDEVICE_TYPE_VAAPI,
                                   config->device, NULL, 0);
  if (err < 0) {
    rift_ff_fail(error, error_len, "the GPU did not open", err);
    goto failed;
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
  snprintf(dec->driver, sizeof(dec->driver), "an unnamed GPU");
  const char* vendor = rift_ff_vaapi_vendor(dec->device);
  if (vendor) snprintf(dec->driver, sizeof(dec->driver), "%s", vendor);
  return dec;

failed:
  rift_ffdec_close(dec);
  return NULL;
}

const char* rift_ffdec_driver(const RiftFfdec* dec) { return dec->driver; }

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
  int err = avcodec_receive_frame(dec->codec, dec->frame);
  if (err == AVERROR(EAGAIN)) return 0;
  if (err < 0) return err;
  if (dec->frame->format != AV_PIX_FMT_VAAPI) {
    av_frame_unref(dec->frame);
    return AVERROR(ENOSYS);
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
  const int64_t pts = dec->frame->pts;
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
  picture->width = mapped->width;
  picture->height = mapped->height;
  picture->planes = 2;
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
  picture->timestamp_us = pts;
  picture->held = mapped;
  return 1;
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
