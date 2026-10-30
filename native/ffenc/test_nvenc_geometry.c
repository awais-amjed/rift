// The arithmetic of the GL path (nvenc_gl_geometry.c), which needs no GPU.
#include <assert.h>
#include <math.h>
#include <stdio.h>

#include "nvenc_gl_geometry.h"

static void same_rect(RiftRect got, int x, int y, int width, int height) {
  assert(got.x == x && got.y == y && got.width == width && got.height == height);
}

static void plane_rects(void) {
  RiftRect bars = {0, 140, 1920, 800};
  same_rect(nvenc_gl_plane_rect(&bars, 1920, 1080, 0), 0, 140, 1920, 800);
  same_rect(nvenc_gl_plane_rect(&bars, 1920, 1080, 1), 0, 70, 960, 400);

  RiftRect odd = {1, 1, 101, 51};
  same_rect(nvenc_gl_plane_rect(&odd, 1920, 1080, 1), 0, 0, 51, 26);

  same_rect(nvenc_gl_plane_rect(NULL, 1920, 1080, 0), 0, 0, 1920, 1080);
  same_rect(nvenc_gl_plane_rect(NULL, 1920, 1080, 1), 0, 0, 960, 540);
}

// The output's top-left, top-right, bottom-left and bottom-right, for each
// way dmabuf.c's turn_of turns the buffer: FFmpeg's transpose directions.
static void turns(void) {
  static const float expected[8][4][2] = {
      {{0, 0}, {1, 0}, {0, 1}, {1, 1}},  // none
      {{0, 1}, {0, 0}, {1, 1}, {1, 0}},  // clock
      {{1, 1}, {0, 1}, {1, 0}, {0, 0}},  // reversal
      {{1, 0}, {1, 1}, {0, 0}, {0, 1}},  // cclock
      {{1, 0}, {0, 0}, {1, 1}, {0, 1}},  // hflip
      {{0, 0}, {0, 1}, {1, 0}, {1, 1}},  // cclock_flip
      {{0, 1}, {1, 1}, {0, 0}, {1, 0}},  // vflip
      {{1, 1}, {1, 0}, {0, 1}, {0, 0}},  // clock_flip
  };
  for (int transform = 0; transform < 8; transform++) {
    RiftDmabuf buf = {.width = 1000, .height = 500, .transform = transform};
    float uv[4][2];
    nvenc_gl_source_uv(&buf, uv);
    for (int corner = 0; corner < 4; corner++) {
      for (int axis = 0; axis < 2; axis++) {
        assert(fabsf(uv[corner][axis] - expected[transform][corner][axis]) < 1e-5f);
      }
    }
  }
}

static void crop(void) {
  RiftDmabuf buf = {.width = 1000,
                    .height = 500,
                    .crop_x = 100,
                    .crop_y = 50,
                    .crop_width = 500,
                    .crop_height = 250};
  float uv[4][2];
  nvenc_gl_source_uv(&buf, uv);
  assert(fabsf(uv[0][0] - 0.1f) < 1e-5f && fabsf(uv[0][1] - 0.1f) < 1e-5f);
  assert(fabsf(uv[3][0] - 0.6f) < 1e-5f && fabsf(uv[3][1] - 0.6f) < 1e-5f);

  // A turned crop still samples only inside the crop.
  buf.transform = 1;
  nvenc_gl_source_uv(&buf, uv);
  assert(fabsf(uv[0][0] - 0.1f) < 1e-5f && fabsf(uv[0][1] - 0.6f) < 1e-5f);
}

int main(void) {
  plane_rects();
  turns();
  crop();
  puts("nvenc geometry: ok");
  return 0;
}
