// Between ffenc.c and dmabuf.c: a DMA-BUF made into an NV12 picture on
// VAAPI, inside the library only.
#ifndef RIFT_FFENC_DMABUF_H_
#define RIFT_FFENC_DMABUF_H_

#include <libavutil/buffer.h>
#include <libavutil/frame.h>

#include "ffenc.h"

typedef struct DmabufPath DmabufPath;

// A path onto `vaapi`, the encoder's device, opened on `render_node`.
DmabufPath* dmabuf_path_alloc(AVBufferRef* vaapi, const char* render_node);

// Maps `buf` into VAAPI, then crops, turns, scales and places it into an
// `out_w` x `out_h` NV12 frame, written into `out` once the GPU has finished
// with the buffer. 0, RIFT_FFENC_IMPORT_FAILED, or a negative FFmpeg error.
int dmabuf_path_run(DmabufPath* path, const RiftDmabuf* buf,
                    const RiftRect* place, int out_w, int out_h,
                    int64_t timestamp_us, AVFrame* out);

void dmabuf_path_free(DmabufPath** path);

#endif  // RIFT_FFENC_DMABUF_H_
