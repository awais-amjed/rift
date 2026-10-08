// A GPU encoder through FFmpeg; see ffenc.h.
#include "ffenc.h"

#include <stdio.h>
#include <string.h>

#include <libavcodec/avcodec.h>
#include <libavutil/hwcontext.h>
#include <libavutil/opt.h>
#include <libavutil/pixdesc.h>

#if defined(__linux__)
#include <libavutil/hwcontext_vaapi.h>
#include <va/va.h>
#endif

struct RiftFfenc {
  AVBufferRef* device;
  AVBufferRef* frames;
  AVCodecContext* codec;
  // The caller's picture, described in place: never owns its bytes.
  AVFrame* picture;
  AVPacket* packet;
  int32_t peak_percent;
  char driver[128];
};

static RiftFfencLog log_sink;
static int32_t log_max_level = AV_LOG_WARNING;

static void forward_log(void* avcl, int level, const char* fmt, va_list vl) {
  if (!log_sink || level > log_max_level) return;
  char line[1024];
  static int print_prefix = 1;
  av_log_format_line2(avcl, level, fmt, vl, line, sizeof(line), &print_prefix);
  size_t len = strlen(line);
  while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r')) {
    line[--len] = '\0';
  }
  if (len > 0) log_sink(level, line);
}

int32_t rift_ffenc_abi(void) { return RIFT_FFENC_ABI; }

void rift_ffenc_set_log(RiftFfencLog log, int32_t max_level) {
  log_sink = log;
  log_max_level = max_level;
  av_log_set_level(log ? max_level : AV_LOG_QUIET);
  av_log_set_callback(log ? forward_log : av_log_default_callback);
}

static void fail(char* error, size_t error_len, const char* what, int err) {
  if (!error || error_len == 0) return;
  if (err < 0) {
    char reason[AV_ERROR_MAX_STRING_SIZE];
    av_strerror(err, reason, sizeof(reason));
    snprintf(error, error_len, "%s: %s", what, reason);
  } else {
    snprintf(error, error_len, "%s", what);
  }
}

// The hardware an encoder runs on, from its name: FFmpeg names each after
// the API it drives.
static enum AVHWDeviceType device_type_for(const char* encoder) {
  const char* suffix = strrchr(encoder, '_');
  if (suffix && strcmp(suffix, "_vaapi") == 0) return AV_HWDEVICE_TYPE_VAAPI;
  return AV_HWDEVICE_TYPE_NONE;
}

// The pixel format FFmpeg gives pictures held on that hardware.
static enum AVPixelFormat hardware_format(enum AVHWDeviceType type) {
  switch (type) {
    case AV_HWDEVICE_TYPE_VAAPI:
      return AV_PIX_FMT_VAAPI;
    default:
      return AV_PIX_FMT_NONE;
  }
}

static void name_driver(RiftFfenc* enc) {
  snprintf(enc->driver, sizeof(enc->driver), "an unnamed GPU");
#if defined(__linux__)
  AVHWDeviceContext* device = (AVHWDeviceContext*)enc->device->data;
  if (device->type == AV_HWDEVICE_TYPE_VAAPI) {
    AVVAAPIDeviceContext* vaapi = device->hwctx;
    const char* vendor = vaQueryVendorString(vaapi->display);
    if (vendor) snprintf(enc->driver, sizeof(enc->driver), "%s", vendor);
  }
#endif
}

static int64_t peak_of(int64_t bitrate_bps, int32_t peak_percent) {
  return bitrate_bps * peak_percent / 100;
}

// Open the encoder itself on the picture pool.
static int open_codec(RiftFfenc* enc, const AVCodec* codec,
                      const RiftFfencConfig* config) {
  avcodec_free_context(&enc->codec);
  AVCodecContext* c = avcodec_alloc_context3(codec);
  if (!c) return AVERROR(ENOMEM);
  enc->codec = c;
  AVHWFramesContext* frames = (AVHWFramesContext*)enc->frames->data;
  c->width = config->width;
  c->height = config->height;
  // Timestamps are the capture's, in microseconds, carried straight through.
  c->time_base = (AVRational){1, 1000000};
  c->framerate = (AVRational){config->fps, 1};
  c->pix_fmt = frames->format;
  c->hw_frames_ctx = av_buffer_ref(enc->frames);
  c->gop_size = config->gop;
  c->max_b_frames = 0;
  c->bit_rate = config->bitrate_bps;
  c->rc_max_rate = peak_of(config->bitrate_bps, enc->peak_percent);
  if (codec->id == AV_CODEC_ID_H264) {
    // The one profile LiveKit offers for pre-encoded H264.
    c->profile = AV_PROFILE_H264_CONSTRAINED_BASELINE;
    // No encoder identification or timing SEI: bytes nobody reads.
    av_opt_set(c->priv_data, "sei", "0", 0);
    // The finest quantiser the GPU may use, as on Windows
    // (media_foundation.rs): with rate to spare a still picture never
    // settles otherwise. Intel re-coded a still 1440p one at 4 Mbps of 20,
    // and at 0.01 with this. Any floor at all moved Intel's rate control:
    // a busy 1440p60 picture asked for 12 Mbps made 13.8 instead of 12.2
    // (Oct 9 2026). What it makes beyond the target is held back before it
    // is encoded (rate_gate.rs).
    c->qmin = 18;
  }
  // Variable bitrate, peaking at the cap: in constant bitrate a GPU pads a
  // still picture with filler to make up the rate (Intel: 8 Mbps of a
  // gradient that needs almost none, Oct 9 2026), and a shared screen is
  // mostly still.
  av_opt_set(c->priv_data, "rc_mode", "VBR", 0);
  // One picture in the GPU at a time: each comes out before the next goes
  // in, so the encoder adds no frames of delay.
  av_opt_set(c->priv_data, "async_depth", "1", 0);
  // Not Intel's low-power encoder: on Alder Lake it ignored the rate
  // altogether, 22 Mbps whatever was asked (HuC loaded, Oct 9 2026).
  return avcodec_open2(c, codec, NULL);
}

RiftFfenc* rift_ffenc_open(const RiftFfencConfig* config, char* error,
                           size_t error_len) {
  if (error && error_len) error[0] = '\0';
  const AVCodec* codec = avcodec_find_encoder_by_name(config->encoder);
  if (!codec) {
    fail(error, error_len, "this build has no such encoder", 0);
    return NULL;
  }
  enum AVHWDeviceType type = device_type_for(config->encoder);
  if (type == AV_HWDEVICE_TYPE_NONE) {
    fail(error, error_len, "not a GPU encoder", 0);
    return NULL;
  }

  RiftFfenc* enc = av_mallocz(sizeof(RiftFfenc));
  if (!enc) return NULL;
  enc->peak_percent = config->peak_percent < 100 ? 100 : config->peak_percent;

  int err = av_hwdevice_ctx_create(&enc->device, type, config->device, NULL, 0);
  if (err < 0) {
    fail(error, error_len, "the GPU did not open", err);
    goto fail;
  }
  name_driver(enc);

  enc->frames = av_hwframe_ctx_alloc(enc->device);
  if (!enc->frames) {
    fail(error, error_len, "no picture pool", AVERROR(ENOMEM));
    goto fail;
  }
  AVHWFramesContext* frames = (AVHWFramesContext*)enc->frames->data;
  frames->format = hardware_format(type);
  frames->sw_format = AV_PIX_FMT_NV12;
  frames->width = config->width;
  frames->height = config->height;
  frames->initial_pool_size = 16;
  err = av_hwframe_ctx_init(enc->frames);
  if (err < 0) {
    fail(error, error_len, "the GPU took no NV12 pictures that size", err);
    goto fail;
  }

  err = open_codec(enc, codec, config);
  if (err < 0) {
    fail(error, error_len, "the encoder did not open", err);
    goto fail;
  }

  enc->picture = av_frame_alloc();
  enc->packet = av_packet_alloc();
  if (!enc->picture || !enc->packet) {
    fail(error, error_len, "out of memory", AVERROR(ENOMEM));
    goto fail;
  }
  enc->picture->format = AV_PIX_FMT_NV12;
  enc->picture->width = config->width;
  enc->picture->height = config->height;
  enc->picture->linesize[0] = config->width;
  enc->picture->linesize[1] = config->width;
  return enc;

fail:
  rift_ffenc_close(enc);
  return NULL;
}

const char* rift_ffenc_driver(const RiftFfenc* enc) { return enc->driver; }

void rift_ffenc_set_bitrate(RiftFfenc* enc, int64_t bitrate_bps) {
  // Read by the patched VAAPI encoder before the next picture
  // (third_party/ffmpeg/RIFT_PATCHES.md).
  enc->codec->bit_rate = bitrate_bps;
  enc->codec->rc_max_rate = peak_of(bitrate_bps, enc->peak_percent);
}

int32_t rift_ffenc_send(RiftFfenc* enc, const uint8_t* nv12,
                        int64_t timestamp_us, int32_t keyframe) {
  AVFrame* picture = enc->picture;
  picture->data[0] = (uint8_t*)nv12;
  picture->data[1] = (uint8_t*)nv12 + (size_t)picture->width * picture->height;

  AVFrame* gpu = av_frame_alloc();
  if (!gpu) return AVERROR(ENOMEM);
  int err = av_hwframe_get_buffer(enc->frames, gpu, 0);
  if (err >= 0) err = av_hwframe_transfer_data(gpu, picture, 0);
  if (err >= 0) {
    gpu->pts = timestamp_us;
    gpu->pict_type = keyframe ? AV_PICTURE_TYPE_I : AV_PICTURE_TYPE_NONE;
    err = avcodec_send_frame(enc->codec, gpu);
  }
  av_frame_free(&gpu);
  picture->data[0] = NULL;
  picture->data[1] = NULL;
  return err < 0 ? err : 0;
}

int32_t rift_ffenc_receive(RiftFfenc* enc, RiftFfencPacket* packet) {
  av_packet_unref(enc->packet);
  int err = avcodec_receive_packet(enc->codec, enc->packet);
  if (err == AVERROR(EAGAIN) || err == AVERROR_EOF) return 0;
  if (err < 0) return err;
  packet->data = enc->packet->data;
  packet->len = (size_t)enc->packet->size;
  packet->timestamp_us = enc->packet->pts;
  packet->keyframe = (enc->packet->flags & AV_PKT_FLAG_KEY) != 0;
  return 1;
}

void rift_ffenc_close(RiftFfenc* enc) {
  if (!enc) return;
  av_packet_free(&enc->packet);
  av_frame_free(&enc->picture);
  avcodec_free_context(&enc->codec);
  av_buffer_unref(&enc->frames);
  av_buffer_unref(&enc->device);
  av_free(enc);
}
