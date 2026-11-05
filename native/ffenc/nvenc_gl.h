// A Wayland share's DMA-BUF into NVENC with the picture never on the CPU, for a
// screen NVIDIA's card draws: imported into EGL, drawn into two GL textures as
// NV12, and copied by CUDA into the frame h264_nvenc takes. Inside the library
// only (ffenc.c).
#ifndef RIFT_NVENC_GL_H_
#define RIFT_NVENC_GL_H_

#include <libavutil/buffer.h>
#include <libavutil/frame.h>
#include <stddef.h>

#include "ffenc.h"

typedef struct NvencGl NvencGl;

// EGL display and surfaceless GLES 3 context on `render_node`, the CUDA context
// on the same card, FFmpeg's CUDA device on that context, an NV12 CUDA pool of
// width x height, and the textures registered. Makes the context current on the
// calling thread. NULL with why in `error`.
NvencGl* nvenc_gl_open(const char* render_node, int width, int height,
                       char* error, size_t error_len);

// The CUDA pool the encoder must be opened on.
AVBufferRef* nvenc_gl_frames(NvencGl* gl);

// Makes the context current if it is not, imports `buf`, draws, maps, copies,
// syncs, unmaps. Returns with `out` holding a frame from the pool and the buffer
// no longer needed. 0, RIFT_FFENC_IMPORT_FAILED for a format and modifier that
// have not imported on this path, AVERROR(EAGAIN) for one that has and failed
// this time, when the caller sends the last picture again, or a negative FFmpeg
// error.
int nvenc_gl_run(NvencGl* gl, const RiftDmabuf* buf, const RiftRect* place,
                 AVFrame* out);

// After the encoder and every frame from the pool are gone. On the thread that
// runs it: a context current on another thread cannot be made current here.
void nvenc_gl_free(NvencGl** gl);

#endif  // RIFT_NVENC_GL_H_
