// Between pipewire.c and dmabuf_caps.c: which DMA-BUF modifiers the GPU
// can read, inside the library only.
#ifndef RIFT_FFENC_DMABUF_CAPS_H_
#define RIFT_FFENC_DMABUF_CAPS_H_

#include <stddef.h>
#include <stdint.h>

// For each of the `n` formats, the modifiers EGL can import it with on
// `render_node`: external-only ones left out unless `include_external`, and
// DRM_FORMAT_MOD_INVALID last when EGL imports a buffer without one. Each `modifiers[i]` is
// malloc'd (NULL with none), for the caller to free. -1 when EGL cannot say,
// with every count 0 and nothing allocated.
int dmabuf_caps_query(const char* render_node, size_t n,
                      const uint32_t* drm_formats, uint64_t** modifiers,
                      size_t* counts, int include_external);

#endif  // RIFT_FFENC_DMABUF_CAPS_H_
