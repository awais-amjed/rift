#include "nvenc_gl_geometry.h"

RiftRect nvenc_gl_plane_rect(const RiftRect* place, int out_w, int out_h,
                             int plane) {
  int divide = plane == 0 ? 1 : 2;
  if (!place) {
    RiftRect whole = {0, 0, (out_w + divide - 1) / divide,
                      (out_h + divide - 1) / divide};
    return whole;
  }
  int left = place->x / divide;
  int top = place->y / divide;
  int right = (place->x + place->width + divide - 1) / divide;
  int bottom = (place->y + place->height + divide - 1) / divide;
  RiftRect rect = {left, top, right - left, bottom - top};
  return rect;
}

void nvenc_gl_source_uv(const RiftDmabuf* buf, float uv[4][2]) {
  // Each corner of the output, for each SPA_META_TRANSFORMATION_*: which
  // corner of the buffer ends up there once turn_of's turn has been made.
  static const float corners[8][4][2] = {
      {{0, 0}, {1, 0}, {0, 1}, {1, 1}},  // none
      {{0, 1}, {0, 0}, {1, 1}, {1, 0}},  // clock
      {{1, 1}, {0, 1}, {1, 0}, {0, 0}},  // reversal
      {{1, 0}, {1, 1}, {0, 0}, {0, 1}},  // cclock
      {{1, 0}, {0, 0}, {1, 1}, {0, 1}},  // hflip
      {{0, 0}, {0, 1}, {1, 0}, {1, 1}},  // cclock_flip
      {{0, 1}, {1, 1}, {0, 0}, {1, 0}},  // vflip
      {{1, 1}, {1, 0}, {0, 1}, {0, 0}},  // clock_flip
  };
  int transform =
      buf->transform >= 0 && buf->transform < 8 ? buf->transform : 0;
  int cropped = buf->crop_width > 0 && buf->crop_height > 0;
  float left = cropped ? (float)buf->crop_x / (float)buf->width : 0.0f;
  float top = cropped ? (float)buf->crop_y / (float)buf->height : 0.0f;
  float across = cropped ? (float)buf->crop_width / (float)buf->width : 1.0f;
  float down = cropped ? (float)buf->crop_height / (float)buf->height : 1.0f;
  for (int corner = 0; corner < 4; corner++) {
    uv[corner][0] = left + corners[transform][corner][0] * across;
    uv[corner][1] = top + corners[transform][corner][1] * down;
  }
}

int nvenc_gl_scales_far(const RiftDmabuf* buf, int place_w, int place_h) {
  int cropped = buf->crop_width > 0 && buf->crop_height > 0;
  int source_w = cropped ? buf->crop_width : buf->width;
  int source_h = cropped ? buf->crop_height : buf->height;
  if (buf->transform & 1) {
    int swapped = source_w;
    source_w = source_h;
    source_h = swapped;
  }
  return source_w > 2 * place_w || source_h > 2 * place_h;
}

void nvenc_gl_spread(const float uv[4][2], int width, int height, int spread,
                     float offsets[2][2]) {
  for (int axis = 0; axis < 2; axis++) {
    offsets[0][axis] = spread ? (uv[1][axis] - uv[0][axis]) / (float)width / 4 : 0;
    offsets[1][axis] = spread ? (uv[2][axis] - uv[0][axis]) / (float)height / 4 : 0;
  }
}
