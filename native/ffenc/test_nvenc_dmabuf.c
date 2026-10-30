// A share's DMA-BUF through NVENC's GL path (nvenc_gl.c), on real GBM buffers
// drawn with GL. Writes each stream to the folder it is given, for
// check_nvenc.py to decode, and prints what a picture cost. Run by
// native/ffenc/test.sh on a computer whose card draws through NVIDIA's driver;
// RIFT_RENDER_NODE picks the card, or the first render node the path opens on.
// Exits 2 with no such card. `--exit-open` returns from main with an encoder
// open, which must end at once.
#include "ffenc.h"

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <GLES2/gl2ext.h>
#include <drm_fourcc.h>
#include <gbm.h>

#define BUFFERS 4
#define AVERROR_ENOSYS (-38)

static int failures;

#define CHECK(cond, ...)                     \
  do {                                       \
    if (!(cond)) {                           \
      fprintf(stderr, "FAIL: " __VA_ARGS__); \
      fprintf(stderr, "\n");                 \
      failures++;                            \
    }                                        \
  } while (0)

static void log_line(int32_t level, const char* line) {
  (void)level;
  fprintf(stderr, "ffmpeg: %s\n", line);
}

static double now_ms(clockid_t clock) {
  struct timespec t;
  clock_gettime(clock, &t);
  return (double)t.tv_sec * 1e3 + (double)t.tv_nsec / 1e6;
}

// ── Drawing ─────────────────────────────────────────────────────────────

static struct gbm_device* gbm;
static EGLDisplay display;
static EGLContext context;
static PFNEGLQUERYDMABUFMODIFIERSEXTPROC query_modifiers;
static PFNGLEGLIMAGETARGETTEXTURE2DOESPROC image_target;

typedef struct Buffer {
  struct gbm_bo* bo;
  int fd;
  GLuint framebuffer;
  RiftDmabuf dmabuf;
} Buffer;

static void open_drawing(const char* node) {
  gbm = gbm_create_device(open(node, O_RDWR));
  display = eglGetPlatformDisplay(EGL_PLATFORM_GBM_KHR, gbm, NULL);
  eglInitialize(display, NULL, NULL);
  eglBindAPI(EGL_OPENGL_ES_API);
  static const EGLint attributes[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
  context = eglCreateContext(display, EGL_NO_CONFIG_KHR, EGL_NO_CONTEXT, attributes);
  query_modifiers = (PFNEGLQUERYDMABUFMODIFIERSEXTPROC)eglGetProcAddress(
      "eglQueryDmaBufModifiersEXT");
  image_target = (PFNGLEGLIMAGETARGETTEXTURE2DOESPROC)eglGetProcAddress(
      "glEGLImageTargetTexture2DOES");
}

static void make_drawing_current(void) {
  eglBindAPI(EGL_OPENGL_ES_API);
  eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, context);
}

// A buffer of `family`, 0x606 (linear blocks) or 0xe08 (compressed), found in the
// modifier's bits NVIDIA keeps its kind in. 0 when this card has none that way.
static int make_buffer(Buffer* b, int width, int height, uint32_t fourcc, int family) {
  make_drawing_current();
  EGLuint64KHR modifiers[64];
  EGLBoolean external[64];
  EGLint count = 0;
  uint64_t use[64];
  int used = 0;
  query_modifiers(display, (EGLint)fourcc, 64, modifiers, external, &count);
  for (int i = 0; i < count; i++) {
    if (!external[i] && modifiers[i] != 0 &&
        (int)((modifiers[i] >> 12) & 0xfff) == family) {
      use[used++] = modifiers[i];
    }
  }
  if (!used) return 0;
  b->bo = gbm_bo_create_with_modifiers2(gbm, (uint32_t)width, (uint32_t)height, fourcc,
                                        use, (unsigned)used, GBM_BO_USE_RENDERING);
  if (!b->bo) return 0;
  b->fd = gbm_bo_get_fd(b->bo);
  memset(&b->dmabuf, 0, sizeof(b->dmabuf));
  b->dmabuf.width = width;
  b->dmabuf.height = height;
  b->dmabuf.drm_format = fourcc;
  b->dmabuf.modifier = gbm_bo_get_modifier(b->bo);
  b->dmabuf.planes = 1;
  b->dmabuf.fds[0] = b->fd;
  b->dmabuf.offsets[0] = gbm_bo_get_offset(b->bo, 0);
  b->dmabuf.strides[0] = gbm_bo_get_stride(b->bo);

  EGLAttrib attributes[] = {
      EGL_WIDTH, width, EGL_HEIGHT, height,
      EGL_LINUX_DRM_FOURCC_EXT, (EGLAttrib)fourcc,
      EGL_DMA_BUF_PLANE0_FD_EXT, b->fd,
      EGL_DMA_BUF_PLANE0_OFFSET_EXT, (EGLAttrib)b->dmabuf.offsets[0],
      EGL_DMA_BUF_PLANE0_PITCH_EXT, (EGLAttrib)b->dmabuf.strides[0],
      EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT, (EGLAttrib)(b->dmabuf.modifier & 0xffffffff),
      EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT, (EGLAttrib)(b->dmabuf.modifier >> 32),
      EGL_NONE};
  EGLImage image = eglCreateImage(display, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, NULL, attributes);
  if (image == EGL_NO_IMAGE) return 0;
  GLuint texture;
  glGenTextures(1, &texture);
  glBindTexture(GL_TEXTURE_2D, texture);
  image_target(GL_TEXTURE_2D, image);
  glGenFramebuffers(1, &b->framebuffer);
  glBindFramebuffer(GL_FRAMEBUFFER, b->framebuffer);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);
  return glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
}

static void rect(int x, int y, int w, int h, float r, float g, float b) {
  glScissor(x, y, w, h);
  glClearColor(r, g, b, 1);
  glClear(GL_COLOR_BUFFER_BIT);
}

// Red, green, blue and gray quarters, red in the buffer's first rows and columns,
// with a white bar `bar` pixels across when it is not negative. Finished before
// it returns: a compositor's sync stands in for this in a real share.
static void draw(const Buffer* b, int bar) {
  int w = b->dmabuf.width, h = b->dmabuf.height;
  make_drawing_current();
  glBindFramebuffer(GL_FRAMEBUFFER, b->framebuffer);
  glEnable(GL_SCISSOR_TEST);
  rect(0, 0, w / 2, h / 2, 1, 0, 0);
  rect(w / 2, 0, w - w / 2, h / 2, 0, 1, 0);
  rect(0, h / 2, w / 2, h - h / 2, 0, 0, 1);
  rect(w / 2, h / 2, w - w / 2, h - h / 2, 0.5f, 0.5f, 0.5f);
  if (bar >= 0) rect(bar, 0, 40, h, 1, 1, 1);
  glDisable(GL_SCISSOR_TEST);
  glFinish();
}

// ── The encoder ─────────────────────────────────────────────────────────

static const char* node;
static const char* out_dir;

static RiftFfenc* open_encoder(int width, int height) {
  char error[256] = "";
  RiftFfencConfig config = {
      .encoder = "h264_nvenc",
      .device = node,
      .width = width,
      .height = height,
      .fps = 60,
      .bitrate_bps = 15000000,
      .peak_percent = 100,
      .gop = 6000,
      .max_bitrate_bps = 15000000,
  };
  RiftFfenc* enc = rift_ffenc_open(&config, error, sizeof(error));
  if (!enc) fprintf(stderr, "%s: %s\n", node, error);
  return enc;
}

typedef struct Stream {
  FILE* file;
  int packets;
  int keyframes;
} Stream;

static Stream open_stream(const char* name) {
  char path[512];
  snprintf(path, sizeof(path), "%s/%s.h264", out_dir, name);
  Stream stream = {fopen(path, "wb"), 0, 0};
  return stream;
}

static void drain(RiftFfenc* enc, Stream* stream) {
  RiftFfencPacket packet;
  int got;
  while ((got = rift_ffenc_receive(enc, &packet)) == 1) {
    fwrite(packet.data, 1, packet.len, stream->file);
    stream->packets++;
    if (packet.keyframe) stream->keyframes++;
  }
  CHECK(got == 0, "receive said %d", got);
}

static void send(RiftFfenc* enc, const Buffer* b, const RiftRect* place, int picture, Stream* stream) {
  int err = rift_ffenc_send_dmabuf(enc, &b->dmabuf, place, picture * 16667, picture == 0);
  CHECK(err == 0, "send_dmabuf said %d", err);
  drain(enc, stream);
}

// ── The cases ───────────────────────────────────────────────────────────

// The moving bar, 660 pictures at 1080p, in four buffers taken in turn as a
// compositor's are. Paced at 60 fps when `paced`, to read its cost.
static void moving_bar(const char* name, uint32_t fourcc, int family, int paced) {
  Buffer buffers[BUFFERS];
  for (int i = 0; i < BUFFERS; i++) {
    if (!make_buffer(&buffers[i], 1920, 1080, fourcc, family)) {
      fprintf(stderr, "%s: no buffer of this kind here\n", name);
      failures++;
      return;
    }
  }
  fprintf(stderr, "%s: modifier 0x%llx\n", name, (unsigned long long)buffers[0].dmabuf.modifier);
  RiftFfenc* enc = open_encoder(1920, 1080);
  CHECK(enc && rift_ffenc_takes_dmabuf(enc), "%s: no GL path", name);
  if (!enc) return;
  Stream stream = open_stream(name);
  double wall = 0, cpu = 0, worst = 0;
  double next = now_ms(CLOCK_MONOTONIC);
  for (int i = 0; i < 660; i++) {
    if (paced) {
      next += 1000.0 / 60.0;
      double wait = next - now_ms(CLOCK_MONOTONIC);
      if (wait > 0) {
        struct timespec sleep_for = {0, (long)(wait * 1e6)};
        nanosleep(&sleep_for, NULL);
      }
    }
    const Buffer* b = &buffers[i % BUFFERS];
    draw(b, (i * 8) % (1920 - 40));
    double wall_at = now_ms(CLOCK_MONOTONIC), cpu_at = now_ms(CLOCK_THREAD_CPUTIME_ID);
    send(enc, b, NULL, i, &stream);
    double took = now_ms(CLOCK_MONOTONIC) - wall_at;
    if (i >= 60) {
      wall += took;
      cpu += now_ms(CLOCK_THREAD_CPUTIME_ID) - cpu_at;
      if (took > worst) worst = took;
    }
  }
  fclose(stream.file);
  CHECK(stream.packets == 660, "%s: %d packets", name, stream.packets);
  if (paced) {
    printf("%s: send %.2f ms a picture, worst %.2f ms, CPU %.2f ms a picture (%.1f%% of a core at 60 fps)\n",
           name, wall / 600, worst, cpu / 600, cpu / 600 * 60 / 10);
  }
  rift_ffenc_close(enc);
}

// A still picture of quarters, a few times over, for the decoder to settle on.
static void still(const char* name, int width, int height, int out_w, int out_h,
                  const RiftRect* crop, const RiftRect* place, int transform) {
  Buffer b;
  if (!make_buffer(&b, width, height, DRM_FORMAT_XRGB8888, 0x606)) {
    fprintf(stderr, "%s: no buffer\n", name);
    failures++;
    return;
  }
  b.dmabuf.transform = transform;
  if (crop) {
    b.dmabuf.crop_x = crop->x;
    b.dmabuf.crop_y = crop->y;
    b.dmabuf.crop_width = crop->width;
    b.dmabuf.crop_height = crop->height;
  }
  RiftFfenc* enc = open_encoder(out_w, out_h);
  CHECK(enc && rift_ffenc_takes_dmabuf(enc), "%s: no GL path", name);
  if (!enc) return;
  Stream stream = open_stream(name);
  draw(&b, -1);
  for (int i = 0; i < 30; i++) send(enc, &b, place, i, &stream);
  fclose(stream.file);
  CHECK(stream.packets == 30, "%s: %d packets", name, stream.packets);
  rift_ffenc_close(enc);
}

// The last picture again, and as a keyframe when asked.
static void repeat(void) {
  Buffer b;
  if (!make_buffer(&b, 1920, 1080, DRM_FORMAT_XRGB8888, 0x606)) {
    failures++;
    return;
  }
  RiftFfenc* enc = open_encoder(1920, 1080);
  if (!enc) {
    failures++;
    return;
  }
  CHECK(rift_ffenc_repeat(enc, 0, 1) != 0, "repeat before any picture should refuse");
  Stream stream = open_stream("repeat");
  draw(&b, -1);
  int i = 0;
  for (; i < 20; i++) send(enc, &b, NULL, i, &stream);
  for (; i < 30; i++) {
    int err = rift_ffenc_repeat(enc, i * 16667, 0);
    CHECK(err == 0, "repeat said %d", err);
    drain(enc, &stream);
  }
  int before = stream.keyframes;
  int err = rift_ffenc_repeat(enc, i * 16667, 1);
  CHECK(err == 0, "keyframe repeat said %d", err);
  drain(enc, &stream);
  CHECK(stream.keyframes == before + 1, "a repeat asked to be a keyframe was not");
  fclose(stream.file);
  CHECK(stream.packets == 31, "repeat: %d packets", stream.packets);
  rift_ffenc_close(enc);
}

// Pictures from memory on the same encoder, then the GPU's again: a share that
// moved between the two keeps its encoder.
static void memory_between(void) {
  Buffer b;
  if (!make_buffer(&b, 1920, 1080, DRM_FORMAT_XRGB8888, 0x606)) {
    failures++;
    return;
  }
  RiftFfenc* enc = open_encoder(1920, 1080);
  if (!enc) {
    failures++;
    return;
  }
  size_t size = 1920 * 1080 * 3 / 2;
  uint8_t* nv12 = malloc(size);
  memset(nv12, 200, 1920 * 1080);
  for (size_t i = 1920 * 1080; i + 1 < size; i += 2) {
    nv12[i] = 100;
    nv12[i + 1] = 150;
  }
  Stream stream = open_stream("memory");
  draw(&b, -1);
  int i = 0;
  for (; i < 30; i++) send(enc, &b, NULL, i, &stream);
  for (; i < 60; i++) {
    int err = rift_ffenc_send(enc, nv12, i * 16667, 0);
    CHECK(err == 0, "send said %d", err);
    drain(enc, &stream);
  }
  for (; i < 90; i++) send(enc, &b, NULL, i, &stream);
  fclose(stream.file);
  CHECK(stream.packets == 90, "memory: %d packets", stream.packets);
  free(nv12);
  rift_ffenc_close(enc);
}

// With the GL path refused: memory only, as if it had never been.
static void refused(void) {
  setenv("RIFT_FFENC_NO_GL", "1", 1);
  RiftFfenc* enc = open_encoder(1920, 1080);
  unsetenv("RIFT_FFENC_NO_GL");
  CHECK(enc != NULL, "NO_GL: the encoder should still open");
  if (!enc) return;
  CHECK(rift_ffenc_takes_dmabuf(enc) == 0, "NO_GL: takes DMA-BUFs");
  RiftDmabuf none = {.width = 1920, .height = 1080};
  CHECK(rift_ffenc_send_dmabuf(enc, &none, NULL, 0, 1) == AVERROR_ENOSYS,
        "NO_GL: send_dmabuf should be ENOSYS");
  size_t size = 1920 * 1080 * 3 / 2;
  uint8_t* nv12 = malloc(size);
  memset(nv12, 128, size);
  Stream stream = open_stream("refused");
  for (int i = 0; i < 10; i++) {
    CHECK(rift_ffenc_send(enc, nv12, i * 16667, 0) == 0, "NO_GL: memory refused");
    drain(enc, &stream);
  }
  fclose(stream.file);
  CHECK(stream.packets == 10, "NO_GL: %d packets", stream.packets);
  free(nv12);
  rift_ffenc_close(enc);
}

static const char* find_node(void) {
  static char path[64];
  const char* asked = getenv("RIFT_RENDER_NODE");
  for (int i = 128; i < 136; i++) {
    if (asked) {
      snprintf(path, sizeof(path), "%s", asked);
    } else {
      snprintf(path, sizeof(path), "/dev/dri/renderD%d", i);
      if (access(path, R_OK | W_OK) != 0) continue;
    }
    node = path;
    RiftFfenc* enc = open_encoder(1280, 720);
    int takes = enc && rift_ffenc_takes_dmabuf(enc);
    if (enc) rift_ffenc_close(enc);
    if (takes) return path;
    if (asked) break;
  }
  return NULL;
}

int main(int argc, char** argv) {
  rift_ffenc_set_log(log_line, 24 /* AV_LOG_WARNING */);
  if (argc < 2) {
    fprintf(stderr, "usage: test_nvenc_dmabuf OUT_DIR | --exit-open\n");
    return 1;
  }
  node = NULL;
  if (!find_node()) {
    fprintf(stderr, "no card here takes NVENC's GL path\n");
    return 2;
  }
  fprintf(stderr, "on %s\n", node);

  if (strcmp(argv[1], "--exit-open") == 0) {
    RiftFfenc* enc = open_encoder(1280, 720);
    if (!enc) return 1;
    open_drawing(node);
    Buffer b;
    if (!make_buffer(&b, 1280, 720, DRM_FORMAT_XRGB8888, 0x606)) return 1;
    draw(&b, -1);
    int err = rift_ffenc_send_dmabuf(enc, &b.dmabuf, NULL, 0, 1);
    fprintf(stderr, "returning from main with an encoder open (%d)\n", err);
    return err == 0 ? 0 : 1;
  }

  out_dir = argv[1];
  open_drawing(node);

  moving_bar("bar_606_xrgb", DRM_FORMAT_XRGB8888, 0x606, 1);
  moving_bar("bar_e08_xrgb", DRM_FORMAT_XRGB8888, 0xe08, 0);
  moving_bar("bar_606_xbgr", DRM_FORMAT_XBGR8888, 0x606, 0);
  moving_bar("bar_e08_xbgr", DRM_FORMAT_XBGR8888, 0xe08, 0);

  still("scaled", 2560, 1440, 1920, 1080, NULL, NULL, 0);
  RiftRect bars = {285, 0, 1350, 1080};
  still("letterbox", 1000, 800, 1920, 1080, NULL, &bars, 0);
  // A corner of the red quarter, in a small place: everything else stays black.
  RiftRect crop = {3, 5, 200, 100};
  RiftRect odd = {1, 1, 101, 51};
  still("place", 640, 360, 640, 360, &crop, &odd, 0);
  still("turned", 1920, 1080, 1080, 1920, NULL, NULL, 1);

  repeat();
  memory_between();
  refused();

  if (failures) {
    fprintf(stderr, "%d failed\n", failures);
    return 1;
  }
  puts("nvenc dmabuf: ok");
  return 0;
}
