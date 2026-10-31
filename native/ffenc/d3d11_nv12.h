// A Windows Graphics Capture picture into FFmpeg's D3D11 NV12 frames, on the
// GPU. Windows only; see d3d11_nv12.c.
#ifndef RIFT_D3D11_NV12_H_
#define RIFT_D3D11_NV12_H_

#include <stddef.h>

#include <libavutil/buffer.h>
#include <libavutil/frame.h>

#include "ffenc.h"

typedef struct D3d11Nv12 D3d11Nv12;

// Opens the converter on `device`, an ID3D11Device the caller keeps, for
// pictures `width` by `height`. NULL with why in `error`.
D3d11Nv12* d3d11_nv12_open(void* device, int width, int height, char* error,
                           size_t error_len);

// FFmpeg's frames the converter draws into, for the encoder to open on.
AVBufferRef* d3d11_nv12_frames(D3d11Nv12* path);

// Draws the part `source_width` by `source_height` of `texture` (an
// ID3D11Texture2D on the same device, BGRA) into a new frame, at `place`, the
// rest black; NULL place fills it. 0, AVERROR(EAGAIN) for a passing failure
// worth repeating the last picture over, or another FFmpeg error.
int d3d11_nv12_run(D3d11Nv12* path, void* texture, int source_width,
                   int source_height, const RiftRect* place, AVFrame* frame);

void d3d11_nv12_free(D3d11Nv12** path);

#endif  // RIFT_D3D11_NV12_H_
