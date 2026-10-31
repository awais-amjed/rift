// The arithmetic of the GL path (nvenc_gl.c): where a picture lands in the
// encoder's planes, and which part of the buffer each corner shows. No GL or
// FFmpeg here, so test_nvenc_geometry.c runs without a GPU.
#ifndef RIFT_NVENC_GL_GEOMETRY_H_
#define RIFT_NVENC_GL_GEOMETRY_H_

#include "ffenc.h"

// The rectangle `place` covers in plane 0 (Y) or 1 (UV, half size), rounded
// outward. NULL place fills the plane.
RiftRect nvenc_gl_plane_rect(const RiftRect* place, int out_w, int out_h,
                             int plane);

// Texture coordinates of the output's top-left, top-right, bottom-left and
// bottom-right, with the crop applied and the turn undone, the way dmabuf.c's
// turn_of undoes it on VAAPI.
void nvenc_gl_source_uv(const RiftDmabuf* buf, float uv[4][2]);

// Whether the buffer, cropped and turned, is more than twice the place it lands
// in, either way.
int nvenc_gl_scales_far(const RiftDmabuf* buf, int place_w, int place_h);

// A quarter of an output pixel across and down in texture coordinates, for the
// four samples of a far scale; zeros for the one sample otherwise.
void nvenc_gl_spread(const float uv[4][2], int width, int height, int spread,
                     float offsets[2][2]);

#endif  // RIFT_NVENC_GL_GEOMETRY_H_
