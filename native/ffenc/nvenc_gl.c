/* nvenc_gl.c — a DMA-BUF into NVENC through EGL, GL and CUDA.
 *
 * Adapted from gpu-screen-recorder (at 099a55b, Copyright dec05eba, GPL-3.0):
 * the CUDA device by PCI bus id (src/cuda.c), the EGL display on a render node
 * (src/egl.c), the import (gsr_pipewire_video_create_egl_image) and FFmpeg's
 * CUDA device on our own context (src/encoder/video/nvenc.c). Changed for Rift:
 * one shader program for every import, the textures mapped for each picture as
 * Sunshine (at a679b05, GPL-3.0) maps them, since drawing into a mapped resource
 * is undefined; GL's functions asked of EGL, so the library needs no new one to
 * load; and Rift's turn, crop and letterbox.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, version 3.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
#include "nvenc_gl.h"

#include <drm_fourcc.h>
#include <fcntl.h>
#include <gbm.h>
#include <inttypes.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <xf86drm.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
// Only the function types: every function comes from eglGetProcAddress.
#define GL_GLES_PROTOTYPES 0
#include <GLES3/gl3.h>
#include <GLES2/gl2ext.h>

#include <ffnvcodec/dynlink_loader.h>
#include <libavutil/error.h>
#include <libavutil/hwcontext.h>
#include <libavutil/hwcontext_cuda.h>
#include <libavutil/log.h>

#include "nvenc_gl_geometry.h"

// How often the worst wait on the GPU is logged at debug level.
#define WORST_EVERY_NS 5000000000LL

// The GL functions used, each asked of EGL in nvenc_gl_open.
#define GL_FUNCTIONS(X)                                     \
  X(PFNGLACTIVETEXTUREPROC, ActiveTexture)                  \
  X(PFNGLATTACHSHADERPROC, AttachShader)                    \
  X(PFNGLBINDFRAMEBUFFERPROC, BindFramebuffer)              \
  X(PFNGLBINDTEXTUREPROC, BindTexture)                      \
  X(PFNGLBINDVERTEXARRAYPROC, BindVertexArray)              \
  X(PFNGLCHECKFRAMEBUFFERSTATUSPROC, CheckFramebufferStatus) \
  X(PFNGLCLEARPROC, Clear)                                  \
  X(PFNGLCLEARCOLORPROC, ClearColor)                        \
  X(PFNGLCOMPILESHADERPROC, CompileShader)                  \
  X(PFNGLCREATEPROGRAMPROC, CreateProgram)                  \
  X(PFNGLCREATESHADERPROC, CreateShader)                    \
  X(PFNGLDELETEFRAMEBUFFERSPROC, DeleteFramebuffers)        \
  X(PFNGLDELETEPROGRAMPROC, DeleteProgram)                  \
  X(PFNGLDELETESHADERPROC, DeleteShader)                    \
  X(PFNGLDELETETEXTURESPROC, DeleteTextures)                \
  X(PFNGLDELETEVERTEXARRAYSPROC, DeleteVertexArrays)        \
  X(PFNGLDRAWARRAYSPROC, DrawArrays)                        \
  X(PFNGLEGLIMAGETARGETTEXTURE2DOESPROC, EGLImageTargetTexture2DOES) \
  X(PFNGLFLUSHPROC, Flush)                                  \
  X(PFNGLFRAMEBUFFERTEXTURE2DPROC, FramebufferTexture2D)    \
  X(PFNGLGENFRAMEBUFFERSPROC, GenFramebuffers)              \
  X(PFNGLGENTEXTURESPROC, GenTextures)                      \
  X(PFNGLGENVERTEXARRAYSPROC, GenVertexArrays)              \
  X(PFNGLGETERRORPROC, GetError)                            \
  X(PFNGLGETPROGRAMIVPROC, GetProgramiv)                    \
  X(PFNGLGETSHADERINFOLOGPROC, GetShaderInfoLog)            \
  X(PFNGLGETSHADERIVPROC, GetShaderiv)                      \
  X(PFNGLGETUNIFORMLOCATIONPROC, GetUniformLocation)        \
  X(PFNGLLINKPROGRAMPROC, LinkProgram)                      \
  X(PFNGLSHADERSOURCEPROC, ShaderSource)                    \
  X(PFNGLTEXPARAMETERIPROC, TexParameteri)                  \
  X(PFNGLTEXSTORAGE2DPROC, TexStorage2D)                    \
  X(PFNGLUNIFORM1IPROC, Uniform1i)                          \
  X(PFNGLUNIFORM2FVPROC, Uniform2fv)                        \
  X(PFNGLUSEPROGRAMPROC, UseProgram)                        \
  X(PFNGLVIEWPORTPROC, Viewport)

typedef struct Gl {
#define X(type, name) type name;
  GL_FUNCTIONS(X)
#undef X
} Gl;

struct NvencGl {
  int width;
  int height;

  EGLDisplay display;
  EGLContext context;
  Gl gl;
  GLuint programs[2];
  GLint corners[2];
  GLuint source;
  GLuint vertex_array;
  GLuint textures[2];
  GLuint framebuffers[2];

  CudaFunctions* cu;
  CUcontext cu_context;
  CUstream cu_stream;
  CUgraphicsResource resources[2];
  AVBufferRef* device;
  AVBufferRef* frames;

  // The wait on the GPU, for the logs.
  int64_t worst_ns;
  int64_t worst_since_ns;
  int64_t share_worst_ns;
};

static const char* const VERTEX_SHADER =
    "#version 300 es\n"
    "uniform highp vec2 corners[4];\n"
    "out highp vec2 uv;\n"
    "void main() {\n"
    "  uv = corners[gl_VertexID];\n"
    "  gl_Position = vec4((gl_VertexID & 1) == 1 ? 1.0 : -1.0,\n"
    "                     (gl_VertexID & 2) == 2 ? 1.0 : -1.0, 0.0, 1.0);\n"
    "}\n";

// BT.601 in limited range, as libyuv makes it and the encoder's stream says.
// External sampling takes every import and costs RGB nothing, so no modifier
// needs a second program.
#define FRAGMENT_HEAD                                         \
  "#version 300 es\n"                                         \
  "#extension GL_OES_EGL_image_external_essl3 : require\n"    \
  "precision highp float;\n"                                  \
  "in vec2 uv;\n"                                             \
  "out vec4 colour;\n"                                        \
  "uniform samplerExternalOES picture;\n"

static const char* const Y_SHADER =
    FRAGMENT_HEAD
    "void main() {\n"
    "  vec3 s = texture(picture, uv).rgb;\n"
    "  colour = vec4((16.0 + 65.481 * s.r + 128.553 * s.g + 24.966 * s.b)"
    " / 255.0, 0.0, 0.0, 1.0);\n"
    "}\n";

static const char* const UV_SHADER =
    FRAGMENT_HEAD
    "void main() {\n"
    "  vec3 s = texture(picture, uv).rgb;\n"
    "  colour = vec4((128.0 - 37.797 * s.r - 74.203 * s.g + 112.0 * s.b)"
    " / 255.0,\n"
    "                (128.0 + 112.0 * s.r - 93.786 * s.g - 18.214 * s.b)"
    " / 255.0, 0.0, 1.0);\n"
    "}\n";

static void fail(char* error, size_t error_len, const char* format, ...) {
  if (!error || error_len == 0) return;
  va_list args;
  va_start(args, format);
  vsnprintf(error, error_len, format, args);
  va_end(args);
}

static int64_t now_ns(void) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return (int64_t)now.tv_sec * 1000000000 + now.tv_nsec;
}

static bool has_extension(const char* extensions, const char* name) {
  size_t len = strlen(name);
  for (const char* at = extensions; at && (at = strstr(at, name)); at += len) {
    if ((at == extensions || at[-1] == ' ') && (at[len] == ' ' || !at[len])) {
      return true;
    }
  }
  return false;
}

// ── The display ─────────────────────────────────────────────────────────

// Displays are never terminated: a process's EGL display is shared with anything
// else in it that opens the same one. So the GBM device a fall back display
// stands on stays too, and is kept here for the next share.
static pthread_mutex_t gbm_lock = PTHREAD_MUTEX_INITIALIZER;
static struct {
  char node[64];
  EGLDisplay display;
} gbm_display = {"", EGL_NO_DISPLAY};

static EGLDisplay display_of_device(const char* render_node) {
  PFNEGLQUERYDEVICESEXTPROC query_devices =
      (PFNEGLQUERYDEVICESEXTPROC)eglGetProcAddress("eglQueryDevicesEXT");
  PFNEGLQUERYDEVICESTRINGEXTPROC query_string =
      (PFNEGLQUERYDEVICESTRINGEXTPROC)eglGetProcAddress(
          "eglQueryDeviceStringEXT");
  PFNEGLGETPLATFORMDISPLAYEXTPROC get_platform_display =
      (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress(
          "eglGetPlatformDisplayEXT");
  if (!query_devices || !query_string || !get_platform_display) {
    return EGL_NO_DISPLAY;
  }
  EGLDeviceEXT devices[16];
  EGLint count = 0;
  if (!query_devices(16, devices, &count)) return EGL_NO_DISPLAY;
  for (EGLint i = 0; i < count; i++) {
    const char* node =
        query_string(devices[i], EGL_DRM_RENDER_NODE_FILE_EXT);
    if (!node || strcmp(node, render_node) != 0) continue;
    return get_platform_display(EGL_PLATFORM_DEVICE_EXT, devices[i], NULL);
  }
  return EGL_NO_DISPLAY;
}

static EGLDisplay display_of_gbm(const char* render_node) {
  pthread_mutex_lock(&gbm_lock);
  EGLDisplay display = EGL_NO_DISPLAY;
  if (strcmp(gbm_display.node, render_node) == 0) {
    display = gbm_display.display;
  } else if (gbm_display.display == EGL_NO_DISPLAY &&
             strlen(render_node) < sizeof(gbm_display.node)) {
    PFNEGLGETPLATFORMDISPLAYEXTPROC get_platform_display =
        (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress(
            "eglGetPlatformDisplayEXT");
    int fd = open(render_node, O_RDWR | O_CLOEXEC);
    struct gbm_device* gbm = fd >= 0 ? gbm_create_device(fd) : NULL;
    if (gbm && get_platform_display) {
      display = get_platform_display(EGL_PLATFORM_GBM_KHR, gbm, NULL);
    }
    if (display != EGL_NO_DISPLAY) {
      strcpy(gbm_display.node, render_node);
      gbm_display.display = display;
    } else {
      if (gbm) gbm_device_destroy(gbm);
      if (fd >= 0) close(fd);
    }
  }
  pthread_mutex_unlock(&gbm_lock);
  return display;
}

// A display that takes a DMA-BUF and draws without a surface.
static bool display_fits(EGLDisplay display) {
  if (display == EGL_NO_DISPLAY || !eglInitialize(display, NULL, NULL)) {
    return false;
  }
  const char* extensions = eglQueryString(display, EGL_EXTENSIONS);
  return has_extension(extensions, "EGL_EXT_image_dma_buf_import") &&
         has_extension(extensions, "EGL_KHR_surfaceless_context") &&
         has_extension(extensions, "EGL_KHR_no_config_context");
}

static EGLDisplay open_display(const char* render_node) {
  EGLDisplay display = display_of_device(render_node);
  if (display_fits(display)) return display;
  display = display_of_gbm(render_node);
  return display_fits(display) ? display : EGL_NO_DISPLAY;
}

// ── GL's side ───────────────────────────────────────────────────────────

static bool load_gl(Gl* gl) {
#define X(type, name)                                     \
  gl->name = (type)eglGetProcAddress("gl" #name);         \
  if (!gl->name) return false;
  GL_FUNCTIONS(X)
#undef X
  return true;
}

static GLuint compile(const Gl* gl, GLenum type, const char* source,
                      char* error, size_t error_len) {
  GLuint shader = gl->CreateShader(type);
  GLint compiled = 0;
  gl->ShaderSource(shader, 1, &source, NULL);
  gl->CompileShader(shader);
  gl->GetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
  if (!compiled) {
    char log[256] = "";
    gl->GetShaderInfoLog(shader, sizeof(log), NULL, log);
    fail(error, error_len, "a shader did not compile: %s", log);
    gl->DeleteShader(shader);
    return 0;
  }
  return shader;
}

static GLuint link_program(const Gl* gl, const char* fragment_source,
                           char* error, size_t error_len) {
  GLuint vertex = compile(gl, GL_VERTEX_SHADER, VERTEX_SHADER, error, error_len);
  if (!vertex) return 0;
  GLuint fragment =
      compile(gl, GL_FRAGMENT_SHADER, fragment_source, error, error_len);
  if (!fragment) {
    gl->DeleteShader(vertex);
    return 0;
  }
  GLuint program = gl->CreateProgram();
  GLint linked = 0;
  gl->AttachShader(program, vertex);
  gl->AttachShader(program, fragment);
  gl->LinkProgram(program);
  gl->DeleteShader(vertex);
  gl->DeleteShader(fragment);
  gl->GetProgramiv(program, GL_LINK_STATUS, &linked);
  if (!linked) {
    fail(error, error_len, "a shader program did not link");
    gl->DeleteProgram(program);
    return 0;
  }
  return program;
}

static bool open_gl(NvencGl* self, char* error, size_t error_len) {
  static const EGLint attributes[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
  if (!eglBindAPI(EGL_OPENGL_ES_API)) {
    fail(error, error_len, "EGL has no OpenGL ES");
    return false;
  }
  self->context = eglCreateContext(self->display, EGL_NO_CONFIG_KHR,
                                   EGL_NO_CONTEXT, attributes);
  if (self->context == EGL_NO_CONTEXT ||
      !eglMakeCurrent(self->display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                      self->context)) {
    fail(error, error_len, "no GLES 3 context (EGL error 0x%x)", eglGetError());
    return false;
  }
  const Gl* gl = &self->gl;
  if (!load_gl(&self->gl)) {
    fail(error, error_len, "EGL did not give every GL function");
    return false;
  }

  static const char* const* const fragments[2] = {&Y_SHADER, &UV_SHADER};
  for (int plane = 0; plane < 2; plane++) {
    self->programs[plane] =
        link_program(gl, *fragments[plane], error, error_len);
    if (!self->programs[plane]) return false;
    self->corners[plane] =
        gl->GetUniformLocation(self->programs[plane], "corners");
    gl->UseProgram(self->programs[plane]);
    gl->Uniform1i(gl->GetUniformLocation(self->programs[plane], "picture"), 0);
  }

  gl->GenVertexArrays(1, &self->vertex_array);
  gl->BindVertexArray(self->vertex_array);
  gl->GenTextures(1, &self->source);
  gl->ActiveTexture(GL_TEXTURE0);
  gl->BindTexture(GL_TEXTURE_EXTERNAL_OES, self->source);
  gl->TexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  gl->TexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

  gl->GenTextures(2, self->textures);
  gl->GenFramebuffers(2, self->framebuffers);
  for (int plane = 0; plane < 2; plane++) {
    RiftRect whole =
        nvenc_gl_plane_rect(NULL, self->width, self->height, plane);
    gl->BindTexture(GL_TEXTURE_2D, self->textures[plane]);
    gl->TexStorage2D(GL_TEXTURE_2D, 1, plane == 0 ? GL_R8 : GL_RG8, whole.width,
                     whole.height);
    gl->BindFramebuffer(GL_FRAMEBUFFER, self->framebuffers[plane]);
    gl->FramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                             GL_TEXTURE_2D, self->textures[plane], 0);
    if (gl->CheckFramebufferStatus(GL_FRAMEBUFFER) !=
        GL_FRAMEBUFFER_COMPLETE) {
      fail(error, error_len, "a plane's framebuffer is not complete");
      return false;
    }
  }
  return true;
}

// ── CUDA's side ─────────────────────────────────────────────────────────

// The CUDA device that is this render node's card, or the first if it cannot be
// told (src/cuda.c).
static CUresult device_of_node(const CudaFunctions* cu, const char* render_node,
                               CUdevice* device) {
  int fd = open(render_node, O_RDONLY | O_CLOEXEC);
  if (fd >= 0) {
    drmDevicePtr drm = NULL;
    char bus_id[32] = "";
    if (drmGetDevice2(fd, 0, &drm) == 0) {
      if (drm->bustype == DRM_BUS_PCI) {
        snprintf(bus_id, sizeof(bus_id), "%04x:%02x:%02x.%u",
                 drm->businfo.pci->domain, drm->businfo.pci->bus,
                 drm->businfo.pci->dev, drm->businfo.pci->func);
      }
      drmFreeDevice(&drm);
    }
    close(fd);
    if (bus_id[0] && cu->cuDeviceGetByPCIBusId &&
        cu->cuDeviceGetByPCIBusId(device, bus_id) == CUDA_SUCCESS) {
      return CUDA_SUCCESS;
    }
  }
  return cu->cuDeviceGet(device, 0);
}

static bool open_cuda(NvencGl* self, const char* render_node, char* error,
                      size_t error_len) {
  if (cuda_load_functions(&self->cu, NULL) < 0) {
    fail(error, error_len, "no CUDA library");
    return false;
  }
  CudaFunctions* cu = self->cu;
  CUdevice device;
  CUresult result = cu->cuInit(0);
  if (result == CUDA_SUCCESS) {
    result = device_of_node(cu, render_node, &device);
  }
  if (result == CUDA_SUCCESS) {
    result = cu->cuCtxCreate(&self->cu_context, 0, device);
  }
  if (result != CUDA_SUCCESS) {
    fail(error, error_len, "no CUDA context (CUDA error %d)", (int)result);
    return false;
  }

  self->device = av_hwdevice_ctx_alloc(AV_HWDEVICE_TYPE_CUDA);
  if (!self->device) goto no_frames;
  AVHWDeviceContext* device_context = (AVHWDeviceContext*)self->device->data;
  AVCUDADeviceContext* hwctx = device_context->hwctx;
  hwctx->cuda_ctx = self->cu_context;
  if (av_hwdevice_ctx_init(self->device) < 0) goto no_frames;
  self->cu_stream = hwctx->stream;

  self->frames = av_hwframe_ctx_alloc(self->device);
  if (!self->frames) goto no_frames;
  AVHWFramesContext* frames = (AVHWFramesContext*)self->frames->data;
  frames->format = AV_PIX_FMT_CUDA;
  frames->sw_format = AV_PIX_FMT_NV12;
  frames->width = self->width;
  frames->height = self->height;
  if (av_hwframe_ctx_init(self->frames) < 0) goto no_frames;

  CUcontext popped;
  cu->cuCtxPushCurrent(self->cu_context);
  for (int plane = 0; plane < 2; plane++) {
    result = cu->cuGraphicsGLRegisterImage(
        &self->resources[plane], self->textures[plane], GL_TEXTURE_2D,
        CU_GRAPHICS_REGISTER_FLAGS_READ_ONLY);
    if (result != CUDA_SUCCESS) break;
  }
  cu->cuCtxPopCurrent(&popped);
  if (result != CUDA_SUCCESS) {
    fail(error, error_len, "CUDA would not take GL's textures (CUDA error %d)",
         (int)result);
    return false;
  }
  return true;

no_frames:
  fail(error, error_len, "no CUDA frames");
  return false;
}

// ── The path ────────────────────────────────────────────────────────────

NvencGl* nvenc_gl_open(const char* render_node, int width, int height,
                       char* error, size_t error_len) {
  NvencGl* self = calloc(1, sizeof(*self));
  if (!self) {
    fail(error, error_len, "out of memory");
    return NULL;
  }
  self->width = width;
  self->height = height;
  self->context = EGL_NO_CONTEXT;
  self->worst_since_ns = now_ns();

  self->display = open_display(render_node);
  if (self->display == EGL_NO_DISPLAY) {
    fail(error, error_len, "no EGL display on %s that imports DMA-BUFs",
         render_node);
    nvenc_gl_free(&self);
    return NULL;
  }
  if (!open_gl(self, error, error_len) ||
      !open_cuda(self, render_node, error, error_len)) {
    nvenc_gl_free(&self);
    return NULL;
  }
  return self;
}

AVBufferRef* nvenc_gl_frames(NvencGl* self) { return self->frames; }

static bool make_current(NvencGl* self) {
  if (eglGetCurrentContext() == self->context) return true;
  eglBindAPI(EGL_OPENGL_ES_API);
  return eglMakeCurrent(self->display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                        self->context);
}

// The buffer as EGL takes it, with its modifier when it has one
// (setup_dma_buf_attrs).
static EGLImage import_image(NvencGl* self, const RiftDmabuf* buf) {
  static const EGLAttrib plane_keys[4][5] = {
      {EGL_DMA_BUF_PLANE0_FD_EXT, EGL_DMA_BUF_PLANE0_OFFSET_EXT,
       EGL_DMA_BUF_PLANE0_PITCH_EXT, EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT,
       EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT},
      {EGL_DMA_BUF_PLANE1_FD_EXT, EGL_DMA_BUF_PLANE1_OFFSET_EXT,
       EGL_DMA_BUF_PLANE1_PITCH_EXT, EGL_DMA_BUF_PLANE1_MODIFIER_LO_EXT,
       EGL_DMA_BUF_PLANE1_MODIFIER_HI_EXT},
      {EGL_DMA_BUF_PLANE2_FD_EXT, EGL_DMA_BUF_PLANE2_OFFSET_EXT,
       EGL_DMA_BUF_PLANE2_PITCH_EXT, EGL_DMA_BUF_PLANE2_MODIFIER_LO_EXT,
       EGL_DMA_BUF_PLANE2_MODIFIER_HI_EXT},
      {EGL_DMA_BUF_PLANE3_FD_EXT, EGL_DMA_BUF_PLANE3_OFFSET_EXT,
       EGL_DMA_BUF_PLANE3_PITCH_EXT, EGL_DMA_BUF_PLANE3_MODIFIER_LO_EXT,
       EGL_DMA_BUF_PLANE3_MODIFIER_HI_EXT},
  };
  EGLAttrib attributes[6 + 4 * 10 + 1];
  int at = 0;
  attributes[at++] = EGL_WIDTH;
  attributes[at++] = buf->width;
  attributes[at++] = EGL_HEIGHT;
  attributes[at++] = buf->height;
  attributes[at++] = EGL_LINUX_DRM_FOURCC_EXT;
  attributes[at++] = (EGLAttrib)buf->drm_format;
  for (int plane = 0; plane < buf->planes && plane < 4; plane++) {
    attributes[at++] = plane_keys[plane][0];
    attributes[at++] = buf->fds[plane];
    attributes[at++] = plane_keys[plane][1];
    attributes[at++] = (EGLAttrib)buf->offsets[plane];
    attributes[at++] = plane_keys[plane][2];
    attributes[at++] = (EGLAttrib)buf->strides[plane];
    if (buf->modifier != DRM_FORMAT_MOD_INVALID) {
      attributes[at++] = plane_keys[plane][3];
      attributes[at++] = (EGLAttrib)(buf->modifier & 0xffffffff);
      attributes[at++] = plane_keys[plane][4];
      attributes[at++] = (EGLAttrib)(buf->modifier >> 32);
    }
  }
  attributes[at] = EGL_NONE;
  return eglCreateImage(self->display, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT,
                        NULL, attributes);
}

static void draw_plane(NvencGl* self, int plane, const RiftRect* place,
                       const float uv[4][2]) {
  const Gl* gl = &self->gl;
  RiftRect whole = nvenc_gl_plane_rect(NULL, self->width, self->height, plane);
  RiftRect rect = nvenc_gl_plane_rect(place, self->width, self->height, plane);
  gl->BindFramebuffer(GL_FRAMEBUFFER, self->framebuffers[plane]);
  if (rect.x != 0 || rect.y != 0 || rect.width != whole.width ||
      rect.height != whole.height) {
    // Black outside the picture.
    float neutral = plane == 0 ? 16.0f / 255.0f : 128.0f / 255.0f;
    gl->ClearColor(neutral, neutral, 0.0f, 1.0f);
    gl->Clear(GL_COLOR_BUFFER_BIT);
  }
  // Row 0 of the buffer goes to GL's y = 0, and CUDA copies that to the frame's
  // top row, so nothing here is flipped.
  gl->Viewport(rect.x, rect.y, rect.width, rect.height);
  gl->UseProgram(self->programs[plane]);
  gl->Uniform2fv(self->corners[plane], 4, &uv[0][0]);
  gl->DrawArrays(GL_TRIANGLE_STRIP, 0, 4);
}

// Into the frame the encoder takes. Mapping is the point where everything GL was
// told to draw is done for CUDA.
static int copy_to_frame(NvencGl* self, AVFrame* out) {
  CudaFunctions* cu = self->cu;
  CUcontext popped;
  CUarray arrays[2] = {0, 0};
  int64_t started = now_ns();
  cu->cuCtxPushCurrent(self->cu_context);
  CUresult result =
      cu->cuGraphicsMapResources(2, self->resources, self->cu_stream);
  if (result == CUDA_SUCCESS) {
    CUresult copied = CUDA_SUCCESS;
    for (int plane = 0; plane < 2 && copied == CUDA_SUCCESS; plane++) {
      copied = cu->cuGraphicsSubResourceGetMappedArray(
          &arrays[plane], self->resources[plane], 0, 0);
      if (copied != CUDA_SUCCESS) break;
      RiftRect whole =
          nvenc_gl_plane_rect(NULL, self->width, self->height, plane);
      CUDA_MEMCPY2D copy = {0};
      copy.srcMemoryType = CU_MEMORYTYPE_ARRAY;
      copy.srcArray = arrays[plane];
      copy.dstMemoryType = CU_MEMORYTYPE_DEVICE;
      copy.dstDevice = (CUdeviceptr)out->data[plane];
      copy.dstPitch = (size_t)out->linesize[plane];
      copy.WidthInBytes = (size_t)whole.width * (plane == 0 ? 1 : 2);
      copy.Height = (size_t)whole.height;
      copied = cu->cuMemcpy2DAsync(&copy, self->cu_stream);
    }
    if (copied == CUDA_SUCCESS) {
      copied = cu->cuStreamSynchronize(self->cu_stream);
    }
    cu->cuGraphicsUnmapResources(2, self->resources, self->cu_stream);
    result = copied;
  }
  cu->cuCtxPopCurrent(&popped);
  if (result != CUDA_SUCCESS) {
    av_log(NULL, AV_LOG_WARNING, "nvenc gl: CUDA error %d\n", (int)result);
    return AVERROR_EXTERNAL;
  }

  int64_t done = now_ns();
  int64_t waited = done - started;
  if (waited > self->worst_ns) self->worst_ns = waited;
  if (waited > self->share_worst_ns) self->share_worst_ns = waited;
  if (done - self->worst_since_ns >= WORST_EVERY_NS) {
    av_log(NULL, AV_LOG_DEBUG, "nvenc gl: worst wait on the GPU %" PRId64 " us\n",
           self->worst_ns / 1000);
    self->worst_ns = 0;
    self->worst_since_ns = done;
  }
  return 0;
}

int nvenc_gl_run(NvencGl* self, const RiftDmabuf* buf, const RiftRect* place,
                 AVFrame* out) {
  if (!make_current(self)) return AVERROR_EXTERNAL;
  const Gl* gl = &self->gl;
  while (gl->GetError() != GL_NO_ERROR) {
  }

  EGLImage image = import_image(self, buf);
  if (image == EGL_NO_IMAGE) return RIFT_FFENC_IMPORT_FAILED;
  gl->BindTexture(GL_TEXTURE_EXTERNAL_OES, self->source);
  gl->EGLImageTargetTexture2DOES(GL_TEXTURE_EXTERNAL_OES, image);
  if (gl->GetError() != GL_NO_ERROR) {
    eglDestroyImage(self->display, image);
    return RIFT_FFENC_IMPORT_FAILED;
  }

  float uv[4][2];
  nvenc_gl_source_uv(buf, uv);
  draw_plane(self, 0, place, uv);
  draw_plane(self, 1, place, uv);
  gl->Flush();
  eglDestroyImage(self->display, image);

  int err = av_hwframe_get_buffer(self->frames, out, 0);
  if (err < 0) return err;
  err = copy_to_frame(self, out);
  if (err < 0) av_frame_unref(out);
  return err;
}

void nvenc_gl_free(NvencGl** handle) {
  NvencGl* self = *handle;
  if (!self) return;
  *handle = NULL;

  if (self->share_worst_ns > 0) {
    av_log(NULL, AV_LOG_INFO, "nvenc gl: worst wait on the GPU %" PRId64 " us\n",
           self->share_worst_ns / 1000);
  }
  bool current = self->context != EGL_NO_CONTEXT && make_current(self);
  if (self->cu && self->cu_context) {
    CUcontext popped;
    self->cu->cuCtxPushCurrent(self->cu_context);
    for (int plane = 0; plane < 2; plane++) {
      if (self->resources[plane]) {
        self->cu->cuGraphicsUnregisterResource(self->resources[plane]);
      }
    }
    self->cu->cuCtxPopCurrent(&popped);
  }
  av_buffer_unref(&self->frames);
  av_buffer_unref(&self->device);
  if (self->cu && self->cu_context) self->cu->cuCtxDestroy(self->cu_context);
  if (self->cu) cuda_free_functions(&self->cu);

  if (current && self->gl.DeleteTextures) {
    const Gl* gl = &self->gl;
    gl->DeleteFramebuffers(2, self->framebuffers);
    gl->DeleteTextures(2, self->textures);
    gl->DeleteTextures(1, &self->source);
    gl->DeleteVertexArrays(1, &self->vertex_array);
    if (self->programs[0]) gl->DeleteProgram(self->programs[0]);
    if (self->programs[1]) gl->DeleteProgram(self->programs[1]);
  }
  // The display stays: see gbm_display.
  if (current) {
    eglMakeCurrent(self->display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                   EGL_NO_CONTEXT);
  }
  if (self->context != EGL_NO_CONTEXT) {
    eglDestroyContext(self->display, self->context);
  }
  free(self);
}
