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

// The GPU APIs this library drives, told apart by the encoder's name: FFmpeg
// names each encoder after the API it drives.
typedef enum Api { API_NONE, API_VAAPI, API_NVENC, API_QSV, API_AMF } Api;

// Pictures kept for an encoder that takes them from memory: one going in, and
// room for the few an encoder still holds while it works.
#define OWN_PICTURES 4

struct RiftFfenc {
  Api api;
  // VAAPI's GPU and its picture pool. NULL for NVENC, QSV and AMF, which
  // take the picture from memory and upload it themselves.
  AVBufferRef* device;
  AVBufferRef* frames;
  AVCodecContext* codec;
  // The caller's picture, described in place: never owns its bytes.
  AVFrame* picture;
  // Pictures in memory the encoder can hold on to, for the encoders that
  // upload them themselves; reused once it lets go.
  AVFrame* own[OWN_PICTURES];
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

static Api api_of(const char* encoder) {
  const char* suffix = strrchr(encoder, '_');
  if (!suffix) return API_NONE;
  if (strcmp(suffix, "_vaapi") == 0) return API_VAAPI;
  if (strcmp(suffix, "_nvenc") == 0) return API_NVENC;
  if (strcmp(suffix, "_qsv") == 0) return API_QSV;
  if (strcmp(suffix, "_amf") == 0) return API_AMF;
  return API_NONE;
}

static void name_driver(RiftFfenc* enc, const AVCodec* codec) {
  snprintf(enc->driver, sizeof(enc->driver), "an unnamed GPU");
  if (!enc->device) {
    // The driver picks the GPU and does not say which; the encoder's own
    // name says whose it is.
    snprintf(enc->driver, sizeof(enc->driver), "%s", codec->long_name);
    return;
  }
#if defined(__linux__)
  AVHWDeviceContext* device = (AVHWDeviceContext*)enc->device->data;
  if (device->type == AV_HWDEVICE_TYPE_VAAPI) {
    AVVAAPIDeviceContext* vaapi = device->hwctx;
    const char* vendor = vaQueryVendorString(vaapi->display);
    if (vendor) snprintf(enc->driver, sizeof(enc->driver), "%s", vendor);
  }
#endif
}

static int64_t peak_of(Api api, int64_t bitrate_bps, int32_t peak_percent) {
  int64_t peak = bitrate_bps * peak_percent / 100;
  // QSV runs constant bitrate whenever the peak equals the average, and has
  // no other way to ask for variable. It counts in kbps, so one kbps more is
  // the least that tells them apart.
  if (api == API_QSV && peak < bitrate_bps + 1000) peak = bitrate_bps + 1000;
  return peak;
}

// The rate, its peak and the buffer they are held over, on the encoder: when
// it opens, and at every move.
static void set_rates(RiftFfenc* enc, int64_t bitrate_bps) {
  AVCodecContext* c = enc->codec;
  c->bit_rate = bitrate_bps;
  c->rc_max_rate = peak_of(enc->api, bitrate_bps, enc->peak_percent);
  // One second of the peak, which is what VAAPI's encoder takes when none is
  // given (and what its patch keeps as the rate moves). Left to itself,
  // FFmpeg's NVENC keeps two seconds of the rate it opened at, whatever the
  // rate moves to. QSV's is set once (open_codec).
  if (enc->api == API_NVENC || enc->api == API_AMF) {
    c->rc_buffer_size = (int)c->rc_max_rate;
  }
}

// Open the encoder itself, on the picture pool when there is one.
static int open_codec(RiftFfenc* enc, const AVCodec* codec,
                      const RiftFfencConfig* config) {
  avcodec_free_context(&enc->codec);
  AVCodecContext* c = avcodec_alloc_context3(codec);
  if (!c) return AVERROR(ENOMEM);
  enc->codec = c;
  c->width = config->width;
  c->height = config->height;
  // Timestamps are the capture's, in microseconds, carried straight through.
  c->time_base = (AVRational){1, 1000000};
  c->framerate = (AVRational){config->fps, 1};
  if (enc->frames) {
    c->pix_fmt = ((AVHWFramesContext*)enc->frames->data)->format;
    c->hw_frames_ctx = av_buffer_ref(enc->frames);
  } else {
    c->pix_fmt = AV_PIX_FMT_NV12;
  }
  c->gop_size = config->gop;
  c->max_b_frames = 0;
  set_rates(enc, config->bitrate_bps);
  if (codec->id == AV_CODEC_ID_H264) {
    // The one profile LiveKit offers for pre-encoded H264. NVENC and QSV
    // read their own option instead, which has no constrained baseline;
    // their baseline uses none of the tools that would make it more.
    c->profile = AV_PROFILE_H264_CONSTRAINED_BASELINE;
    if (enc->api == API_NVENC || enc->api == API_QSV) {
      av_opt_set(c->priv_data, "profile", "baseline", 0);
    }
    // No encoder identification or timing SEI: bytes nobody reads.
    av_opt_set(c->priv_data, "sei", "0", 0);
    // The finest quantiser the GPU may use, as on Windows
    // (media_foundation.rs): with rate to spare a still picture never
    // settles otherwise. Intel re-coded a still 1440p one at 4 Mbps of 20,
    // and at 0.01 with this. Any floor at all moved Intel's rate control:
    // a busy 1440p60 picture asked for 12 Mbps made 13.8 instead of 12.2
    // (Oct 9 2026). What it makes beyond the target is held back before it
    // is encoded (rate_gate.rs). NVENC takes it as its own option.
    if (enc->api == API_NVENC) {
      av_opt_set_int(c->priv_data, "qmin", 18, 0);
    } else {
      c->qmin = 18;
    }
  }
  // Variable bitrate, peaking at the cap: in constant bitrate a GPU pads a
  // still picture with filler to make up the rate (Intel: 8 Mbps of a
  // gradient that needs almost none, Oct 9 2026), and a shared screen is
  // mostly still. QSV has no option for it; its peak decides (peak_of).
  switch (enc->api) {
    case API_VAAPI:
      av_opt_set(c->priv_data, "rc_mode", "VBR", 0);
      break;
    case API_NVENC:
      av_opt_set(c->priv_data, "rc", "vbr", 0);
      break;
    case API_AMF:
      av_opt_set(c->priv_data, "rc", "vbr_peak", 0);
      break;
    default:
      break;
  }
  // One picture in the GPU at a time: each comes out before the next goes
  // in, so the encoder adds no frames of delay.
  av_opt_set(c->priv_data, "async_depth", "1", 0);
  switch (enc->api) {
    case API_NVENC:
      // NVIDIA's settings for streaming: the middle preset, as Rift's own
      // NVENC on Linux uses, tuned for the lowest latency, with no look-ahead
      // and nothing held back.
      av_opt_set(c->priv_data, "preset", "p4", 0);
      av_opt_set(c->priv_data, "tune", "ull", 0);
      av_opt_set(c->priv_data, "zerolatency", "1", 0);
      av_opt_set(c->priv_data, "delay", "0", 0);
      av_opt_set(c->priv_data, "rc-lookahead", "0", 0);
      // A keyframe asked for is one a viewer can start from, not just an
      // intra picture.
      av_opt_set(c->priv_data, "forced-idr", "1", 0);
      break;
    case API_QSV: {
      av_opt_set(c->priv_data, "look_ahead", "0", 0);
      av_opt_set(c->priv_data, "forced_idr", "1", 0);
      // Quick Sync takes a moved rate by resetting itself, and refused any
      // reset that moved the buffer too ("incompatible video parameters",
      // Iris Xe, Oct 9 2026). FFmpeg also sizes the encoder's output from
      // this buffer once, when it opens. So it is one second of the most the
      // rate will reach, and stays.
      int64_t most = config->max_bitrate_bps > config->bitrate_bps
                         ? config->max_bitrate_bps
                         : config->bitrate_bps;
      c->rc_buffer_size = (int)peak_of(API_QSV, most, enc->peak_percent);
      // With the HRD conformance it keeps by default, each reset starts a
      // new sequence with a keyframe, and WebRTC moves the rate every few
      // seconds. Without it the rate moves between two pictures.
      c->strict_std_compliance = FF_COMPLIANCE_UNOFFICIAL;
      break;
    }
    case API_AMF:
      // Without it AMF holds one picture back before handing out the first.
      c->flags |= AV_CODEC_FLAG_LOW_DELAY;
      av_opt_set(c->priv_data, "usage", "ultralowlatency", 0);
      av_opt_set(c->priv_data, "latency", "1", 0);
      av_opt_set(c->priv_data, "preencode", "0", 0);
      av_opt_set(c->priv_data, "forced_idr", "1", 0);
      break;
    default:
      // Not Intel's low-power VAAPI encoder: on Alder Lake it ignored the
      // rate altogether, 22 Mbps whatever was asked (HuC loaded, Oct 9 2026).
      break;
  }
  return avcodec_open2(c, codec, NULL);
}

// VAAPI's GPU and a pool of NV12 pictures on it, the size of the share's.
static int open_device(RiftFfenc* enc, const RiftFfencConfig* config,
                       char* error, size_t error_len) {
  int err = av_hwdevice_ctx_create(&enc->device, AV_HWDEVICE_TYPE_VAAPI,
                                   config->device, NULL, 0);
  if (err < 0) {
    fail(error, error_len, "the GPU did not open", err);
    return err;
  }
  enc->frames = av_hwframe_ctx_alloc(enc->device);
  if (!enc->frames) {
    fail(error, error_len, "no picture pool", AVERROR(ENOMEM));
    return AVERROR(ENOMEM);
  }
  AVHWFramesContext* frames = (AVHWFramesContext*)enc->frames->data;
  frames->format = AV_PIX_FMT_VAAPI;
  frames->sw_format = AV_PIX_FMT_NV12;
  frames->width = config->width;
  frames->height = config->height;
  frames->initial_pool_size = 16;
  err = av_hwframe_ctx_init(enc->frames);
  if (err < 0) {
    fail(error, error_len, "the GPU took no NV12 pictures that size", err);
  }
  return err;
}

RiftFfenc* rift_ffenc_open(const RiftFfencConfig* config, char* error,
                           size_t error_len) {
  if (error && error_len) error[0] = '\0';
  const AVCodec* codec = avcodec_find_encoder_by_name(config->encoder);
  if (!codec) {
    fail(error, error_len, "this build has no such encoder", 0);
    return NULL;
  }
  Api api = api_of(config->encoder);
  if (api == API_NONE) {
    fail(error, error_len, "not a GPU encoder", 0);
    return NULL;
  }

  RiftFfenc* enc = av_mallocz(sizeof(RiftFfenc));
  if (!enc) return NULL;
  enc->api = api;
  enc->peak_percent = config->peak_percent < 100 ? 100 : config->peak_percent;

  if (api == API_VAAPI && open_device(enc, config, error, error_len) < 0) {
    goto fail;
  }
  name_driver(enc, codec);

  int err = open_codec(enc, codec, config);
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
  if (!enc->frames) {
    for (int i = 0; i < OWN_PICTURES; i++) {
      AVFrame* own = enc->own[i] = av_frame_alloc();
      if (!own) err = AVERROR(ENOMEM);
      if (own) {
        own->format = AV_PIX_FMT_NV12;
        own->width = config->width;
        own->height = config->height;
        err = av_frame_get_buffer(own, 0);
      }
      if (err < 0) {
        fail(error, error_len, "out of memory", err);
        goto fail;
      }
    }
  }
  return enc;

fail:
  rift_ffenc_close(enc);
  return NULL;
}

const char* rift_ffenc_driver(const RiftFfenc* enc) { return enc->driver; }

void rift_ffenc_set_bitrate(RiftFfenc* enc, int64_t bitrate_bps) {
  // Read by the encoder before the next picture: by NVENC and QSV
  // themselves, by VAAPI and AMF once patched
  // (third_party/ffmpeg/RIFT_PATCHES.md).
  set_rates(enc, bitrate_bps);
}

int32_t rift_ffenc_send(RiftFfenc* enc, const uint8_t* nv12,
                        int64_t timestamp_us, int32_t keyframe) {
  AVFrame* picture = enc->picture;
  picture->data[0] = (uint8_t*)nv12;
  picture->data[1] = (uint8_t*)nv12 + (size_t)picture->width * picture->height;

  int err;
  if (!enc->frames) {
    // Copied into one of the encoder's own pictures, which it holds by
    // reference until it has uploaded it. Handed the caller's bytes instead,
    // FFmpeg allocated a fresh copy for every picture: at 120 fps, 360 MB a
    // second through Windows' memory manager, and the share process stalled
    // for seconds at a time (Oct 9 2026).
    AVFrame* own = NULL;
    for (int i = 0; i < OWN_PICTURES && !own; i++) {
      if (av_frame_is_writable(enc->own[i])) own = enc->own[i];
    }
    if (!own) {
      // Every one still in the encoder: one more is allocated for this
      // picture, and kept.
      own = enc->own[0];
      err = av_frame_make_writable(own);
      if (err < 0) goto done;
    }
    err = av_frame_copy(own, picture);
    if (err < 0) goto done;
    own->pts = timestamp_us;
    own->pict_type = keyframe ? AV_PICTURE_TYPE_I : AV_PICTURE_TYPE_NONE;
    err = avcodec_send_frame(enc->codec, own);
  } else {
    AVFrame* gpu = av_frame_alloc();
    if (!gpu) return AVERROR(ENOMEM);
    err = av_hwframe_get_buffer(enc->frames, gpu, 0);
    if (err >= 0) err = av_hwframe_transfer_data(gpu, picture, 0);
    if (err >= 0) {
      gpu->pts = timestamp_us;
      gpu->pict_type = keyframe ? AV_PICTURE_TYPE_I : AV_PICTURE_TYPE_NONE;
      err = avcodec_send_frame(enc->codec, gpu);
    }
    av_frame_free(&gpu);
  }
done:
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
  for (int i = 0; i < OWN_PICTURES; i++) av_frame_free(&enc->own[i]);
  avcodec_free_context(&enc->codec);
  av_buffer_unref(&enc->frames);
  av_buffer_unref(&enc->device);
  av_free(enc);
}
