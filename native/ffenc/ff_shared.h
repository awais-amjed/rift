// What the library's encoder (ffenc.c) and decoder (ffdec.c) share. Not part
// of the library's interface: nothing here is exported.
#ifndef RIFT_FF_SHARED_H_
#define RIFT_FF_SHARED_H_

#include <stddef.h>

#include <libavutil/buffer.h>

// Writes `what`, and FFmpeg's reason for `err` when it is an error, into
// `error`.
void rift_ff_fail(char* error, size_t error_len, const char* what, int err);

#if defined(__linux__)
#include <ffnvcodec/dynlink_loader.h>

// A VAAPI device's driver, as it names itself; NULL for any other device.
const char* rift_ff_vaapi_vendor(const AVBufferRef* device);

// The CUDA device that is `render_node`'s card, or the first when that cannot
// be told (nvenc_gl.c). CUDA must be initialised.
CUresult rift_ff_cuda_device(const CudaFunctions* cu, const char* render_node,
                             CUdevice* device);
#endif

#endif  // RIFT_FF_SHARED_H_
