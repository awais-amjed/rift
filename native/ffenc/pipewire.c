/* pipewire.c — a Wayland share's PipeWire stream, its pictures handed up to
 * Rust as DMA-BUFs or memory buffers.
 *
 * From OBS Studio's plugins/linux-pipewire/pipewire.c (at 1d4d119). Kept as
 * OBS wrote them: build_format and build_format_params, init_format_info,
 * remove_modifier_from_format and renegotiate_format,
 * return_unused_pw_buffer and find_latest_buffer, on_param_changed_cb, and
 * the state and core callbacks. Changed for Rift: OBS's source, textures,
 * cursor and rendering are gone; one stream per connection; GLib and OBS's
 * arrays replaced by plain C; the explicit-sync acquire point is waited on
 * here, on the CPU, where OBS has its GPU wait, and the release point is
 * signalled when Rust gives the buffer back; the picture handed up carries
 * the crop and turn OBS reads, for the encoder to apply; the format asks
 * for a maxFramerate, which OBS leaves to the compositor; and a buffer lent
 * to Rust keeps its memory and fds after PipeWire frees it (struct Held),
 * since OBS uses each buffer inside its process callback and Rift does not.
 *
 * Copyright 2020 Georges Basile Stavracas Neto <georges.stavracas@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
#include "ffenc.h"

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#include <drm_fourcc.h>
#include <libavutil/log.h>
#include <pipewire/pipewire.h>
#include <spa/buffer/meta.h>
#include <spa/debug/types.h>
#include <spa/param/video/format-utils.h>
#include <spa/param/video/type-info.h>
#include <spa/utils/result.h>
#include <xf86drm.h>

#include "dmabuf_caps.h"

// Rust holds at most this many; a newer picture while it does goes back.
#define MAX_HELD 2

// How long a picture's acquire point may take to signal before it is
// dropped: the compositor is still drawing it.
#define ACQUIRE_TIMEOUT_NS (100 * 1000 * 1000)

struct pw_version {
  int major;
  int minor;
  int micro;
};

struct format_info {
  uint32_t spa_format;
  uint32_t drm_format;
  // Memory buffers come only in BGRx and BGRA, the bytes Rust's raw path
  // reads; DMA-BUFs in all four.
  bool memory;
  uint64_t* modifiers;
  size_t n_modifiers;
};

// 8-bit RGB only: 10-bit and HDR formats are refused for now. No alpha
// first, since the encoder never reads it.
static const struct {
  uint32_t spa_format;
  uint32_t drm_format;
  bool memory;
} supported_formats[] = {
    {SPA_VIDEO_FORMAT_BGRx, DRM_FORMAT_XRGB8888, true},
    {SPA_VIDEO_FORMAT_BGRA, DRM_FORMAT_ARGB8888, true},
    {SPA_VIDEO_FORMAT_RGBx, DRM_FORMAT_XBGR8888, false},
    {SPA_VIDEO_FORMAT_RGBA, DRM_FORMAT_ABGR8888, false},
};

#define N_SUPPORTED_FORMATS \
  (sizeof(supported_formats) / sizeof(supported_formats[0]))

struct RiftPwStream {
  struct pw_thread_loop* thread_loop;
  struct pw_context* context;

  struct pw_core* core;
  struct spa_hook core_listener;
  int sync_id;
  bool synced;
  int core_error;

  struct pw_version server_version;

  struct pw_stream* stream;
  struct spa_hook stream_listener;
  struct spa_source* reneg;

  struct spa_video_info format;
  bool negotiated;

  struct format_info format_info[N_SUPPORTED_FORMATS];
  size_t n_format_info;

  int32_t buffers;
  int32_t max_fps;

  // The render node, for the explicit-sync timeline's sync objects.
  int drm_fd;
  bool explicit_sync;

  RiftPwCallbacks callbacks;
  int held;
  // Closed by Rust: no more callbacks, and freed once nothing is held.
  bool closing;
  bool ended;
  bool warned_format;
  bool logged_sync;
};

/* auxiliary methods */

// A buffer as Rust holds it. PipeWire frees a stream's buffers whenever it
// renegotiates — a switch of buffer kind, a resized window — unmapping their
// memory and closing their fds, the ones a picture still in Rust's hands
// reads among them (a crash, Oct 29 2026). So a buffer handed up has fds and
// a mapping of Rift's own, let go once PipeWire has removed the buffer and
// Rust has released every picture of it.
typedef struct Held {
  // NULL once PipeWire has removed it: nothing to queue back.
  struct pw_buffer* b;
  // PipeWire's hold, and one for each picture in Rust.
  int refs;
  int fds[4];
  // A memory buffer's own mapping, or for memory PipeWire owns, a copy.
  uint8_t* map;
  size_t map_len;
  bool copied;
} Held;

static void unref_held(Held* h) {
  if (--h->refs > 0) return;
  for (int i = 0; i < 4; i++)
    if (h->fds[i] >= 0) close(h->fds[i]);
  if (h->map && h->copied) free(h->map);
  else if (h->map) munmap(h->map, h->map_len);
  free(h);
}

static void on_add_buffer_cb(void* user_data, struct pw_buffer* b) {
  (void)user_data;
  Held* h = calloc(1, sizeof(*h));
  if (!h) return;
  h->b = b;
  h->refs = 1;
  for (int i = 0; i < 4; i++) h->fds[i] = -1;
  b->user_data = h;
}

static void on_remove_buffer_cb(void* user_data, struct pw_buffer* b) {
  (void)user_data;
  Held* h = b->user_data;
  if (!h) return;
  b->user_data = NULL;
  h->b = NULL;
  unref_held(h);
}

// The plane's fd, Rift's own copy of it.
static int held_fd(Held* h, uint32_t plane, int fd) {
  if (h->fds[plane] < 0) h->fds[plane] = fcntl(fd, F_DUPFD_CLOEXEC, 0);
  return h->fds[plane];
}

// A memory buffer's bytes, mapped by Rift from its fd, or copied when
// PipeWire's own memory is all there is. NULL when neither works.
static const uint8_t* held_data(Held* h, struct spa_data* d) {
  if (d->type == SPA_DATA_MemFd && d->fd >= 0) {
    if (!h->map) {
      size_t len = (size_t)d->mapoffset + d->maxsize;
      void* map = mmap(NULL, len, PROT_READ, MAP_SHARED, (int)d->fd, 0);
      if (map == MAP_FAILED) return NULL;
      h->map = map;
      h->map_len = len;
    }
    return h->map + d->mapoffset;
  }
  if (!h->map) {
    h->map = malloc(d->maxsize);
    if (!h->map) return NULL;
    h->map_len = d->maxsize;
    h->copied = true;
  }
  memcpy(h->map, d->data, d->maxsize);
  return h->map;
}

static bool parse_pw_version(struct pw_version* dst, const char* version) {
  int n_matches =
      sscanf(version, "%d.%d.%d", &dst->major, &dst->minor, &dst->micro);
  return n_matches == 3;
}

static bool check_pw_version(const struct pw_version* pw_version, int major,
                             int minor, int micro) {
  if (pw_version->major != major) return pw_version->major > major;
  if (pw_version->minor != minor) return pw_version->minor > minor;
  return pw_version->micro >= micro;
}

static void update_pw_versions(RiftPwStream* s, const char* version) {
  av_log(NULL, AV_LOG_INFO, "pipewire: server %s, library %s\n", version,
         pw_get_library_version());

  if (!parse_pw_version(&s->server_version, version))
    av_log(NULL, AV_LOG_WARNING,
           "pipewire: failed to parse the server version\n");
}

static void report(RiftPwStream* s, int32_t state, const char* error) {
  if (s->closing || s->ended || !s->callbacks.state) return;
  if (state == 2) s->ended = true;
  s->callbacks.state(s->callbacks.user, state, error);
}

static bool dmabuf_allowed(const RiftPwStream* s) {
  if (s->buffers != RIFT_PW_DMABUF) return false;
  for (size_t i = 0; i < s->n_format_info; i++) {
    if (s->format_info[i].n_modifiers > 0) return true;
  }
  return false;
}

static inline struct spa_pod* build_format(RiftPwStream* s,
                                           struct spa_pod_builder* b,
                                           uint32_t format,
                                           uint64_t* modifiers,
                                           size_t modifier_count) {
  struct spa_rectangle max_resolution = SPA_RECTANGLE(8192, 4320);
  struct spa_rectangle min_resolution = SPA_RECTANGLE(1, 1);
  struct spa_rectangle resolution = SPA_RECTANGLE(1920, 1080);
  struct spa_pod_frame format_frame;
  // At most the share's rate: the compositor sends a picture when the
  // screen changes, never faster than maxFramerate. Mutter fixes framerate
  // at 0/1, variable, and without a maxFramerate of ours sent at the
  // screen's refresh: 110 a second on a 165 Hz laptop screen asked for 60
  // (GNOME 50, Oct 29 2026).
  struct spa_fraction max_framerate = SPA_FRACTION((uint32_t)s->max_fps, 1);
  struct spa_fraction min_framerate = SPA_FRACTION(0, 1);
  struct spa_fraction framerate = SPA_FRACTION((uint32_t)s->max_fps, 1);
  struct spa_fraction min_max_framerate = SPA_FRACTION(1, 1);

  /* Make an object of type SPA_TYPE_OBJECT_Format and id SPA_PARAM_EnumFormat.
   * The object type is important because it defines the properties that are
   * acceptable. The id gives more context about what the object is meant to
   * contain. In this case we enumerate supported formats. */
  spa_pod_builder_push_object(b, &format_frame, SPA_TYPE_OBJECT_Format,
                              SPA_PARAM_EnumFormat);
  /* add media type and media subtype properties */
  spa_pod_builder_add(b, SPA_FORMAT_mediaType, SPA_POD_Id(SPA_MEDIA_TYPE_video),
                      0);
  spa_pod_builder_add(b, SPA_FORMAT_mediaSubtype,
                      SPA_POD_Id(SPA_MEDIA_SUBTYPE_raw), 0);

  /* formats */
  spa_pod_builder_add(b, SPA_FORMAT_VIDEO_format, SPA_POD_Id(format), 0);

  /* modifier */
  if (modifier_count > 0) {
    struct spa_pod_frame modifier_frame;

    /* build an enumeration of modifiers */
    spa_pod_builder_prop(b, SPA_FORMAT_VIDEO_modifier,
                         SPA_POD_PROP_FLAG_MANDATORY |
                             SPA_POD_PROP_FLAG_DONT_FIXATE);

    spa_pod_builder_push_choice(b, &modifier_frame, SPA_CHOICE_Enum, 0);

    /* The first element of choice pods is the preferred value. Here
     * we arbitrarily pick the first modifier as the preferred one.
     */
    spa_pod_builder_long(b, (int64_t)modifiers[0]);

    /* modifiers from  an array */
    for (uint32_t i = 0; i < modifier_count; i++)
      spa_pod_builder_long(b, (int64_t)modifiers[i]);

    spa_pod_builder_pop(b, &modifier_frame);
  }
  /* add size and framerate ranges */
  spa_pod_builder_add(
      b, SPA_FORMAT_VIDEO_size,
      SPA_POD_CHOICE_RANGE_Rectangle(&resolution, &min_resolution,
                                     &max_resolution),
      SPA_FORMAT_VIDEO_framerate,
      SPA_POD_CHOICE_RANGE_Fraction(&framerate, &min_framerate,
                                    &max_framerate),
      SPA_FORMAT_VIDEO_maxFramerate,
      SPA_POD_CHOICE_RANGE_Fraction(&max_framerate, &min_max_framerate,
                                    &max_framerate),
      0);
  return spa_pod_builder_pop(b, &format_frame);
}

static bool build_format_params(RiftPwStream* s,
                                struct spa_pod_builder* pod_builder,
                                const struct spa_pod** params,
                                uint32_t* n_params) {
  uint32_t params_count = 0;

  if (!s->n_format_info) {
    av_log(NULL, AV_LOG_ERROR,
           "pipewire: no format found while building params\n");
    return false;
  }

  if (s->buffers != RIFT_PW_DMABUF ||
      !check_pw_version(&s->server_version, 0, 3, 33))
    goto build_shm;

  for (size_t i = 0; i < s->n_format_info; i++) {
    if (s->format_info[i].n_modifiers == 0) {
      continue;
    }
    params[params_count++] = build_format(
        s, pod_builder, s->format_info[i].spa_format,
        s->format_info[i].modifiers, s->format_info[i].n_modifiers);
  }

build_shm:
  for (size_t i = 0; i < s->n_format_info; i++) {
    if (!s->format_info[i].memory) continue;
    params[params_count++] =
        build_format(s, pod_builder, s->format_info[i].spa_format, NULL, 0);
  }
  *n_params = params_count;
  return true;
}

static void init_format_info(RiftPwStream* s, const char* render_node,
                             bool refuse_dmabuf) {
  uint32_t drm_formats[N_SUPPORTED_FORMATS];
  uint64_t* modifiers[N_SUPPORTED_FORMATS];
  size_t counts[N_SUPPORTED_FORMATS];

  for (size_t i = 0; i < N_SUPPORTED_FORMATS; i++) {
    drm_formats[i] = supported_formats[i].drm_format;
    modifiers[i] = NULL;
    counts[i] = 0;
  }
  if (render_node && !refuse_dmabuf &&
      dmabuf_caps_query(render_node, N_SUPPORTED_FORMATS, drm_formats,
                        modifiers, counts) < 0) {
    av_log(NULL, AV_LOG_WARNING,
           "pipewire: EGL could not list the modifiers of %s; memory "
           "buffers only\n",
           render_node);
  }

  if (render_node && !refuse_dmabuf)
    av_log(NULL, AV_LOG_INFO,
           "pipewire: %zu, %zu, %zu and %zu modifiers import on %s\n",
           counts[0], counts[1], counts[2], counts[3], render_node);
  for (size_t i = 0; i < N_SUPPORTED_FORMATS; i++) {
    struct format_info* info = &s->format_info[s->n_format_info++];
    info->spa_format = supported_formats[i].spa_format;
    info->drm_format = supported_formats[i].drm_format;
    info->memory = supported_formats[i].memory;
    info->modifiers = modifiers[i];
    info->n_modifiers = counts[i];
  }
}

static void clear_format_info(RiftPwStream* s) {
  for (size_t i = 0; i < s->n_format_info; i++) {
    free(s->format_info[i].modifiers);
    s->format_info[i].modifiers = NULL;
    s->format_info[i].n_modifiers = 0;
  }
  s->n_format_info = 0;
}

static void remove_modifier_from_format(RiftPwStream* s, uint32_t spa_format,
                                        uint64_t modifier) {
  for (size_t i = 0; i < s->n_format_info; i++) {
    struct format_info* info = &s->format_info[i];
    if (info->spa_format != spa_format) continue;

    if (!check_pw_version(&s->server_version, 0, 3, 40)) {
      info->n_modifiers = 0;
      continue;
    }

    size_t kept = 0;
    for (size_t j = 0; j < info->n_modifiers; j++) {
      if (info->modifiers[j] != modifier)
        info->modifiers[kept++] = info->modifiers[j];
    }
    info->n_modifiers = kept;
  }
}

static void renegotiate_format(void* data, uint64_t expirations) {
  (void)expirations;
  RiftPwStream* s = data;
  const struct spa_pod* params[2 * N_SUPPORTED_FORMATS];

  av_log(NULL, AV_LOG_INFO, "pipewire: renegotiating the stream\n");

  pw_thread_loop_lock(s->thread_loop);

  uint8_t params_buffer[4096];
  struct spa_pod_builder pod_builder =
      SPA_POD_BUILDER_INIT(params_buffer, sizeof(params_buffer));
  uint32_t n_params;
  if (!build_format_params(s, &pod_builder, params, &n_params)) {
    report(s, 2, "no format left to offer");
    pw_thread_loop_unlock(s->thread_loop);
    return;
  }

  pw_stream_update_params(s->stream, params, n_params);
  pw_thread_loop_unlock(s->thread_loop);
}

/* ------------------------------------------------- */

// Explicit sync came in PipeWire 1.2. Built against older headers (Ubuntu
// 24.04, where the release is built, has 1.0) it is left out, as OBS does.
#if PW_CHECK_VERSION(1, 2, 0)
static void signal_timeline_point(RiftPwStream* s, int syncobj_fd,
                                  uint64_t timeline_point) {
  uint32_t syncobj_handle = 0;

  if (drmSyncobjFDToHandle(s->drm_fd, syncobj_fd, &syncobj_handle) != 0)
    return;
  drmSyncobjTimelineSignal(s->drm_fd, &syncobj_handle, &timeline_point, 1);
  drmSyncobjDestroy(s->drm_fd, syncobj_handle);
}

// Waits for the compositor to finish drawing the buffer. OBS has the GPU
// wait for it; the encoder's import does not, so the CPU waits here.
static bool wait_timeline_point(RiftPwStream* s, int syncobj_fd,
                                uint64_t timeline_point) {
  uint32_t syncobj_handle = 0;
  struct timespec now;

  if (drmSyncobjFDToHandle(s->drm_fd, syncobj_fd, &syncobj_handle) != 0)
    return false;
  clock_gettime(CLOCK_MONOTONIC, &now);
  int64_t deadline =
      (int64_t)now.tv_sec * 1000000000 + now.tv_nsec + ACQUIRE_TIMEOUT_NS;
  int result = drmSyncobjTimelineWait(
      s->drm_fd, &syncobj_handle, &timeline_point, 1, deadline,
      DRM_SYNCOBJ_WAIT_FLAGS_WAIT_FOR_SUBMIT, NULL);
  drmSyncobjDestroy(s->drm_fd, syncobj_handle);
  return result == 0;
}
#endif

static void return_unused_pw_buffer(RiftPwStream* s, struct pw_buffer* b) {
#if PW_CHECK_VERSION(1, 2, 0)
  struct spa_buffer* buffer = b->buffer;
  struct spa_data* last_data = &buffer->datas[buffer->n_datas - 1];
  struct spa_meta_sync_timeline* synctimeline = spa_buffer_find_meta_data(
      buffer, SPA_META_SyncTimeline, sizeof(struct spa_meta_sync_timeline));

  if (synctimeline && (last_data->type == SPA_DATA_SyncObj) &&
      s->drm_fd >= 0)
    signal_timeline_point(s, (int)last_data->fd, synctimeline->release_point);
#endif
  pw_stream_queue_buffer(s->stream, b);
}

static inline struct pw_buffer* find_latest_buffer(RiftPwStream* s) {
  struct pw_buffer* b;

  /* Find the most recent buffer */
  b = NULL;
  while (true) {
    struct pw_buffer* aux = pw_stream_dequeue_buffer(s->stream);
    if (!aux) break;
    if (b) return_unused_pw_buffer(s, b);
    b = aux;
  }

  return b;
}

static uint32_t get_spa_buffer_plane_count(const struct spa_buffer* buffer) {
  uint32_t plane_count = 0;

  while (plane_count < buffer->n_datas) {
    if (buffer->datas[plane_count].type == SPA_DATA_DmaBuf)
      plane_count++;
    else
      break;
  }

  return plane_count;
}

static const struct format_info* format_of(const RiftPwStream* s) {
  for (size_t i = 0; i < s->n_format_info; i++) {
    if (s->format_info[i].spa_format == s->format.info.raw.format)
      return &s->format_info[i];
  }
  return NULL;
}

static bool quarter_turned(uint32_t transform) {
  switch (transform) {
    case SPA_META_TRANSFORMATION_90:
    case SPA_META_TRANSFORMATION_270:
    case SPA_META_TRANSFORMATION_Flipped90:
    case SPA_META_TRANSFORMATION_Flipped270:
      return true;
    default:
      return false;
  }
}

static int64_t monotonic_ns(void) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return (int64_t)now.tv_sec * 1000000000 + now.tv_nsec;
}

// OBS's process_video_sync, up to the texture: the newest buffer, its crop,
// turn and sync points, handed to Rust instead of drawn.
static void on_process_cb(void* user_data) {
  RiftPwStream* s = user_data;
  struct spa_meta_header* header;
  struct spa_meta_region* region;
  struct spa_meta_videotransform* video_transform;
  struct spa_buffer* buffer;
  struct pw_buffer* b;

  b = find_latest_buffer(s);
  if (!b) return;

  buffer = b->buffer;
  Held* h = b->user_data;
  if (!h || s->closing || s->held >= MAX_HELD) goto drop;

  header = spa_buffer_find_meta_data(buffer, SPA_META_Header, sizeof(*header));
  if (header && (header->flags & SPA_META_HEADER_FLAG_CORRUPTED) > 0) {
    av_log(NULL, AV_LOG_DEBUG, "pipewire: buffer is corrupt\n");
    goto drop;
  }

  // Workaround for kwin behaviour pre 5.27.5
  // Workaround for mutter behaviour pre GNOME 43
  // Only check this if !SPA_META_Header, once supported platforms update.
  // An empty buffer is also what a cursor that moved alone brings.
  if (buffer->datas[0].chunk->size == 0) goto drop;

  const struct format_info* format = format_of(s);
  if (!format) goto drop;

  uint32_t width = s->format.info.raw.size.width;
  uint32_t height = s->format.info.raw.size.height;
  RiftPwPicture picture = {0};

  /* Video Crop */
  region = spa_buffer_find_meta_data(buffer, SPA_META_VideoCrop,
                                     sizeof(*region));
  int32_t crop_x = 0, crop_y = 0;
  uint32_t crop_w = width, crop_h = height;
  if (region && spa_meta_region_is_valid(region) &&
      region->region.position.x >= 0 && region->region.position.y >= 0 &&
      (uint64_t)region->region.position.x + region->region.size.width <=
          width &&
      (uint64_t)region->region.position.y + region->region.size.height <=
          height) {
    crop_x = region->region.position.x;
    crop_y = region->region.position.y;
    crop_w = region->region.size.width;
    crop_h = region->region.size.height;
  }
  bool has_crop = crop_x != 0 || crop_y != 0 || crop_w < width ||
                  crop_h < height;

  /* Video Transform */
  video_transform = spa_buffer_find_meta_data(
      buffer, SPA_META_VideoTransform, sizeof(*video_transform));
  uint32_t transform =
      video_transform ? video_transform->transform : SPA_META_TRANSFORMATION_None;

  if (buffer->datas[0].type == SPA_DATA_DmaBuf) {
    uint32_t planes = get_spa_buffer_plane_count(buffer);
    bool corrupt = false;
#if PW_CHECK_VERSION(1, 2, 0)
    struct spa_meta_sync_timeline* synctimeline = spa_buffer_find_meta_data(
        buffer, SPA_META_SyncTimeline, sizeof(struct spa_meta_sync_timeline));
#endif

    if (planes == 0 || planes > 4) goto drop;

    RiftDmabuf* dmabuf = &picture.dmabuf;
    dmabuf->width = (int32_t)width;
    dmabuf->height = (int32_t)height;
    if (has_crop) {
      dmabuf->crop_x = crop_x;
      dmabuf->crop_y = crop_y;
      dmabuf->crop_width = (int32_t)crop_w;
      dmabuf->crop_height = (int32_t)crop_h;
    }
    dmabuf->drm_format = format->drm_format;
    dmabuf->modifier = s->format.info.raw.modifier;
    dmabuf->planes = (int32_t)planes;
    dmabuf->transform = (int32_t)transform;
    for (uint32_t plane = 0; plane < planes; plane++) {
      dmabuf->fds[plane] = held_fd(h, plane, (int)buffer->datas[plane].fd);
      if (dmabuf->fds[plane] < 0) goto drop;
      dmabuf->offsets[plane] = buffer->datas[plane].chunk->offset;
      dmabuf->strides[plane] = (uint32_t)buffer->datas[plane].chunk->stride;
      corrupt |=
          (buffer->datas[plane].chunk->flags & SPA_CHUNK_FLAG_CORRUPTED) > 0;
    }

    if (corrupt) {
      av_log(NULL, AV_LOG_DEBUG, "pipewire: buffer contains corrupted data\n");
      goto drop;
    }

#if PW_CHECK_VERSION(1, 2, 0)
    if (synctimeline && (buffer->n_datas == (planes + 2))) {
      if (s->drm_fd < 0 ||
          buffer->datas[planes].type != SPA_DATA_SyncObj ||
          !wait_timeline_point(s, (int)buffer->datas[planes].fd,
                               synctimeline->acquire_point)) {
        av_log(NULL, AV_LOG_DEBUG,
               "pipewire: the compositor did not finish a picture\n");
        goto drop;
      }
      if (!s->logged_sync) {
        av_log(NULL, AV_LOG_INFO, "pipewire: the compositor syncs explicitly\n");
        s->logged_sync = true;
      }
    }
#endif
    picture.buffers = RIFT_PW_DMABUF;
  } else if (buffer->datas[0].data) {
    struct spa_data* d = &buffer->datas[0];

    if (!format->memory) {
      if (!s->warned_format) {
        av_log(NULL, AV_LOG_WARNING,
               "pipewire: a memory buffer in format %u, not BGRx or BGRA\n",
               s->format.info.raw.format);
        s->warned_format = true;
      }
      goto drop;
    }

    if ((d->chunk->flags & SPA_CHUNK_FLAG_CORRUPTED) > 0) {
      av_log(NULL, AV_LOG_DEBUG, "pipewire: buffer contains corrupted data\n");
      goto drop;
    }

    uint32_t stride =
        d->chunk->stride > 0 ? (uint32_t)d->chunk->stride : width * 4;
    uint64_t offset = d->chunk->offset;
    uint64_t start = offset + (uint64_t)crop_y * stride + (uint64_t)crop_x * 4;
    uint64_t len = (uint64_t)stride * (crop_h - 1) + (uint64_t)crop_w * 4;
    if (stride < width * 4 || start + len > d->maxsize) {
      av_log(NULL, AV_LOG_DEBUG, "pipewire: a memory buffer too small\n");
      goto drop;
    }
    const uint8_t* data = held_data(h, d);
    if (!data) goto drop;
    // Whole rows where the buffer has them, as libyuv's callers check for: a
    // window's crop stops short of the stride on its last row.
    uint64_t rows = (uint64_t)stride * crop_h;
    if (start + rows <= d->maxsize) len = rows;
    picture.data = data + start;
    picture.len = (size_t)len;
    picture.stride = (int32_t)stride;
    picture.buffers = RIFT_PW_MEMORY;
  } else {
    goto drop;
  }

  picture.transform = (int32_t)transform;
  picture.width = (int32_t)(quarter_turned(transform) ? crop_h : crop_w);
  picture.height = (int32_t)(quarter_turned(transform) ? crop_w : crop_h);
  picture.pts_ns = header && header->pts >= 0 ? header->pts : monotonic_ns();
  picture.stream = s;
  picture.held = h;
  h->refs++;
  s->held++;
  s->callbacks.picture(s->callbacks.user, &picture);
  return;

drop:
  return_unused_pw_buffer(s, b);
}

static void on_param_changed_cb(void* user_data, uint32_t id,
                                const struct spa_pod* param) {
  RiftPwStream* s = user_data;
  struct spa_pod_builder pod_builder;
  const struct spa_pod* params[7];
  const char* format_name;
  uint32_t n_params = 0;
  uint32_t buffer_types;
  uint8_t params_buffer[1024];
  int result;
#if PW_CHECK_VERSION(1, 2, 0)
  bool supports_explicit_sync = false;
#endif

  if (!param || id != SPA_PARAM_Format) return;

  result = spa_format_parse(param, &s->format.media_type,
                            &s->format.media_subtype);
  if (result < 0) return;

  if (s->format.media_type != SPA_MEDIA_TYPE_video ||
      s->format.media_subtype != SPA_MEDIA_SUBTYPE_raw)
    return;

  spa_format_video_raw_parse(param, &s->format.info.raw);

  buffer_types = (1 << SPA_DATA_MemPtr) | (1 << SPA_DATA_MemFd);
  bool has_modifier =
      spa_pod_find_prop(param, NULL, SPA_FORMAT_VIDEO_modifier) != NULL;
  if (!has_modifier) s->format.info.raw.modifier = DRM_FORMAT_MOD_INVALID;
  if ((has_modifier || check_pw_version(&s->server_version, 0, 3, 24)) &&
      dmabuf_allowed(s)) {
    buffer_types |= 1 << SPA_DATA_DmaBuf;
#if PW_CHECK_VERSION(1, 2, 0)
    supports_explicit_sync = s->explicit_sync;
#endif
  }

  format_name = spa_debug_type_find_name(spa_type_video_format,
                                         s->format.info.raw.format);
  char modifier[32] = "memory";
  if (has_modifier)
    snprintf(modifier, sizeof(modifier), "modifier 0x%" PRIx64,
             s->format.info.raw.modifier);
  av_log(NULL, AV_LOG_INFO,
         "pipewire: negotiated %s, %s, %ux%u, %u/%u, at most %u/%u\n",
         format_name ? format_name : "an unknown format", modifier,
         s->format.info.raw.size.width, s->format.info.raw.size.height,
         s->format.info.raw.framerate.num, s->format.info.raw.framerate.denom,
         s->format.info.raw.max_framerate.num,
         s->format.info.raw.max_framerate.denom);

  /* Video crop */
  pod_builder = SPA_POD_BUILDER_INIT(params_buffer, sizeof(params_buffer));
  params[n_params++] = spa_pod_builder_add_object(
      &pod_builder, SPA_TYPE_OBJECT_ParamMeta, SPA_PARAM_Meta,
      SPA_PARAM_META_type, SPA_POD_Id(SPA_META_VideoCrop), SPA_PARAM_META_size,
      SPA_POD_Int(sizeof(struct spa_meta_region)));

  /* Buffer options */
#if PW_CHECK_VERSION(1, 2, 0)
  if (supports_explicit_sync) {
    struct spa_pod_frame dmabuf_explicit_sync_frame;

    spa_pod_builder_push_object(&pod_builder, &dmabuf_explicit_sync_frame,
                                SPA_TYPE_OBJECT_ParamBuffers,
                                SPA_PARAM_Buffers);
    spa_pod_builder_add(&pod_builder, SPA_PARAM_BUFFERS_dataType,
                        SPA_POD_Int(1 << SPA_DATA_DmaBuf), 0);
    spa_pod_builder_prop(&pod_builder, SPA_PARAM_BUFFERS_metaType,
                         SPA_POD_PROP_FLAG_MANDATORY);
    spa_pod_builder_int(&pod_builder, 1 << SPA_META_SyncTimeline);

    params[n_params++] =
        spa_pod_builder_pop(&pod_builder, &dmabuf_explicit_sync_frame);
  }
#endif

  params[n_params++] = spa_pod_builder_add_object(
      &pod_builder, SPA_TYPE_OBJECT_ParamBuffers, SPA_PARAM_Buffers,
      SPA_PARAM_BUFFERS_dataType, SPA_POD_Int(buffer_types));

  /* Sync timeline */
#if PW_CHECK_VERSION(1, 2, 0)
  if (supports_explicit_sync) {
    params[n_params++] = spa_pod_builder_add_object(
        &pod_builder, SPA_TYPE_OBJECT_ParamMeta, SPA_PARAM_Meta,
        SPA_PARAM_META_type, SPA_POD_Id(SPA_META_SyncTimeline),
        SPA_PARAM_META_size,
        SPA_POD_Int(sizeof(struct spa_meta_sync_timeline)));
  }
#endif

  /* Meta header */
  params[n_params++] = spa_pod_builder_add_object(
      &pod_builder, SPA_TYPE_OBJECT_ParamMeta, SPA_PARAM_Meta,
      SPA_PARAM_META_type, SPA_POD_Id(SPA_META_Header), SPA_PARAM_META_size,
      SPA_POD_Int(sizeof(struct spa_meta_header)));

  if (check_pw_version(&s->server_version, 0, 3, 62)) {
    /* Video transformation */
    params[n_params++] = spa_pod_builder_add_object(
        &pod_builder, SPA_TYPE_OBJECT_ParamMeta, SPA_PARAM_Meta,
        SPA_PARAM_META_type, SPA_POD_Id(SPA_META_VideoTransform),
        SPA_PARAM_META_size,
        SPA_POD_Int(sizeof(struct spa_meta_videotransform)));
  }
  pw_stream_update_params(s->stream, params, n_params);
  s->negotiated = true;
}

static void on_state_changed_cb(void* user_data, enum pw_stream_state old,
                                enum pw_stream_state state,
                                const char* error) {
  (void)old;
  RiftPwStream* s = user_data;

  av_log(NULL, AV_LOG_INFO, "pipewire: stream state %s (error: %s)\n",
         pw_stream_state_as_string(state), error ? error : "none");
  switch (state) {
    case PW_STREAM_STATE_STREAMING:
      report(s, 0, NULL);
      break;
    case PW_STREAM_STATE_PAUSED:
      report(s, 1, NULL);
      break;
    case PW_STREAM_STATE_ERROR:
      report(s, 2, error ? error : "the stream failed");
      break;
    case PW_STREAM_STATE_UNCONNECTED:
      report(s, 2, "the stream was disconnected");
      break;
    default:
      break;
  }
}

static const struct pw_stream_events stream_events = {
    PW_VERSION_STREAM_EVENTS,
    .state_changed = on_state_changed_cb,
    .param_changed = on_param_changed_cb,
    .process = on_process_cb,
    .add_buffer = on_add_buffer_cb,
    .remove_buffer = on_remove_buffer_cb,
};

static void on_core_info_cb(void* user_data, const struct pw_core_info* info) {
  RiftPwStream* s = user_data;

  update_pw_versions(s, info->version);
}

static void on_core_error_cb(void* user_data, uint32_t id, int seq, int res,
                             const char* message) {
  RiftPwStream* s = user_data;

  av_log(NULL, AV_LOG_ERROR, "pipewire: error id:%u seq:%d res:%d (%s): %s\n",
         id, seq, res, spa_strerror(res), message);

  if (id == PW_ID_CORE) {
    s->core_error = res;
    report(s, 2, message ? message : "PipeWire failed");
  }
  pw_thread_loop_signal(s->thread_loop, false);
}

static void on_core_done_cb(void* user_data, uint32_t id, int seq) {
  RiftPwStream* s = user_data;

  if (id == PW_ID_CORE && s->sync_id == seq) {
    s->synced = true;
    pw_thread_loop_signal(s->thread_loop, false);
  }
}

static const struct pw_core_events core_events = {
    PW_VERSION_CORE_EVENTS,
    .info = on_core_info_cb,
    .done = on_core_done_cb,
    .error = on_core_error_cb,
};

/* Rift's interface */

static void destroy(RiftPwStream* s) {
  // Disconnecting changes the state; nobody hears it now.
  s->closing = true;
  if (s->thread_loop) {
    pw_thread_loop_lock(s->thread_loop);
    if (s->stream) {
      pw_stream_disconnect(s->stream);
      pw_stream_destroy(s->stream);
      s->stream = NULL;
    }
    if (s->reneg) {
      pw_loop_destroy_source(pw_thread_loop_get_loop(s->thread_loop),
                             s->reneg);
      s->reneg = NULL;
    }
    if (s->core) {
      spa_hook_remove(&s->core_listener);
      pw_core_disconnect(s->core);
      s->core = NULL;
    }
    pw_thread_loop_unlock(s->thread_loop);
    pw_thread_loop_stop(s->thread_loop);
  }
  if (s->context) pw_context_destroy(s->context);
  if (s->thread_loop) pw_thread_loop_destroy(s->thread_loop);
  if (s->drm_fd >= 0) close(s->drm_fd);
  clear_format_info(s);
  free(s);
  pw_deinit();
}

static void fail(char* error, size_t error_len, const char* what) {
  if (error && error_len) snprintf(error, error_len, "%s", what);
}

RiftPwStream* rift_pw_open(int32_t fd, uint32_t node_id, int32_t max_fps,
                           const char* render_node, int32_t buffers,
                           const RiftPwCallbacks* callbacks, char* error,
                           size_t error_len) {
  if (!callbacks || !callbacks->picture || max_fps <= 0) {
    fail(error, error_len, "the stream was asked for nothing");
    return NULL;
  }
  pw_init(NULL, NULL);
  RiftPwStream* s = calloc(1, sizeof(*s));
  if (!s) {
    pw_deinit();
    fail(error, error_len, "out of memory");
    return NULL;
  }
  s->drm_fd = -1;
  s->callbacks = *callbacks;
  s->buffers = buffers;
  s->max_fps = max_fps;

  // A test's way to see the memory fall back on a GPU that imports.
  const char* refuse = getenv("RIFT_PW_REFUSE_DMABUF");
  bool refuse_dmabuf = refuse && strcmp(refuse, "1") == 0;
  init_format_info(s, render_node, refuse_dmabuf);
  if (render_node && !refuse_dmabuf) {
    s->drm_fd = open(render_node, O_RDWR | O_CLOEXEC);
    uint64_t syncobj = 0, timeline = 0;
    if (s->drm_fd >= 0) {
      drmGetCap(s->drm_fd, DRM_CAP_SYNCOBJ, &syncobj);
      drmGetCap(s->drm_fd, DRM_CAP_SYNCOBJ_TIMELINE, &timeline);
    }
    s->explicit_sync = syncobj && timeline;
  }

  s->thread_loop = pw_thread_loop_new("rift-pipewire", NULL);
  if (!s->thread_loop) {
    fail(error, error_len, "PipeWire's thread did not start");
    destroy(s);
    return NULL;
  }
  s->context =
      pw_context_new(pw_thread_loop_get_loop(s->thread_loop), NULL, 0);
  if (!s->context || pw_thread_loop_start(s->thread_loop) < 0) {
    fail(error, error_len, "PipeWire's thread did not start");
    destroy(s);
    return NULL;
  }

  pw_thread_loop_lock(s->thread_loop);

  /* Core */
  s->core = pw_context_connect_fd(s->context, fcntl(fd, F_DUPFD_CLOEXEC, 5),
                                  NULL, 0);
  if (!s->core) {
    snprintf(error, error_len, "PipeWire did not connect: %s",
             strerror(errno));
    pw_thread_loop_unlock(s->thread_loop);
    destroy(s);
    return NULL;
  }

  pw_core_add_listener(s->core, &s->core_listener, &core_events, s);

  // Dispatch to receive the info core event
  s->sync_id = pw_core_sync(s->core, PW_ID_CORE, s->sync_id);
  while (!s->synced && !s->core_error) {
    if (pw_thread_loop_timed_wait(s->thread_loop, 5) != 0) break;
  }
  if (!s->synced) {
    pw_thread_loop_unlock(s->thread_loop);
    fail(error, error_len, "PipeWire did not answer");
    destroy(s);
    return NULL;
  }

  /* Signal to renegotiate */
  s->reneg = pw_loop_add_event(pw_thread_loop_get_loop(s->thread_loop),
                               renegotiate_format, s);

  /* Stream */
  s->stream = pw_stream_new(
      s->core, "Rift screen share",
      pw_properties_new(PW_KEY_MEDIA_TYPE, "Video", PW_KEY_MEDIA_CATEGORY,
                        "Capture", PW_KEY_MEDIA_ROLE, "Screen", NULL));
  if (!s->stream) {
    pw_thread_loop_unlock(s->thread_loop);
    fail(error, error_len, "PipeWire made no stream");
    destroy(s);
    return NULL;
  }
  pw_stream_add_listener(s->stream, &s->stream_listener, &stream_events, s);

  /* Stream parameters */
  uint8_t params_buffer[4096];
  struct spa_pod_builder pod_builder =
      SPA_POD_BUILDER_INIT(params_buffer, sizeof(params_buffer));
  const struct spa_pod* params[2 * N_SUPPORTED_FORMATS];
  uint32_t n_params;
  if (!build_format_params(s, &pod_builder, params, &n_params)) {
    pw_thread_loop_unlock(s->thread_loop);
    fail(error, error_len, "no format to offer");
    destroy(s);
    return NULL;
  }

  int connected = pw_stream_connect(
      s->stream, PW_DIRECTION_INPUT, node_id,
      PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS, params,
      n_params);
  pw_thread_loop_unlock(s->thread_loop);
  if (connected < 0) {
    snprintf(error, error_len, "the stream did not connect: %s",
             spa_strerror(connected));
    destroy(s);
    return NULL;
  }
  return s;
}

void rift_pw_set_buffers(RiftPwStream* s, int32_t buffers) {
  if (!s) return;
  pw_thread_loop_lock(s->thread_loop);
  if (s->buffers != buffers) {
    s->buffers = buffers;
    pw_loop_signal_event(pw_thread_loop_get_loop(s->thread_loop), s->reneg);
  }
  pw_thread_loop_unlock(s->thread_loop);
}

void rift_pw_set_max_fps(RiftPwStream* s, int32_t max_fps) {
  if (!s || max_fps <= 0) return;
  pw_thread_loop_lock(s->thread_loop);
  if (s->max_fps != max_fps) {
    s->max_fps = max_fps;
    pw_loop_signal_event(pw_thread_loop_get_loop(s->thread_loop), s->reneg);
  }
  pw_thread_loop_unlock(s->thread_loop);
}

void rift_pw_drop_modifier(RiftPwStream* s, uint32_t drm_format,
                           uint64_t modifier) {
  if (!s) return;
  pw_thread_loop_lock(s->thread_loop);
  for (size_t i = 0; i < s->n_format_info; i++) {
    if (s->format_info[i].drm_format != drm_format) continue;
    av_log(NULL, AV_LOG_INFO,
           "pipewire: modifier 0x%" PRIx64 " did not import, dropped\n",
           modifier);
    remove_modifier_from_format(s, s->format_info[i].spa_format, modifier);
    pw_loop_signal_event(pw_thread_loop_get_loop(s->thread_loop), s->reneg);
  }
  pw_thread_loop_unlock(s->thread_loop);
}

void rift_pw_release(RiftPwStream* s, void* held) {
  if (!s || !held) return;
  pw_thread_loop_lock(s->thread_loop);
  Held* h = held;
  if (h->b) return_unused_pw_buffer(s, h->b);
  unref_held(h);
  s->held--;
  bool last = s->closing && s->held == 0;
  pw_thread_loop_unlock(s->thread_loop);
  if (last) destroy(s);
}

void rift_pw_close(RiftPwStream* s) {
  if (!s) return;
  pw_thread_loop_lock(s->thread_loop);
  s->closing = true;
  // Nothing more is drawn for a stream nobody takes pictures from.
  pw_stream_set_active(s->stream, false);
  bool now = s->held == 0;
  pw_thread_loop_unlock(s->thread_loop);
  if (now) destroy(s);
}
