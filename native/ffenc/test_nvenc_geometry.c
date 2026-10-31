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

// A picture's corners, top-left, top-right, bottom-left and bottom-right, each
// as where in the buffer it came from.
typedef struct Grid {
  float at[4][2];
} Grid;

static const Grid UNTURNED = {{{0, 0}, {1, 0}, {0, 1}, {1, 1}}};

static Grid arranged(Grid in, int tl, int tr, int bl, int br) {
  Grid out;
  const int from[4] = {tl, tr, bl, br};
  for (int corner = 0; corner < 4; corner++) {
    out.at[corner][0] = in.at[from[corner]][0];
    out.at[corner][1] = in.at[from[corner]][1];
  }
  return out;
}

// What FFmpeg's transpose directions do to a picture, on its own terms.
static Grid clockwise(Grid g) { return arranged(g, 2, 0, 3, 1); }
static Grid hflip(Grid g) { return arranged(g, 1, 0, 3, 2); }
static Grid vflip(Grid g) { return arranged(g, 2, 3, 0, 1); }

// For each transform, the direction dmabuf.c's turn_of names, worked out by
// turning a labelled grid, so a wrong row of the code's table cannot pass by
// being copied here.
static void turns(void) {
  Grid clock = clockwise(UNTURNED);
  Grid reversal = clockwise(clock);
  Grid cclock = clockwise(reversal);
  const Grid expected[8] = {
      UNTURNED,
      clock,
      reversal,
      cclock,
      hflip(UNTURNED),
      vflip(cclock),  // cclock_flip
      vflip(UNTURNED),
      vflip(clock),  // clock_flip
  };
  for (int transform = 0; transform < 8; transform++) {
    RiftDmabuf buf = {.width = 1000, .height = 500, .transform = transform};
    float uv[4][2];
    nvenc_gl_source_uv(&buf, uv);
    for (int corner = 0; corner < 4; corner++) {
      for (int axis = 0; axis < 2; axis++) {
        assert(fabsf(uv[corner][axis] - expected[transform].at[corner][axis]) < 1e-5f);
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

static void far_scales(void) {
  RiftDmabuf four_k = {.width = 3840, .height = 2160};
  // 2:1 exactly, the usual 4K share at 1080p, stays at one sample.
  assert(!nvenc_gl_scales_far(&four_k, 1920, 1080));
  assert(nvenc_gl_scales_far(&four_k, 1280, 720));

  // Turned, a tall place is the same scale, and a wide one is not.
  RiftDmabuf turned = {.width = 3840, .height = 2160, .transform = 1};
  assert(!nvenc_gl_scales_far(&turned, 1080, 1920));
  assert(nvenc_gl_scales_far(&turned, 1920, 1080));

  // The crop is what is scaled.
  RiftDmabuf cropped = {.width = 3840,
                        .height = 2160,
                        .crop_width = 1280,
                        .crop_height = 720};
  assert(!nvenc_gl_scales_far(&cropped, 1280, 720));

  float uv[4][2] = {{0, 0}, {1, 0}, {0, 1}, {1, 1}};
  float offsets[2][2];
  nvenc_gl_spread(uv, 100, 50, 1, offsets);
  assert(fabsf(offsets[0][0] - 0.0025f) < 1e-6f && offsets[0][1] == 0);
  assert(offsets[1][0] == 0 && fabsf(offsets[1][1] - 0.005f) < 1e-6f);
  nvenc_gl_spread(uv, 100, 50, 0, offsets);
  assert(offsets[0][0] == 0 && offsets[1][1] == 0);
}

int main(void) {
  plane_rects();
  far_scales();
  turns();
  crop();
  puts("nvenc geometry: ok");
  return 0;
}
