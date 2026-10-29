// Encodes a picture the GPU already holds, the way a Wayland share hands one
// over: a DMA-BUF exported from a VA surface goes to rift_ffenc_send_dmabuf.
// Run by native/ffenc/test.sh on a computer with a VAAPI encoder;
// RIFT_RENDER_NODE picks the GPU, or the first render node that opens one.
#include "ffenc.h"

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <va/va.h>
#include <va/va_drm.h>
#include <va/va_drmcommon.h>

#define SRC_W 1920
#define SRC_H 1080

static int failures;

#define CHECK(cond, ...)                 \
  do {                                   \
    if (!(cond)) {                       \
      fprintf(stderr, "FAIL: " __VA_ARGS__); \
      fprintf(stderr, "\n");             \
      failures++;                        \
    }                                    \
  } while (0)

static void log_line(int32_t level, const char* line) {
  (void)level;
  fprintf(stderr, "ffmpeg: %s\n", line);
}

static RiftFfenc* open_encoder(const char* node, int w, int h, char* error,
                               size_t len) {
  RiftFfencConfig config = {
      .encoder = "h264_vaapi",
      .device = node,
      .width = w,
      .height = h,
      .fps = 60,
      .bitrate_bps = 4000000,
      .peak_percent = 100,
      .gop = 600,
      .max_bitrate_bps = 4000000,
  };
  return rift_ffenc_open(&config, error, len);
}

// Packets the encoder has ready; -1 on a bad one. The encoder holds one
// picture at a time, so each send is drained before the next.
static int drain(RiftFfenc* enc, int* keyframes) {
  int n = 0;
  RiftFfencPacket packet;
  int got;
  while ((got = rift_ffenc_receive(enc, &packet)) == 1) {
    const uint8_t* d = packet.data;
    if (packet.len < 4 || d[0] != 0 || d[1] != 0 ||
        !(d[2] == 1 || (d[2] == 0 && d[3] == 1))) {
      fprintf(stderr, "packet %d has no start code\n", n);
      return -1;
    }
    if (keyframes && packet.keyframe) (*keyframes)++;
    if (keyframes && n == 0 && *keyframes == 0) {
      fprintf(stderr, "the first packet is not a keyframe\n");
      return -1;
    }
    n++;
  }
  return got < 0 ? -1 : n;
}

typedef struct Source {
  VADisplay display;
  int drm_fd;
  VASurfaceID surface;
  VADRMPRIMESurfaceDescriptor prime;
} Source;

// A BGRX surface on the GPU, filled with one colour, exported as a DMA-BUF.
static int make_source(Source* s, const char* node) {
  s->drm_fd = open(node, O_RDWR);
  if (s->drm_fd < 0) return -1;
  s->display = vaGetDisplayDRM(s->drm_fd);
  int major, minor;
  if (vaInitialize(s->display, &major, &minor) != VA_STATUS_SUCCESS) return -1;
  VASurfaceAttrib attr = {
      .type = VASurfaceAttribPixelFormat,
      .flags = VA_SURFACE_ATTRIB_SETTABLE,
      .value = {.type = VAGenericValueTypeInteger, .value.i = VA_FOURCC_BGRX},
  };
  if (vaCreateSurfaces(s->display, VA_RT_FORMAT_RGB32, SRC_W, SRC_H,
                       &s->surface, 1, &attr, 1) != VA_STATUS_SUCCESS) {
    return -1;
  }
  VAImage image;
  if (vaDeriveImage(s->display, s->surface, &image) != VA_STATUS_SUCCESS) {
    return -1;
  }
  uint8_t* pixels;
  if (vaMapBuffer(s->display, image.buf, (void**)&pixels) != VA_STATUS_SUCCESS) {
    return -1;
  }
  for (int y = 0; y < SRC_H; y++) {
    uint32_t* row = (uint32_t*)(pixels + image.offsets[0] + y * image.pitches[0]);
    for (int x = 0; x < SRC_W; x++) row[x] = x < SRC_W / 2 ? 0x00c03020 : 0x002040e0;
  }
  vaUnmapBuffer(s->display, image.buf);
  vaDestroyImage(s->display, image.image_id);
  vaSyncSurface(s->display, s->surface);
  if (vaExportSurfaceHandle(s->display, s->surface,
                            VA_SURFACE_ATTRIB_MEM_TYPE_DRM_PRIME_2,
                            VA_EXPORT_SURFACE_READ_ONLY |
                                VA_EXPORT_SURFACE_COMPOSED_LAYERS,
                            &s->prime) != VA_STATUS_SUCCESS) {
    return -1;
  }
  return 0;
}

static RiftDmabuf dmabuf_of(const Source* s) {
  RiftDmabuf buf = {
      .width = SRC_W,
      .height = SRC_H,
      .drm_format = s->prime.layers[0].drm_format,
      .modifier = s->prime.objects[0].drm_format_modifier,
      .planes = (int32_t)s->prime.layers[0].num_planes,
  };
  for (uint32_t i = 0; i < s->prime.layers[0].num_planes; i++) {
    buf.fds[i] = s->prime.objects[s->prime.layers[0].object_index[i]].fd;
    buf.offsets[i] = s->prime.layers[0].offset[i];
    buf.strides[i] = s->prime.layers[0].pitch[i];
  }
  return buf;
}

// The render node to test on: RIFT_RENDER_NODE, or the first with a VAAPI
// H264 encoder.
static RiftFfenc* find_encoder(char* node, size_t len) {
  char error[256];
  const char* asked = getenv("RIFT_RENDER_NODE");
  if (asked) {
    snprintf(node, len, "%s", asked);
    RiftFfenc* enc = open_encoder(node, 1280, 720, error, sizeof(error));
    if (!enc) fprintf(stderr, "%s: %s\n", node, error);
    return enc;
  }
  for (int i = 128; i < 136; i++) {
    snprintf(node, len, "/dev/dri/renderD%d", i);
    if (access(node, R_OK | W_OK) != 0) continue;
    RiftFfenc* enc = open_encoder(node, 1280, 720, error, sizeof(error));
    if (enc) return enc;
  }
  return NULL;
}

int main(void) {
  rift_ffenc_set_log(log_line, 16 /* AV_LOG_ERROR */);
  char node[64];
  RiftFfenc* enc = find_encoder(node, sizeof(node));
  if (!enc) {
    fprintf(stderr, "no VAAPI encoder to test on\n");
    return 2;
  }
  fprintf(stderr, "on %s (%s)\n", node, rift_ffenc_driver(enc));

  Source src;
  if (make_source(&src, node) < 0) {
    fprintf(stderr, "could not make a DMA-BUF to send\n");
    return 2;
  }
  RiftDmabuf buf = dmabuf_of(&src);
  fprintf(stderr, "source: fourcc %.4s, modifier 0x%llx, %d plane(s)\n",
          (const char*)&buf.drm_format, (unsigned long long)buf.modifier,
          buf.planes);

  CHECK(rift_ffenc_repeat(enc, 0, 1) != 0,
        "repeat before any picture should refuse");

  int packets = 0, keyframes = 0;
  int64_t t = 0;
  for (int i = 0; i < 60; i++, t += 16667) {
    int err = rift_ffenc_send_dmabuf(enc, &buf, NULL, t, i == 0);
    CHECK(err == 0, "send %d returned %d", i, err);
    int got = drain(enc, &keyframes);
    CHECK(got >= 0, "bad packet after send %d", i);
    if (got > 0) packets += got;
  }
  for (int i = 0; i < 5; i++, t += 16667) {
    int err = rift_ffenc_repeat(enc, t, 0);
    CHECK(err == 0, "repeat %d returned %d", i, err);
    int got = drain(enc, &keyframes);
    CHECK(got >= 0, "bad packet after repeat %d", i);
    if (got > 0) packets += got;
  }
  CHECK(packets == 65, "%d packets, not 65", packets);
  CHECK(keyframes >= 1, "no keyframe");

  RiftDmabuf bad = buf;
  bad.modifier = 0xdeadbeef;
  int err = rift_ffenc_send_dmabuf(enc, &bad, NULL, t, 0);
  CHECK(err == RIFT_FFENC_IMPORT_FAILED, "a bad modifier returned %d", err);
  t += 16667;

  // After a refused import the same buffer still goes.
  err = rift_ffenc_send_dmabuf(enc, &buf, NULL, t, 0);
  CHECK(err == 0, "the good buffer after a bad one returned %d", err);
  t += 16667;
  CHECK(drain(enc, NULL) >= 0, "bad packet after the good buffer");

  RiftDmabuf cropped = buf;
  cropped.crop_x = 480;
  cropped.crop_y = 270;
  cropped.crop_width = 960;
  cropped.crop_height = 540;
  err = rift_ffenc_send_dmabuf(enc, &cropped, NULL, t, 0);
  CHECK(err == 0, "a cropped buffer returned %d", err);
  t += 16667;
  CHECK(drain(enc, NULL) >= 0, "bad packet after the cropped buffer");

  RiftRect place = {160, 0, 960, 720};
  err = rift_ffenc_send_dmabuf(enc, &buf, &place, t, 0);
  CHECK(err == 0, "a placed buffer returned %d", err);
  CHECK(drain(enc, NULL) >= 0, "bad packet after the placed buffer");
  rift_ffenc_close(enc);

  char error[256];
  RiftFfenc* tall = open_encoder(node, 1080, 1920, error, sizeof(error));
  CHECK(tall != NULL, "a 1080x1920 encoder did not open: %s", error);
  if (tall) {
    RiftDmabuf turned = buf;
    turned.transform = 1;  // SPA_META_TRANSFORMATION_90
    err = rift_ffenc_send_dmabuf(tall, &turned, NULL, 0, 1);
    CHECK(err == 0, "a turned buffer returned %d", err);
    CHECK(drain(tall, NULL) >= 0, "bad packet after the turned send");
    rift_ffenc_close(tall);
  }

  CHECK(rift_ffenc_abi() == RIFT_FFENC_ABI, "ABI mismatch");

  for (uint32_t i = 0; i < src.prime.num_objects; i++) close(src.prime.objects[i].fd);
  vaDestroySurfaces(src.display, &src.surface, 1);
  vaTerminate(src.display);
  close(src.drm_fd);

  if (failures) {
    fprintf(stderr, "%d failure(s)\n", failures);
    return 1;
  }
  printf("ok: %d packets\n", packets);
  return 0;
}
