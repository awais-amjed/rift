#include "stream_texture.h"

#include <epoxy/egl.h>
#include <epoxy/gl.h>
#include <gdk/gdkwayland.h>

#include <cstdint>
#include <cstring>
#include <map>
#include <mutex>
#include <string>
#include <vector>

namespace {

// rust/src/watching/frames.rs, `WatchPlanes`: the same fields in the same
// order, `#[repr(C)]` there.
struct WatchPlanes {
  uint32_t width, height;
  const uint8_t* y;
  const uint8_t* u;
  const uint8_t* v;
  uint32_t stride_y, stride_u, stride_v;
  // 0: the three planes above, in memory. kOnGpu: NV12 decoded on the GPU,
  // as two DMA-BUF layers, Y as DRM's R8 and UV as GR88 at half size.
  uint32_t kind;
  uint32_t formats[2];
  int32_t fds[2];
  uint32_t offsets[2], pitches[2];
  uint64_t modifiers[2];
};
constexpr uint32_t kOnGpu = 1;
using LockFn = int32_t (*)(uint64_t, WatchPlanes*);
using UnlockFn = void (*)(uint64_t);

}  // namespace

struct _RiftStreamTexture {
  FlTextureGL parent_instance;
  LockFn lock;
  UnlockFn unlock;
  int64_t id;
  GLuint planes[3];
  // The two layers of a picture decoded on the GPU, each its EGL image's.
  GLuint layers[2];
  bool import_failed;
  GLuint out, fbo;
  uint32_t width, height;
};

G_DECLARE_FINAL_TYPE(RiftStreamTexture, rift_stream_texture, RIFT,
                     STREAM_TEXTURE, FlTextureGL)
G_DEFINE_TYPE(RiftStreamTexture, rift_stream_texture, fl_texture_gl_get_type())

namespace {

FlTextureRegistrar* registrar = nullptr;

// The textures Rust may mark, by id. A texture leaves before it is let go, so
// a mark that finds nothing is a share already stopped.
std::mutex live_mutex;
std::map<int64_t, FlTexture*> live;

// GL names of textures let go. Only the raster thread has Flutter's context
// current, so they are deleted there, at the next draw of any stream.
std::mutex dead_mutex;
std::vector<GLuint> dead_textures, dead_framebuffers;

// One program for pictures in memory, one for pictures on the GPU, and one
// quad for every stream: built on the first draw.
GLuint program = 0, gpu_program = 0, vao = 0, vbo = 0;

void Bury() {
  std::lock_guard<std::mutex> hold(dead_mutex);
  if (!dead_textures.empty()) {
    glDeleteTextures(static_cast<GLsizei>(dead_textures.size()),
                     dead_textures.data());
    dead_textures.clear();
  }
  if (!dead_framebuffers.empty()) {
    glDeleteFramebuffers(static_cast<GLsizei>(dead_framebuffers.size()),
                         dead_framebuffers.data());
    dead_framebuffers.clear();
  }
}

GLuint Compile(GLenum type, const char* source) {
  GLuint shader = glCreateShader(type);
  glShaderSource(shader, 1, &source, nullptr);
  glCompileShader(shader);
  GLint ok = 0;
  glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
  if (!ok) {
    char log[512];
    glGetShaderInfoLog(shader, sizeof log, nullptr, log);
    g_warning("stream texture: shader: %s", log);
  }
  return shader;
}

// The picture as BT.601 in limited range, which is how flutter_webrtc's
// renderer (libyuv's I420ToARGB) has always shown a share, so a stream looks
// the same on either path.
//
// Drawn with row 0 of the planes at the bottom of the framebuffer: Flutter
// reads a GL texture's row 0 as the top, so the two turns cancel (probed Nov 2
// under Impeller on Wayland and X11, on Intel and NVIDIA).
constexpr char kVertexEs[] =
    "#version 300 es\n"
    "layout(location = 0) in vec2 p;\n"
    "out vec2 uv;\n"
    "void main() { uv = p * 0.5 + 0.5; gl_Position = vec4(p, 0.0, 1.0); }\n";
constexpr char kVertexGl[] =
    "#version 330 core\n"
    "layout(location = 0) in vec2 p;\n"
    "out vec2 uv;\n"
    "void main() { uv = p * 0.5 + 0.5; gl_Position = vec4(p, 0.0, 1.0); }\n";
constexpr char kFragmentBody[] =
    "in vec2 uv;\n"
    "out vec4 color;\n"
    "uniform sampler2D ty, tu, tv;\n"
    "void main() {\n"
    "  float y = 1.16438 * (texture(ty, uv).r - 0.0627451);\n"
    "  float u = texture(tu, uv).r - 0.501961;\n"
    "  float v = texture(tv, uv).r - 0.501961;\n"
    "  color = vec4(clamp(vec3(y + 1.59603 * v,\n"
    "                          y - 0.391762 * u - 0.812968 * v,\n"
    "                          y + 2.01723 * u), 0.0, 1.0), 1.0);\n"
    "}\n";

// The same, from NV12's two planes: U and V side by side in one texture.
constexpr char kGpuFragmentBody[] =
    "in vec2 uv;\n"
    "out vec4 color;\n"
    "uniform sampler2D ty, tuv;\n"
    "void main() {\n"
    "  float y = 1.16438 * (texture(ty, uv).r - 0.0627451);\n"
    "  vec2 c = texture(tuv, uv).rg - 0.501961;\n"
    "  color = vec4(clamp(vec3(y + 1.59603 * c.y,\n"
    "                          y - 0.391762 * c.x - 0.812968 * c.y,\n"
    "                          y + 2.01723 * c.x), 0.0, 1.0), 1.0);\n"
    "}\n";

GLuint Link(const char* fragment_body, const char* const* samplers,
            int count) {
  const bool es = !epoxy_is_desktop_gl();
  std::string fragment = es ? "#version 300 es\nprecision mediump float;\n"
                            : "#version 330 core\n";
  fragment += fragment_body;
  GLuint vs = Compile(GL_VERTEX_SHADER, es ? kVertexEs : kVertexGl);
  GLuint fs = Compile(GL_FRAGMENT_SHADER, fragment.c_str());
  GLuint linked = glCreateProgram();
  glAttachShader(linked, vs);
  glAttachShader(linked, fs);
  glLinkProgram(linked);
  glDeleteShader(vs);
  glDeleteShader(fs);
  glUseProgram(linked);
  for (int i = 0; i < count; i++) {
    glUniform1i(glGetUniformLocation(linked, samplers[i]), i);
  }
  return linked;
}

void BuildProgram() {
  static const char* const kPlanes[] = {"ty", "tu", "tv"};
  static const char* const kLayers[] = {"ty", "tuv"};
  program = Link(kFragmentBody, kPlanes, 3);
  gpu_program = Link(kGpuFragmentBody, kLayers, 2);

  const float quad[] = {-1, -1, 1, -1, -1, 1, 1, 1};
  glGenVertexArrays(1, &vao);
  glBindVertexArray(vao);
  glGenBuffers(1, &vbo);
  glBindBuffer(GL_ARRAY_BUFFER, vbo);
  glBufferData(GL_ARRAY_BUFFER, sizeof quad, quad, GL_STATIC_DRAW);
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, nullptr);
}

void Allocate(GLuint texture, GLint format, GLenum layout, uint32_t width,
              uint32_t height) {
  glBindTexture(GL_TEXTURE_2D, texture);
  glTexImage2D(GL_TEXTURE_2D, 0, format, static_cast<GLsizei>(width),
               static_cast<GLsizei>(height), 0, layout, GL_UNSIGNED_BYTE,
               nullptr);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
}

// The GL state a draw changes, taken before and put back after: Flutter's
// renderer shares the context and expects to find it as it left it.
struct SavedState {
  GLint draw_fbo, read_fbo, program, vao, array_buffer, unpack_buffer, active;
  GLint textures[3], samplers[3], viewport[4], alignment, row_length,
      skip_rows, skip_pixels;
  GLboolean blend, scissor, depth, stencil, cull, mask[4];

  SavedState() {
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &draw_fbo);
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &read_fbo);
    glGetIntegerv(GL_CURRENT_PROGRAM, &program);
    glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &vao);
    glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &array_buffer);
    glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &unpack_buffer);
    glGetIntegerv(GL_ACTIVE_TEXTURE, &active);
    glGetIntegerv(GL_VIEWPORT, viewport);
    glGetIntegerv(GL_UNPACK_ALIGNMENT, &alignment);
    glGetIntegerv(GL_UNPACK_ROW_LENGTH, &row_length);
    glGetIntegerv(GL_UNPACK_SKIP_ROWS, &skip_rows);
    glGetIntegerv(GL_UNPACK_SKIP_PIXELS, &skip_pixels);
    glGetBooleanv(GL_COLOR_WRITEMASK, mask);
    for (int i = 0; i < 3; i++) {
      glActiveTexture(GL_TEXTURE0 + i);
      glGetIntegerv(GL_TEXTURE_BINDING_2D, &textures[i]);
      glGetIntegerv(GL_SAMPLER_BINDING, &samplers[i]);
    }
    blend = glIsEnabled(GL_BLEND);
    scissor = glIsEnabled(GL_SCISSOR_TEST);
    depth = glIsEnabled(GL_DEPTH_TEST);
    stencil = glIsEnabled(GL_STENCIL_TEST);
    cull = glIsEnabled(GL_CULL_FACE);
  }

  ~SavedState() {
    glBindVertexArray(vao);
    glBindBuffer(GL_ARRAY_BUFFER, array_buffer);
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, unpack_buffer);
    glUseProgram(program);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, draw_fbo);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, read_fbo);
    glViewport(viewport[0], viewport[1], viewport[2], viewport[3]);
    glPixelStorei(GL_UNPACK_ALIGNMENT, alignment);
    glPixelStorei(GL_UNPACK_ROW_LENGTH, row_length);
    glPixelStorei(GL_UNPACK_SKIP_ROWS, skip_rows);
    glPixelStorei(GL_UNPACK_SKIP_PIXELS, skip_pixels);
    glColorMask(mask[0], mask[1], mask[2], mask[3]);
    for (int i = 2; i >= 0; i--) {
      glActiveTexture(GL_TEXTURE0 + i);
      glBindTexture(GL_TEXTURE_2D, textures[i]);
      glBindSampler(i, samplers[i]);
    }
    glActiveTexture(active);
    auto restore = [](GLenum cap, GLboolean on) {
      on ? glEnable(cap) : glDisable(cap);
    };
    restore(GL_BLEND, blend);
    restore(GL_SCISSOR_TEST, scissor);
    restore(GL_DEPTH_TEST, depth);
    restore(GL_STENCIL_TEST, stencil);
    restore(GL_CULL_FACE, cull);
  }
};

// The texture's picture and its framebuffer, sized to |p|. The memory planes
// are sized with it, so a stream moving between the two paths finds them
// ready. The picture may already be there, black, from before the first
// one (DrawBlack), with nothing else made yet.
void Size(RiftStreamTexture* self, const WatchPlanes& p) {
  if (self->fbo == 0) {
    glGenTextures(3, self->planes);
    glGenTextures(2, self->layers);
    glGenFramebuffers(1, &self->fbo);
  }
  if (self->out == 0) glGenTextures(1, &self->out);
  if (p.width == self->width && p.height == self->height) return;
  const uint32_t cw = (p.width + 1) / 2, ch = (p.height + 1) / 2;
  Allocate(self->planes[0], GL_R8, GL_RED, p.width, p.height);
  Allocate(self->planes[1], GL_R8, GL_RED, cw, ch);
  Allocate(self->planes[2], GL_R8, GL_RED, cw, ch);
  Allocate(self->out, GL_RGBA8, GL_RGBA, p.width, p.height);
  glBindFramebuffer(GL_FRAMEBUFFER, self->fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
                         self->out, 0);
  self->width = p.width;
  self->height = p.height;
}

// Draws the quad into the texture's picture with whichever program is bound.
void Fill(RiftStreamTexture* self, const WatchPlanes& p) {
  glBindFramebuffer(GL_FRAMEBUFFER, self->fbo);
  glViewport(0, 0, static_cast<GLsizei>(p.width),
             static_cast<GLsizei>(p.height));
  glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
  glDisable(GL_BLEND);
  glDisable(GL_SCISSOR_TEST);
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_STENCIL_TEST);
  glDisable(GL_CULL_FACE);
  glBindVertexArray(vao);
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
}

// One layer of a picture decoded on the GPU, as an EGL image, or
// EGL_NO_IMAGE_KHR when it will not import.
EGLImageKHR Import(EGLDisplay display, const WatchPlanes& p, int i) {
  const EGLint w = static_cast<EGLint>(i ? (p.width + 1) / 2 : p.width);
  const EGLint h = static_cast<EGLint>(i ? (p.height + 1) / 2 : p.height);
  const EGLint attributes[] = {
      EGL_WIDTH, w,
      EGL_HEIGHT, h,
      EGL_LINUX_DRM_FOURCC_EXT, static_cast<EGLint>(p.formats[i]),
      EGL_DMA_BUF_PLANE0_FD_EXT, p.fds[i],
      EGL_DMA_BUF_PLANE0_OFFSET_EXT, static_cast<EGLint>(p.offsets[i]),
      EGL_DMA_BUF_PLANE0_PITCH_EXT, static_cast<EGLint>(p.pitches[i]),
      EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT,
      static_cast<EGLint>(p.modifiers[i] & 0xffffffff),
      EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT, static_cast<EGLint>(p.modifiers[i] >> 32),
      EGL_NONE};
  return eglCreateImageKHR(display, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT,
                           nullptr, attributes);
}

// Draws a picture decoded on the GPU: its two layers imported where they lie
// and turned into colour by the shader, nothing copied through the CPU.
void DrawFromGpu(RiftStreamTexture* self, const WatchPlanes& p) {
  EGLDisplay display = eglGetCurrentDisplay();
  if (display == EGL_NO_DISPLAY) return;
  SavedState saved;
  if (program == 0) BuildProgram();
  Size(self, p);
  EGLImageKHR images[2] = {EGL_NO_IMAGE_KHR, EGL_NO_IMAGE_KHR};
  for (int i = 0; i < 2; i++) {
    images[i] = Import(display, p, i);
    if (images[i] == EGL_NO_IMAGE_KHR) {
      if (!self->import_failed) {
        g_warning("stream texture: a GPU picture did not import (0x%x)",
                  eglGetError());
        self->import_failed = true;
      }
      if (i == 1) eglDestroyImageKHR(display, images[0]);
      return;
    }
    glActiveTexture(GL_TEXTURE0 + i);
    glBindTexture(GL_TEXTURE_2D, self->layers[i]);
    glBindSampler(i, 0);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glEGLImageTargetTexture2DOES(GL_TEXTURE_2D, images[i]);
  }
  glUseProgram(gpu_program);
  Fill(self, p);
  // Sent to the GPU before Rust gets the picture back and the decoder may
  // write its surface again: the kernel then keeps the two in order.
  glFlush();
  for (EGLImageKHR image : images) eglDestroyImageKHR(display, image);
}

// Uploads |p| and draws it into the texture's picture, resizing both to it.
void Draw(RiftStreamTexture* self, const WatchPlanes& p) {
  if (p.kind == kOnGpu) {
    DrawFromGpu(self, p);
    return;
  }
  SavedState saved;
  if (program == 0) BuildProgram();
  const uint32_t cw = (p.width + 1) / 2, ch = (p.height + 1) / 2;
  Size(self, p);

  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  glPixelStorei(GL_UNPACK_SKIP_ROWS, 0);
  glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0);
  const uint8_t* data[3] = {p.y, p.u, p.v};
  const uint32_t strides[3] = {p.stride_y, p.stride_u, p.stride_v};
  for (int i = 0; i < 3; i++) {
    glActiveTexture(GL_TEXTURE0 + i);
    glBindTexture(GL_TEXTURE_2D, self->planes[i]);
    glBindSampler(i, 0);
    glPixelStorei(GL_UNPACK_ROW_LENGTH, static_cast<GLint>(strides[i]));
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0,
                    static_cast<GLsizei>(i ? cw : p.width),
                    static_cast<GLsizei>(i ? ch : p.height), GL_RED,
                    GL_UNSIGNED_BYTE, data[i]);
  }
  glUseProgram(program);
  Fill(self, p);
}

// Before the first picture: one black pixel, so Flutter has something to show.
void DrawBlack(RiftStreamTexture* self) {
  SavedState saved;
  const uint8_t black[4] = {0, 0, 0, 255};
  glGenTextures(1, &self->out);
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
  glActiveTexture(GL_TEXTURE0);
  Allocate(self->out, GL_RGBA8, GL_RGBA, 1, 1);
  glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE,
                  black);
  self->width = self->height = 0;
}

gboolean Populate(FlTextureGL* texture, uint32_t* target, uint32_t* name,
                  uint32_t* width, uint32_t* height, GError** error) {
  RiftStreamTexture* self = RIFT_STREAM_TEXTURE(texture);
  Bury();
  WatchPlanes planes{};
  if (self->lock(static_cast<uint64_t>(self->id), &planes) == 1) {
    Draw(self, planes);
    self->unlock(static_cast<uint64_t>(self->id));
  } else if (self->out == 0) {
    DrawBlack(self);
  }
  *target = GL_TEXTURE_2D;
  *name = self->out;
  *width = self->width ? self->width : 1;
  *height = self->height ? self->height : 1;
  return TRUE;
}

// Rust's "a new picture is waiting" for texture |id|, from its own thread.
// flutter_webrtc's renderer marks its textures from libwebrtc's thread the
// same way.
extern "C" void rift_stream_texture_mark(uint64_t id) {
  std::lock_guard<std::mutex> hold(live_mutex);
  auto found = live.find(static_cast<int64_t>(id));
  if (found != live.end()) {
    fl_texture_registrar_mark_texture_frame_available(registrar,
                                                      found->second);
  }
}

// Whether a picture decoded on the GPU can be drawn here: GTK draws with EGL
// under Wayland, which imports DMA-BUFs where it has the extension. Under X11
// GTK 3 draws with GLX, which cannot.
bool TakesGpuPictures() {
  static const bool takes = [] {
    GdkDisplay* gdk = gdk_display_get_default();
    if (gdk == nullptr || !GDK_IS_WAYLAND_DISPLAY(gdk)) return false;
    // GTK's own EGL display: EGL hands back the one already made for this
    // Wayland connection.
    EGLDisplay display = eglGetDisplay(reinterpret_cast<EGLNativeDisplayType>(
        gdk_wayland_display_get_wl_display(gdk)));
    if (display == EGL_NO_DISPLAY) return false;
    return epoxy_has_egl_extension(display, "EGL_EXT_image_dma_buf_import") &&
           epoxy_has_egl_extension(display,
                                   "EGL_EXT_image_dma_buf_import_modifiers");
  }();
  return takes;
}

FlMethodResponse* Create(FlValue* args) {
  FlValue* lock = fl_value_lookup_string(args, "lock");
  FlValue* unlock = fl_value_lookup_string(args, "unlock");
  if (lock == nullptr || unlock == nullptr ||
      fl_value_get_type(lock) != FL_VALUE_TYPE_INT ||
      fl_value_get_type(unlock) != FL_VALUE_TYPE_INT ||
      fl_value_get_int(lock) == 0 || fl_value_get_int(unlock) == 0) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "bad-args", "create needs Rust's lock and unlock", nullptr));
  }
  RiftStreamTexture* self = RIFT_STREAM_TEXTURE(
      g_object_new(rift_stream_texture_get_type(), nullptr));
  self->lock = reinterpret_cast<LockFn>(fl_value_get_int(lock));
  self->unlock = reinterpret_cast<UnlockFn>(fl_value_get_int(unlock));
  FlTexture* texture = FL_TEXTURE(self);
  if (!fl_texture_registrar_register_texture(registrar, texture)) {
    g_object_unref(self);
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "register", "Flutter refused the texture", nullptr));
  }
  self->id = fl_texture_get_id(texture);
  {
    std::lock_guard<std::mutex> hold(live_mutex);
    live[self->id] = texture;
  }
  g_autoptr(FlValue) result = fl_value_new_map();
  fl_value_set_string_take(result, "textureId", fl_value_new_int(self->id));
  fl_value_set_string_take(
      result, "mark",
      fl_value_new_int(reinterpret_cast<int64_t>(&rift_stream_texture_mark)));
  fl_value_set_string_take(result, "takesGpuPictures",
                           fl_value_new_bool(TakesGpuPictures()));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

FlMethodResponse* Dispose(FlValue* args) {
  FlValue* id = fl_value_lookup_string(args, "textureId");
  if (id == nullptr || fl_value_get_type(id) != FL_VALUE_TYPE_INT) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "bad-args", "dispose needs a textureId", nullptr));
  }
  FlTexture* texture = nullptr;
  {
    std::lock_guard<std::mutex> hold(live_mutex);
    auto found = live.find(fl_value_get_int(id));
    if (found != live.end()) {
      texture = found->second;
      live.erase(found);
    }
  }
  if (texture != nullptr) {
    fl_texture_registrar_unregister_texture(registrar, texture);
    g_object_unref(texture);
  }
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

void OnCall(FlMethodChannel* channel, FlMethodCall* call, gpointer) {
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("bad-args", "expected a map", nullptr));
  } else if (strcmp(method, "create") == 0) {
    response = Create(args);
  } else if (strcmp(method, "dispose") == 0) {
    response = Dispose(args);
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}

}  // namespace

// Its GL names go to the raster thread to be deleted; this may run anywhere.
static void rift_stream_texture_dispose(GObject* object) {
  RiftStreamTexture* self = RIFT_STREAM_TEXTURE(object);
  if (self->out != 0) {
    std::lock_guard<std::mutex> hold(dead_mutex);
    for (GLuint plane : self->planes) {
      if (plane != 0) dead_textures.push_back(plane);
    }
    for (GLuint layer : self->layers) {
      if (layer != 0) dead_textures.push_back(layer);
    }
    dead_textures.push_back(self->out);
    if (self->fbo != 0) dead_framebuffers.push_back(self->fbo);
    self->out = self->fbo = 0;
    self->planes[0] = self->planes[1] = self->planes[2] = 0;
    self->layers[0] = self->layers[1] = 0;
  }
  G_OBJECT_CLASS(rift_stream_texture_parent_class)->dispose(object);
}

static void rift_stream_texture_class_init(RiftStreamTextureClass* klass) {
  FL_TEXTURE_GL_CLASS(klass)->populate = Populate;
  G_OBJECT_CLASS(klass)->dispose = rift_stream_texture_dispose;
}

static void rift_stream_texture_init(RiftStreamTexture* self) {}

namespace rift {

void InstallStreamTextures(FlView* view) {
  g_autoptr(FlPluginRegistrar) plugin = fl_plugin_registry_get_registrar_for_plugin(
      FL_PLUGIN_REGISTRY(view), "RiftStreamTexture");
  registrar = FL_TEXTURE_REGISTRAR(
      g_object_ref(fl_plugin_registrar_get_texture_registrar(plugin)));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(plugin),
                            "rift/stream_texture", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, OnCall, nullptr, nullptr);
}

}  // namespace rift
