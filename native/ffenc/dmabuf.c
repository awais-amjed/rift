// A DMA-BUF made into an NV12 picture on VAAPI; see dmabuf.h.
//
// FFmpeg's own filters do the work, the chain `kmsgrab` users run: the buffer
// as a DRM_PRIME frame, `hwmap` into VAAPI, `scale_vaapi` (which reads the
// frame's crop) to NV12, `transpose_vaapi` when the compositor turned it, and
// `pad_vaapi` for black bars round a picture smaller than the share. The
// graph is built for one input shape and built again when it changes.
#include "dmabuf.h"

#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include <drm_fourcc.h>
#include <libavfilter/avfilter.h>
#include <libavfilter/buffersink.h>
#include <libavfilter/buffersrc.h>
#include <libavutil/hwcontext.h>
#include <libavutil/hwcontext_drm.h>
#include <libavutil/hwcontext_vaapi.h>
#include <libavutil/pixdesc.h>
#include <va/va.h>
#include <va/va_drmcommon.h>

// What a graph is built for: a change in any of it builds another.
typedef struct Shape {
  int32_t width, height;
  uint32_t drm_format;
  int32_t crop_x, crop_y, crop_width, crop_height;
  int32_t transform;
  RiftRect place;
  int32_t out_w, out_h;
} Shape;

struct DmabufPath {
  AVBufferRef* vaapi;
  AVBufferRef* drm;
  AVBufferRef* drm_frames;
  AVFilterGraph* graph;
  AVFilterContext* source;
  AVFilterContext* sink;
  Shape shape;
  // The last format and modifier that imported, so each new pair is tried
  // once (see `imports`).
  uint32_t imported_format;
  uint64_t imported_modifier;
  // Set once the GPU's video processing refused to turn a picture; it is then
  // sent as it came, and said once.
  int turn_refused;
};

static enum AVPixelFormat sw_format_of(uint32_t drm_format) {
  switch (drm_format) {
    case DRM_FORMAT_XRGB8888:
      return AV_PIX_FMT_BGR0;
    case DRM_FORMAT_ARGB8888:
      return AV_PIX_FMT_BGRA;
    case DRM_FORMAT_XBGR8888:
      return AV_PIX_FMT_RGB0;
    case DRM_FORMAT_ABGR8888:
      return AV_PIX_FMT_RGBA;
    default:
      return AV_PIX_FMT_NONE;
  }
}

// transpose_vaapi's direction that undoes SPA_META_TRANSFORMATION_*, the way
// OBS turns a picture upright (plugins/linux-pipewire/pipewire.c,
// push_rotation and get_buffer_flip): 90 is turned clockwise, 270 counter-
// clockwise, and a flipped one flipped back first. NULL for none.
static const char* turn_of(int32_t transform) {
  switch (transform) {
    case 1:
      return "clock";
    case 2:
      return "reversal";
    case 3:
      return "cclock";
    case 4:
      return "hflip";
    case 5:
      return "cclock_flip";
    case 6:
      return "vflip";
    case 7:
      return "clock_flip";
    default:
      return NULL;
  }
}

static int turns_sideways(int32_t transform) {
  return transform == 1 || transform == 3 || transform == 5 || transform == 7;
}

DmabufPath* dmabuf_path_alloc(AVBufferRef* vaapi, const char* render_node) {
  DmabufPath* path = av_mallocz(sizeof(DmabufPath));
  if (!path) return NULL;
  path->vaapi = av_buffer_ref(vaapi);
  // The DRM device is only what DRM_PRIME frames hang from; hwmap maps them
  // onto the encoder's own VAAPI device.
  int err = av_hwdevice_ctx_create(&path->drm, AV_HWDEVICE_TYPE_DRM,
                                   render_node ? render_node : "/dev/dri/renderD128",
                                   NULL, 0);
  if (err < 0 || !path->vaapi) dmabuf_path_free(&path);
  return path;
}

static void drop_graph(DmabufPath* path) {
  avfilter_graph_free(&path->graph);
  path->source = NULL;
  path->sink = NULL;
  av_buffer_unref(&path->drm_frames);
}

void dmabuf_path_free(DmabufPath** path) {
  if (!*path) return;
  drop_graph(*path);
  av_buffer_unref(&(*path)->drm);
  av_buffer_unref(&(*path)->vaapi);
  av_freep(path);
}

static AVFilterContext* add_filter(DmabufPath* path, AVFilterContext* after,
                                   const char* name, const char* args) {
  const AVFilter* filter = avfilter_get_by_name(name);
  if (!filter) return NULL;
  AVFilterContext* f = avfilter_graph_alloc_filter(path->graph, filter, name);
  if (!f) return NULL;
  if (strcmp(name, "buffer") != 0 && strcmp(name, "buffersink") != 0) {
    f->hw_device_ctx = av_buffer_ref(path->vaapi);
  }
  if (avfilter_init_str(f, args) < 0) return NULL;
  if (after && avfilter_link(after, 0, f, 0) < 0) return NULL;
  return f;
}

static int build_graph(DmabufPath* path, const Shape* s) {
  drop_graph(path);
  path->drm_frames = av_hwframe_ctx_alloc(path->drm);
  if (!path->drm_frames) return AVERROR(ENOMEM);
  AVHWFramesContext* frames = (AVHWFramesContext*)path->drm_frames->data;
  frames->format = AV_PIX_FMT_DRM_PRIME;
  frames->sw_format = sw_format_of(s->drm_format);
  frames->width = s->width;
  frames->height = s->height;
  int err = av_hwframe_ctx_init(path->drm_frames);
  if (err < 0) return err;

  path->graph = avfilter_graph_alloc();
  if (!path->graph) return AVERROR(ENOMEM);
  path->graph->nb_threads = 1;

  const AVFilter* buffer = avfilter_get_by_name("buffer");
  path->source = avfilter_graph_alloc_filter(path->graph, buffer, "in");
  if (!path->source) return AVERROR(ENOMEM);
  AVBufferSrcParameters* par = av_buffersrc_parameters_alloc();
  if (!par) return AVERROR(ENOMEM);
  par->format = AV_PIX_FMT_DRM_PRIME;
  par->width = s->width;
  par->height = s->height;
  par->time_base = (AVRational){1, 1000000};
  par->hw_frames_ctx = path->drm_frames;
  err = av_buffersrc_parameters_set(path->source, par);
  av_free(par);
  if (err < 0) return err;
  err = avfilter_init_str(path->source, NULL);
  if (err < 0) return err;

  // Scaled before it is turned, so the crop is read in the buffer's own
  // terms and the turn moves the fewest pixels.
  const char* turn = path->turn_refused ? NULL : turn_of(s->transform);
  int sideways = turn && turns_sideways(s->transform);
  int scaled_w = sideways ? s->place.height : s->place.width;
  int scaled_h = sideways ? s->place.width : s->place.height;
  char args[160];
  AVFilterContext* last = add_filter(path, path->source, "hwmap", "mode=read");
  // BT.601 in limited range, which the encoder's stream says it is.
  snprintf(args, sizeof(args),
           "w=%d:h=%d:format=nv12:out_color_matrix=smpte170m:out_range=tv",
           scaled_w, scaled_h);
  if (last) last = add_filter(path, last, "scale_vaapi", args);
  if (last && turn) {
    snprintf(args, sizeof(args), "dir=%s", turn);
    last = add_filter(path, last, "transpose_vaapi", args);
  }
  if (last && (s->place.width != s->out_w || s->place.height != s->out_h)) {
    snprintf(args, sizeof(args), "w=%d:h=%d:x=%d:y=%d:color=black", s->out_w,
             s->out_h, s->place.x, s->place.y);
    last = add_filter(path, last, "pad_vaapi", args);
  }
  if (last) path->sink = add_filter(path, last, "buffersink", NULL);
  if (!path->sink) return AVERROR(EINVAL);
  err = avfilter_graph_config(path->graph, NULL);
  if (err < 0 && turn) {
    // The driver's video processing cannot turn pictures: sent unturned.
    av_log(NULL, AV_LOG_WARNING,
           "rift: the GPU cannot turn the picture upright; sent as it is\n");
    path->turn_refused = 1;
    return build_graph(path, s);
  }
  return err;
}

static int same_buffer(int a, int b) {
  if (a == b) return 1;
  struct stat sa, sb;
  return fstat(a, &sa) == 0 && fstat(b, &sb) == 0 && sa.st_ino == sb.st_ino &&
         sa.st_dev == sb.st_dev;
}

static void free_descriptor(void* opaque, uint8_t* data) {
  (void)opaque;
  av_free(data);
}

// The buffer as FFmpeg's DRM frame. VAAPI maps only a single object, so
// planes on fds of the same buffer (PipeWire may pass one fd per plane) share
// one; different buffers are refused.
static int wrap(DmabufPath* path, const RiftDmabuf* buf, AVFrame* frame) {
  if (buf->planes < 1 || buf->planes > 4) return AVERROR(EINVAL);
  for (int i = 1; i < buf->planes; i++) {
    if (!same_buffer(buf->fds[0], buf->fds[i])) return RIFT_FFENC_IMPORT_FAILED;
  }
  AVDRMFrameDescriptor* desc = av_mallocz(sizeof(AVDRMFrameDescriptor));
  if (!desc) return AVERROR(ENOMEM);
  off_t size = lseek(buf->fds[0], 0, SEEK_END);
  desc->nb_objects = 1;
  desc->objects[0].fd = buf->fds[0];
  desc->objects[0].size = size > 0 ? (size_t)size : 0;
  desc->objects[0].format_modifier = buf->modifier;
  desc->nb_layers = 1;
  desc->layers[0].format = buf->drm_format;
  desc->layers[0].nb_planes = buf->planes;
  for (int i = 0; i < buf->planes; i++) {
    desc->layers[0].planes[i].object_index = 0;
    desc->layers[0].planes[i].offset = buf->offsets[i];
    desc->layers[0].planes[i].pitch = buf->strides[i];
  }
  frame->buf[0] = av_buffer_create((uint8_t*)desc, sizeof(*desc),
                                   free_descriptor, NULL, 0);
  if (!frame->buf[0]) {
    av_free(desc);
    return AVERROR(ENOMEM);
  }
  frame->data[0] = (uint8_t*)desc;
  frame->format = AV_PIX_FMT_DRM_PRIME;
  frame->width = buf->width;
  frame->height = buf->height;
  frame->hw_frames_ctx = av_buffer_ref(path->drm_frames);
  if (!frame->hw_frames_ctx) return AVERROR(ENOMEM);
  int has_crop = buf->crop_width > 0 && buf->crop_height > 0 &&
                 buf->crop_x >= 0 && buf->crop_y >= 0 &&
                 buf->crop_x + buf->crop_width <= buf->width &&
                 buf->crop_y + buf->crop_height <= buf->height;
  if (has_crop) {
    frame->crop_left = (size_t)buf->crop_x;
    frame->crop_top = (size_t)buf->crop_y;
    frame->crop_right = (size_t)(buf->width - buf->crop_x - buf->crop_width);
    frame->crop_bottom = (size_t)(buf->height - buf->crop_y - buf->crop_height);
  }
  return 0;
}

// Whether this format and modifier import on the GPU, asked of the driver
// directly the first time each pair is seen. FFmpeg's own mapping falls back
// to an import that leaves the modifier out when this one fails, which a
// tiled or compressed buffer comes through as garbage; the stream should be
// asked for another modifier instead.
static int imports(DmabufPath* path, const RiftDmabuf* buf, const AVFrame* frame) {
  if (buf->modifier == DRM_FORMAT_MOD_INVALID) return 1;
  if (buf->drm_format == path->imported_format &&
      buf->modifier == path->imported_modifier) {
    return 1;
  }
  const AVDRMFrameDescriptor* desc = (const AVDRMFrameDescriptor*)frame->data[0];
  AVHWDeviceContext* device = (AVHWDeviceContext*)path->vaapi->data;
  VADisplay display = ((AVVAAPIDeviceContext*)device->hwctx)->display;
  uint32_t fourcc;
  switch (buf->drm_format) {
    case DRM_FORMAT_XRGB8888:
      fourcc = VA_FOURCC_BGRX;
      break;
    case DRM_FORMAT_ARGB8888:
      fourcc = VA_FOURCC_BGRA;
      break;
    case DRM_FORMAT_XBGR8888:
      fourcc = VA_FOURCC_RGBX;
      break;
    default:
      fourcc = VA_FOURCC_RGBA;
      break;
  }
  VADRMPRIMESurfaceDescriptor prime = {
      .fourcc = fourcc,
      .width = (uint32_t)buf->width,
      .height = (uint32_t)buf->height,
      .num_objects = 1,
      .objects[0] = {.fd = desc->objects[0].fd,
                     .size = (uint32_t)desc->objects[0].size,
                     .drm_format_modifier = buf->modifier},
      .num_layers = 1,
      .layers[0] = {.drm_format = buf->drm_format,
                    .num_planes = (uint32_t)buf->planes},
  };
  for (int i = 0; i < buf->planes; i++) {
    prime.layers[0].offset[i] = buf->offsets[i];
    prime.layers[0].pitch[i] = buf->strides[i];
  }
  VASurfaceAttrib attrs[2] = {
      {.type = VASurfaceAttribMemoryType,
       .flags = VA_SURFACE_ATTRIB_SETTABLE,
       .value = {.type = VAGenericValueTypeInteger,
                 .value.i = VA_SURFACE_ATTRIB_MEM_TYPE_DRM_PRIME_2}},
      {.type = VASurfaceAttribExternalBufferDescriptor,
       .flags = VA_SURFACE_ATTRIB_SETTABLE,
       .value = {.type = VAGenericValueTypePointer, .value.p = &prime}},
  };
  VASurfaceID surface;
  if (vaCreateSurfaces(display, VA_RT_FORMAT_RGB32, (unsigned)buf->width,
                       (unsigned)buf->height, &surface, 1, attrs,
                       2) != VA_STATUS_SUCCESS) {
    return 0;
  }
  vaDestroySurfaces(display, &surface, 1);
  path->imported_format = buf->drm_format;
  path->imported_modifier = buf->modifier;
  return 1;
}

int dmabuf_path_run(DmabufPath* path, const RiftDmabuf* buf,
                    const RiftRect* place, int out_w, int out_h,
                    int64_t timestamp_us, AVFrame* out) {
  if (sw_format_of(buf->drm_format) == AV_PIX_FMT_NONE) {
    return RIFT_FFENC_IMPORT_FAILED;
  }
  Shape shape = {
      .width = buf->width,
      .height = buf->height,
      .drm_format = buf->drm_format,
      .crop_x = buf->crop_x,
      .crop_y = buf->crop_y,
      .crop_width = buf->crop_width,
      .crop_height = buf->crop_height,
      .transform = buf->transform,
      .place = place ? *place : (RiftRect){0, 0, out_w, out_h},
      .out_w = out_w,
      .out_h = out_h,
  };
  if (shape.place.width <= 0 || shape.place.height <= 0 ||
      shape.place.x < 0 || shape.place.y < 0 ||
      shape.place.x + shape.place.width > out_w ||
      shape.place.y + shape.place.height > out_h) {
    return AVERROR(EINVAL);
  }
  // Only what changes the graph: a crop moves within the same graph, since
  // scale_vaapi reads it from each frame.
  shape.crop_x = shape.crop_y = shape.crop_width = shape.crop_height = 0;
  int err = 0;
  if (!path->graph || memcmp(&shape, &path->shape, sizeof(shape)) != 0) {
    err = build_graph(path, &shape);
    if (err < 0) {
      drop_graph(path);
      return err;
    }
    path->shape = shape;
  }

  AVFrame* frame = av_frame_alloc();
  if (!frame) return AVERROR(ENOMEM);
  err = wrap(path, buf, frame);
  if (err == 0 && !imports(path, buf, frame)) err = RIFT_FFENC_IMPORT_FAILED;
  if (err < 0) {
    av_frame_free(&frame);
    return err;
  }
  frame->pts = timestamp_us;
  err = av_buffersrc_add_frame(path->source, frame);
  av_frame_free(&frame);
  if (err >= 0) err = av_buffersink_get_frame(path->sink, out);
  if (err == AVERROR(EINVAL) || err == AVERROR(EIO) || err == AVERROR(ENOSYS)) {
    // The mapping failed after all; a fresh graph is a fresh mapping, since
    // FFmpeg remembers a failed import for the frames context's life.
    drop_graph(path);
    path->imported_modifier = DRM_FORMAT_MOD_INVALID;
    return RIFT_FFENC_IMPORT_FAILED;
  }
  if (err < 0) return err;
  // Done with the buffer once the GPU has written the copy.
  AVHWDeviceContext* device = (AVHWDeviceContext*)path->vaapi->data;
  VADisplay display = ((AVVAAPIDeviceContext*)device->hwctx)->display;
  if (vaSyncSurface(display, (VASurfaceID)(uintptr_t)out->data[3]) !=
      VA_STATUS_SUCCESS) {
    av_frame_unref(out);
    return AVERROR(EIO);
  }
  return 0;
}
