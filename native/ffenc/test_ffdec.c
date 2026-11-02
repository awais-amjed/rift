// Decodes on the GPU what the GPU encoded, and draws it the way the runner
// draws a watched share (linux/runner/stream_texture.cc): from VAAPI, each
// plane of the decoded DMA-BUF imported into EGL as a texture of its own; from
// NVIDIA's decoder, each plane copied by CUDA into a GL texture of the
// runner's kind (rift_ffdec_copy_to_gl); then one shader turning NV12 into
// colour. Four coloured quarters go in, and the same four must come out, at
// the size sent though H264 codes 1080 lines as 1088.
// Run by native/ffenc/test.sh on a computer with a VAAPI encoder and decoder,
// and again with `cuda` on one with NVENC and NVIDIA's decoder;
// RIFT_RENDER_NODE picks the GPU.
#include "ffdec.h"

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
// After gl3.h, which defines what it needs.
#include <GLES2/gl2ext.h>
#include <drm_fourcc.h>
#include <gbm.h>

#define W 1920
#define H 1080
#define PICTURES 30

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

// ── The picture sent ────────────────────────────────────────────────────

// BT.601 in limited range, as the runner reads it: red, green, blue, white.
static const uint8_t kYuv[4][3] = {
    {81, 90, 240}, {145, 54, 34}, {41, 240, 110}, {235, 128, 128}};
static const uint8_t kRgb[4][3] = {
    {255, 0, 0}, {0, 255, 0}, {0, 0, 255}, {255, 255, 255}};

static int quarter_of(int x, int y) { return (y >= H / 2) * 2 + (x >= W / 2); }

static void fill(uint8_t* nv12) {
  for (int y = 0; y < H; y++) {
    for (int x = 0; x < W; x++) nv12[y * W + x] = kYuv[quarter_of(x, y)][0];
  }
  uint8_t* uv = nv12 + W * H;
  for (int y = 0; y < H / 2; y++) {
    for (int x = 0; x < W / 2; x++) {
      const uint8_t* c = kYuv[quarter_of(x * 2, y * 2)];
      uv[y * W + x * 2] = c[1];
      uv[y * W + x * 2 + 1] = c[2];
    }
  }
}

// ── Drawing, as the runner draws ────────────────────────────────────────

static EGLDisplay display;
// Through CUDA rather than DMA-BUFs: the textures CUDA copies into, as the
// runner makes them, and their registration, kept between pictures.
static int cuda;
static GLuint cuda_textures[2];
static RiftFfdecGl* gl_link;
static PFNGLEGLIMAGETARGETTEXTURE2DOESPROC image_target;
static GLuint program, target, framebuffer;

static GLuint compile(GLenum type, const char* source) {
  GLuint shader = glCreateShader(type);
  glShaderSource(shader, 1, &source, NULL);
  glCompileShader(shader);
  GLint ok = 0;
  glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
  if (!ok) {
    char log[512];
    glGetShaderInfoLog(shader, sizeof log, NULL, log);
    fprintf(stderr, "shader: %s\n", log);
  }
  return shader;
}

static int open_drawing(const char* node) {
  struct gbm_device* gbm = gbm_create_device(open(node, O_RDWR));
  if (!gbm) return 0;
  display = eglGetPlatformDisplay(EGL_PLATFORM_GBM_KHR, gbm, NULL);
  if (!eglInitialize(display, NULL, NULL)) return 0;
  eglBindAPI(EGL_OPENGL_ES_API);
  static const EGLint attributes[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
  EGLContext context =
      eglCreateContext(display, EGL_NO_CONFIG_KHR, EGL_NO_CONTEXT, attributes);
  if (!eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, context)) return 0;
  image_target = (PFNGLEGLIMAGETARGETTEXTURE2DOESPROC)eglGetProcAddress(
      "glEGLImageTargetTexture2DOES");

  GLuint vs = compile(GL_VERTEX_SHADER,
                      "#version 300 es\n"
                      "layout(location = 0) in vec2 p;\n"
                      "out vec2 uv;\n"
                      "void main() { uv = p * 0.5 + 0.5; gl_Position = vec4(p, 0.0, 1.0); }\n");
  GLuint fs = compile(GL_FRAGMENT_SHADER,
                      "#version 300 es\n"
                      "precision mediump float;\n"
                      "in vec2 uv;\n"
                      "out vec4 color;\n"
                      "uniform sampler2D ty, tuv;\n"
                      "void main() {\n"
                      "  float y = 1.16438 * (texture(ty, uv).r - 0.0627451);\n"
                      "  vec2 c = texture(tuv, uv).rg - 0.501961;\n"
                      "  color = vec4(clamp(vec3(y + 1.59603 * c.y,\n"
                      "                          y - 0.391762 * c.x - 0.812968 * c.y,\n"
                      "                          y + 2.01723 * c.x), 0.0, 1.0), 1.0);\n"
                      "}\n");
  program = glCreateProgram();
  glAttachShader(program, vs);
  glAttachShader(program, fs);
  glLinkProgram(program);
  glUseProgram(program);
  glUniform1i(glGetUniformLocation(program, "ty"), 0);
  glUniform1i(glGetUniformLocation(program, "tuv"), 1);
  static const float quad[] = {-1, -1, 1, -1, -1, 1, 1, 1};
  GLuint vao, vbo;
  glGenVertexArrays(1, &vao);
  glBindVertexArray(vao);
  glGenBuffers(1, &vbo);
  glBindBuffer(GL_ARRAY_BUFFER, vbo);
  glBufferData(GL_ARRAY_BUFFER, sizeof quad, quad, GL_STATIC_DRAW);
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, NULL);

  glGenTextures(2, cuda_textures);
  glBindTexture(GL_TEXTURE_2D, cuda_textures[0]);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_R8, W, H, 0, GL_RED, GL_UNSIGNED_BYTE, NULL);
  glBindTexture(GL_TEXTURE_2D, cuda_textures[1]);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RG8, (W + 1) / 2, (H + 1) / 2, 0, GL_RG,
               GL_UNSIGNED_BYTE, NULL);

  glGenTextures(1, &target);
  glBindTexture(GL_TEXTURE_2D, target);
  glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA8, W, H);
  glGenFramebuffers(1, &framebuffer);
  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
                         target, 0);
  return image_target != NULL;
}

// One plane of the picture as an EGL image; EGL_NO_IMAGE when it will not
// import.
static EGLImage import_plane(const RiftFfdecPicture* p, int i) {
  const int w = i ? (p->width + 1) / 2 : p->width;
  const int h = i ? (p->height + 1) / 2 : p->height;
  const EGLAttrib attributes[] = {
      EGL_WIDTH, w,
      EGL_HEIGHT, h,
      EGL_LINUX_DRM_FOURCC_EXT, p->formats[i],
      EGL_DMA_BUF_PLANE0_FD_EXT, p->fds[i],
      EGL_DMA_BUF_PLANE0_OFFSET_EXT, p->offsets[i],
      EGL_DMA_BUF_PLANE0_PITCH_EXT, p->pitches[i],
      EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT, (EGLAttrib)(p->modifiers[i] & 0xffffffff),
      EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT, (EGLAttrib)(p->modifiers[i] >> 32),
      EGL_NONE};
  return eglCreateImage(display, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, NULL,
                        attributes);
}

// Draws the picture and checks the middle of each quarter.
static void draw_and_check(const RiftFfdecPicture* p, int index) {
  CHECK(p->matrix == RIFT_FFDEC_BT601 && !p->full_range,
        "picture %d: matrix %d, full range %d; sent BT.601 limited", index,
        p->matrix, p->full_range);
  EGLImage images[2] = {EGL_NO_IMAGE, EGL_NO_IMAGE};
  GLuint textures[2];
  glGenTextures(2, textures);
  if (cuda) {
    int err = rift_ffdec_copy_to_gl(p, cuda_textures, &gl_link);
    CHECK(err == 0, "picture %d did not copy into GL (%d)", index, err);
    if (err != 0) return;
    for (int i = 0; i < 2; i++) {
      glActiveTexture(GL_TEXTURE0 + i);
      glBindTexture(GL_TEXTURE_2D, cuda_textures[i]);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    }
  }
  for (int i = 0; i < 2 && !cuda; i++) {
    images[i] = import_plane(p, i);
    CHECK(images[i] != EGL_NO_IMAGE, "picture %d plane %d did not import (0x%x)",
          index, i, eglGetError());
    if (images[i] == EGL_NO_IMAGE) return;
    glActiveTexture(GL_TEXTURE0 + i);
    glBindTexture(GL_TEXTURE_2D, textures[i]);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    image_target(GL_TEXTURE_2D, images[i]);
  }
  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
  glViewport(0, 0, W, H);
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
  // Row 0 of the planes is drawn at the bottom (stream_texture.cc), so a
  // picture's top half is read from the framebuffer's lower rows.
  for (int q = 0; q < 4; q++) {
    const int x = (q & 1) ? W * 3 / 4 : W / 4;
    const int y = (q & 2) ? H * 3 / 4 : H / 4;
    uint8_t px[4];
    glReadPixels(x, y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
    for (int c = 0; c < 3; c++) {
      CHECK(abs(px[c] - kRgb[q][c]) <= 24,
            "picture %d quarter %d: (%d, %d, %d), wanted (%d, %d, %d)", index, q,
            px[0], px[1], px[2], kRgb[q][0], kRgb[q][1], kRgb[q][2]);
      if (abs(px[c] - kRgb[q][c]) > 24) break;
    }
  }
  CHECK(glGetError() == GL_NO_ERROR, "GL error drawing picture %d", index);
  glDeleteTextures(2, textures);
  for (int i = 0; i < 2; i++) {
    if (images[i] != EGL_NO_IMAGE) eglDestroyImage(display, images[i]);
  }
}

// ── The round trip ──────────────────────────────────────────────────────

int main(int argc, char** argv) {
  cuda = argc > 1 && strcmp(argv[1], "cuda") == 0;
  const char* node = getenv("RIFT_RENDER_NODE");
  if (!node) node = "/dev/dri/renderD128";
  rift_ffenc_set_log(log_line, 16);
  char error[256] = {0};
  const char* way = cuda ? "NVIDIA" : "VAAPI";

  RiftFfencConfig enc_config = {
      // NVENC from memory: a render node would open its GL side.
      .encoder = cuda ? "h264_nvenc" : "h264_vaapi",
      .device = cuda ? NULL : node,
      .width = W,
      .height = H,
      .fps = 60,
      .bitrate_bps = 8000000,
      .peak_percent = 100,
      .gop = 600,
      .max_bitrate_bps = 8000000,
  };
  RiftFfenc* enc = rift_ffenc_open(&enc_config, error, sizeof error);
  if (!enc) {
    fprintf(stderr, "no %s encoder on %s: %s\n", way, node, error);
    return 2;
  }
  RiftFfdecConfig dec_config = {
      .codec = RIFT_FFDEC_H264,
      .device = node,
      .api = cuda ? RIFT_FFDEC_CUDA : RIFT_FFDEC_VAAPI,
  };
  RiftFfdec* dec = rift_ffdec_open(&dec_config, error, sizeof error);
  if (!dec) {
    fprintf(stderr, "no %s decoder on %s: %s\n", way, node, error);
    rift_ffenc_close(enc);
    return 2;
  }
  if (!open_drawing(node)) {
    fprintf(stderr, "FAIL: no EGL on %s\n", node);
    return 1;
  }
  printf("decoding on %s\n", rift_ffdec_driver(dec));

  RiftFfdecConfig bad = {.codec = 99, .device = node, .api = dec_config.api};
  CHECK(rift_ffdec_open(&bad, error, sizeof error) == NULL,
        "a codec that is not one opened");
  RiftFfdecConfig no_api = {.codec = RIFT_FFDEC_H264, .device = node, .api = 7};
  CHECK(rift_ffdec_open(&no_api, error, sizeof error) == NULL,
        "a way to the GPU that is not one opened");

  uint8_t* nv12 = malloc(W * H * 3 / 2);
  fill(nv12);
  int sent = 0, decoded = 0;
  RiftFfdecPicture kept = {0};
  for (int i = 0; i < PICTURES; i++) {
    CHECK(rift_ffenc_send(enc, nv12, i * 16667, i == 0) == 0, "encode %d", i);
    RiftFfencPacket packet;
    while (rift_ffenc_receive(enc, &packet) == 1) {
      sent++;
      CHECK(rift_ffdec_send(dec, packet.data, packet.len, packet.timestamp_us) == 0,
            "decode %d", sent);
      RiftFfdecPicture picture;
      int got;
      while ((got = rift_ffdec_receive(dec, &picture)) == 1) {
        CHECK(picture.width == W && picture.height == H, "size %dx%d",
              picture.width, picture.height);
        if (cuda) {
          CHECK(picture.planes == 2 && picture.memory == RIFT_FFDEC_IN_CUDA &&
                    picture.fds[0] == -1 && picture.fds[1] == -1,
                "not NV12 in CUDA's memory");
        } else {
          CHECK(picture.planes == 2 && picture.memory == RIFT_FFDEC_IN_DMABUF &&
                    picture.formats[0] == DRM_FORMAT_R8 &&
                    picture.formats[1] == DRM_FORMAT_GR88,
                "not NV12 as R8 and GR88");
        }
        // Every picture through CUDA, as the runner copies each; the first and
        // last checked.
        if (decoded == 0 || decoded == PICTURES - 1) {
          draw_and_check(&picture, decoded);
        } else if (cuda) {
          RiftFfdecGl* before = gl_link;
          CHECK(rift_ffdec_copy_to_gl(&picture, cuda_textures, &gl_link) == 0,
                "picture %d did not copy into GL", decoded);
          CHECK(gl_link == before, "picture %d registered the textures again",
                decoded);
        }
        // One kept past the decoder's close, as the runner may still hold one.
        if (decoded == 3) {
          kept = picture;
        } else {
          rift_ffdec_release(&picture);
        }
        decoded++;
      }
      CHECK(got == 0, "receive failed: %d", got);
      // A share's picture comes out as it goes in: nothing held back.
      CHECK(decoded == sent, "%d sent but %d out", sent, decoded);
    }
  }
  rift_ffenc_close(enc);
  rift_ffdec_close(dec);
  if (kept.held) draw_and_check(&kept, 3);
  rift_ffdec_release(&kept);
  rift_ffdec_release(&kept);
  if (cuda) {
    CHECK(gl_link != NULL, "no textures linked");
    RiftFfdecPicture none = {0};
    CHECK(rift_ffdec_copy_to_gl(&none, cuda_textures, &gl_link) < 0,
          "an empty picture copied");
    rift_ffdec_gl_close(gl_link);
    rift_ffdec_gl_close(NULL);
  }
  CHECK(decoded == PICTURES, "%d of %d pictures decoded", decoded, PICTURES);
  free(nv12);

  if (failures) {
    fprintf(stderr, "%d failures\n", failures);
    return 1;
  }
  printf("ok: %d pictures decoded on the GPU and drawn %s\n", decoded,
         cuda ? "after CUDA's copy into GL" : "from their DMA-BUFs");
  return 0;
}
