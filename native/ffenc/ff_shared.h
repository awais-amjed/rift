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
// A VAAPI device's driver, as it names itself; NULL for any other device.
const char* rift_ff_vaapi_vendor(const AVBufferRef* device);
#endif

#endif  // RIFT_FF_SHARED_H_
