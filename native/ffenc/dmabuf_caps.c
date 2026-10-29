/* dmabuf_caps.c — the DMA-BUF modifiers a GPU can read, asked of EGL.
 *
 * From OBS Studio's libobs-opengl/gl-egl-common.c (at 1d4d119):
 * query_dmabuf_formats, query_dmabuf_modifiers and the implicit-modifier
 * check, with OBS's graphics device replaced by an EGL display on a GBM
 * device for one render node, and OBS's allocator and log by libc's and
 * FFmpeg's.
 *
 * Copyright (C) 2020 by Georges Basile Stavracas Neto <georges.stavracas@gmail.com>
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
 */
#include "dmabuf_caps.h"

#include <fcntl.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <drm_fourcc.h>
#include <gbm.h>
#include <libavutil/log.h>

typedef struct Egl {
  EGLDisplay display;
  PFNEGLQUERYDMABUFFORMATSEXTPROC query_formats;
  PFNEGLQUERYDMABUFMODIFIERSEXTPROC query_modifiers;
} Egl;

static bool has_extension(const char* extensions, const char* name) {
  size_t len = strlen(name);
  for (const char* at = extensions; at && (at = strstr(at, name)); at += len) {
    if ((at == extensions || at[-1] == ' ') && (at[len] == ' ' || !at[len])) {
      return true;
    }
  }
  return false;
}

static bool query_dmabuf_formats(const Egl* egl, EGLint** formats,
                                 EGLint* num_formats) {
  EGLint max_formats = 0;

  if (!egl->query_formats(egl->display, 0, NULL, &max_formats)) {
    av_log(NULL, AV_LOG_WARNING, "egl: cannot query the number of formats\n");
    return false;
  }

  *formats = NULL;
  if (max_formats != 0) {
    EGLint* format_list = calloc((size_t)max_formats, sizeof(EGLint));
    if (!format_list) return false;

    if (!egl->query_formats(egl->display, max_formats, format_list,
                            &max_formats)) {
      av_log(NULL, AV_LOG_WARNING, "egl: cannot query a list of formats\n");
      free(format_list);
      return false;
    }

    *formats = format_list;
  }

  *num_formats = max_formats;
  return true;
}

static bool query_dmabuf_modifiers(const Egl* egl, EGLint drm_format,
                                   uint64_t** modifiers, size_t* n_modifiers) {
  EGLint max_modifiers;

  if (!egl->query_modifiers(egl->display, drm_format, 0, NULL, NULL,
                            &max_modifiers)) {
    av_log(NULL, AV_LOG_WARNING,
           "egl: cannot query the number of modifiers\n");
    return false;
  }

  *modifiers = NULL;
  if (max_modifiers != 0) {
    // One more, for the implicit modifier the caller may add.
    EGLuint64KHR* modifier_list =
        calloc((size_t)max_modifiers + 1, sizeof(EGLuint64KHR));
    if (!modifier_list) return false;

    EGLBoolean* external_only =
        calloc((size_t)max_modifiers, sizeof(EGLBoolean));
    if (!external_only) {
      free(modifier_list);
      return false;
    }

    if (!egl->query_modifiers(egl->display, drm_format, max_modifiers,
                              modifier_list, external_only, &max_modifiers)) {
      av_log(NULL, AV_LOG_WARNING, "egl: cannot query a list of modifiers\n");
      free(external_only);
      free(modifier_list);
      return false;
    }

    // Filter out external_only modifiers, since they require special
    // handling.
    for (int i = 0, j = 0; j < max_modifiers; i++) {
      if (external_only[i]) {
        max_modifiers--;
        memmove(&modifier_list[j], &modifier_list[j + 1],
                sizeof(EGLuint64KHR) * (size_t)(max_modifiers - j));
      } else {
        j++;
      }
    }

    free(external_only);
    *modifiers = (uint64_t*)modifier_list;
  }

  *n_modifiers = (size_t)max_modifiers;
  return true;
}

int dmabuf_caps_query(const char* render_node, size_t n,
                      const uint32_t* drm_formats, uint64_t** modifiers,
                      size_t* counts) {
  for (size_t i = 0; i < n; i++) {
    modifiers[i] = NULL;
    counts[i] = 0;
  }
  int fd = open(render_node, O_RDWR | O_CLOEXEC);
  if (fd < 0) return -1;
  int result = -1;
  struct gbm_device* gbm = gbm_create_device(fd);
  EGLDisplay display = EGL_NO_DISPLAY;
  if (!gbm) goto done;

  const char* client = eglQueryString(EGL_NO_DISPLAY, EGL_EXTENSIONS);
  PFNEGLGETPLATFORMDISPLAYEXTPROC get_platform_display =
      (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress(
          "eglGetPlatformDisplayEXT");
  if (!has_extension(client, "EGL_KHR_platform_gbm") &&
      !has_extension(client, "EGL_MESA_platform_gbm")) {
    goto done;
  }
  if (!get_platform_display) goto done;
  display = get_platform_display(EGL_PLATFORM_GBM_KHR, gbm, NULL);
  if (display == EGL_NO_DISPLAY || !eglInitialize(display, NULL, NULL)) {
    display = EGL_NO_DISPLAY;
    goto done;
  }

  const char* extensions = eglQueryString(display, EGL_EXTENSIONS);
  Egl egl = {
      .display = display,
      .query_formats = (PFNEGLQUERYDMABUFFORMATSEXTPROC)eglGetProcAddress(
          "eglQueryDmaBufFormatsEXT"),
      .query_modifiers = (PFNEGLQUERYDMABUFMODIFIERSEXTPROC)eglGetProcAddress(
          "eglQueryDmaBufModifiersEXT"),
  };
  bool implicit = has_extension(extensions, "EGL_EXT_image_dma_buf_import");
  if (!has_extension(extensions, "EGL_EXT_image_dma_buf_import_modifiers") ||
      !egl.query_formats || !egl.query_modifiers) {
    goto done;
  }

  EGLint* formats = NULL;
  EGLint n_formats = 0;
  if (!query_dmabuf_formats(&egl, &formats, &n_formats)) goto done;
  for (size_t i = 0; i < n; i++) {
    bool available = false;
    for (EGLint j = 0; j < n_formats; j++) {
      available |= (uint32_t)formats[j] == drm_formats[i];
    }
    if (!available) continue;
    if (!query_dmabuf_modifiers(&egl, (EGLint)drm_formats[i], &modifiers[i],
                                &counts[i])) {
      continue;
    }
    if (implicit) {
      if (!modifiers[i]) modifiers[i] = calloc(1, sizeof(uint64_t));
      if (modifiers[i]) modifiers[i][counts[i]++] = DRM_FORMAT_MOD_INVALID;
    }
  }
  free(formats);
  result = 0;

done:
  if (display != EGL_NO_DISPLAY) eglTerminate(display);
  if (gbm) gbm_device_destroy(gbm);
  close(fd);
  return result;
}
