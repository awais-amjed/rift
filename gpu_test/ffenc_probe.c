// Encodes synthetic pictures through Rift's FFmpeg encoder library
// (native/ffenc) and writes the H264 to a file, for check_h264.py and ffprobe
// to read: whether each keyframe stays readable to LiveKit's encryption, and
// the colour the stream says it is in. Lives on the gpu-encoding branch only.
//
//   ffenc_probe LIBRARY ENCODER DEVICE OUT.h264 [WIDTH HEIGHT FRAMES KEY_EVERY]
//
// DEVICE is a VAAPI render node on Linux (/dev/dri/renderD128) and "" on
// Windows. A keyframe is asked for on the first picture and then every
// KEY_EVERY pictures (default 1920x1080, 120 pictures, every 20).
//
// Linux:   cc -O1 -I native/ffenc gpu_test/ffenc_probe.c -o ffenc_probe -ldl
// Windows: gcc -O1 -I native/ffenc gpu_test/ffenc_probe.c -o ffenc_probe.exe
//          (MSYS2 UCRT64)
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ffenc.h"

#ifdef _WIN32
#include <windows.h>
static void* open_library(const char* path) { return (void*)LoadLibraryA(path); }
static void* symbol(void* lib, const char* name) {
  return (void*)GetProcAddress((HMODULE)lib, name);
}
#else
#include <dlfcn.h>
static void* open_library(const char* path) { return dlopen(path, RTLD_NOW); }
static void* symbol(void* lib, const char* name) { return dlsym(lib, name); }
#endif

int main(int argc, char** argv) {
  if (argc < 5) {
    fprintf(stderr,
            "ffenc_probe LIBRARY ENCODER DEVICE OUT.h264 "
            "[WIDTH HEIGHT FRAMES KEY_EVERY]\n");
    return 2;
  }
  int w = argc > 5 ? atoi(argv[5]) : 1920;
  int h = argc > 6 ? atoi(argv[6]) : 1080;
  int count = argc > 7 ? atoi(argv[7]) : 120;
  int every = argc > 8 ? atoi(argv[8]) : 20;
  void* lib = open_library(argv[1]);
  if (!lib) {
    fprintf(stderr, "could not load %s\n", argv[1]);
    return 1;
  }
  RiftFfenc* (*open)(const RiftFfencConfig*, char*, size_t) =
      symbol(lib, "rift_ffenc_open");
  int32_t (*send)(RiftFfenc*, const uint8_t*, int64_t, int32_t) =
      symbol(lib, "rift_ffenc_send");
  int32_t (*receive)(RiftFfenc*, RiftFfencPacket*) =
      symbol(lib, "rift_ffenc_receive");
  void (*close)(RiftFfenc*) = symbol(lib, "rift_ffenc_close");
  int32_t (*abi)(void) = symbol(lib, "rift_ffenc_abi");
  if (!open || !send || !receive || !close || !abi) {
    fprintf(stderr, "not Rift's encoder library\n");
    return 1;
  }
  if (abi() != RIFT_FFENC_ABI) {
    fprintf(stderr, "library ABI %d, this probe %d\n", abi(), RIFT_FFENC_ABI);
    return 1;
  }
  RiftFfencConfig config = {argv[2], argv[3][0] ? argv[3] : NULL, w, h, 60,
                            8000000, 100, 3600, 8000000};
  char error[512] = {0};
  RiftFfenc* enc = open(&config, error, sizeof error);
  if (!enc) {
    fprintf(stderr, "open %s: %s\n", argv[2], error);
    return 1;
  }
  FILE* out = fopen(argv[4], "wb");
  if (!out) {
    fprintf(stderr, "cannot write %s\n", argv[4]);
    return 1;
  }
  uint8_t* nv12 = malloc((size_t)w * h * 3 / 2);
  int keyframes = 0;
  for (int f = 0; f < count; f++) {
    // A moving ramp with flat colour, different every picture.
    for (int y = 0; y < h; y++)
      for (int x = 0; x < w; x++) nv12[(size_t)y * w + x] = (uint8_t)(x + y + f * 8);
    memset(nv12 + (size_t)w * h, f & 1 ? 200 : 60, (size_t)w * h / 2);
    int key = f == 0 || (every > 0 && f % every == 0);
    if (send(enc, nv12, (int64_t)f * 16667, key) < 0) {
      fprintf(stderr, "send failed at picture %d\n", f);
      return 1;
    }
    RiftFfencPacket packet;
    int got;
    while ((got = receive(enc, &packet)) > 0) {
      keyframes += packet.keyframe != 0;
      fwrite(packet.data, 1, packet.len, out);
    }
    if (got < 0) {
      fprintf(stderr, "receive failed at picture %d\n", f);
      return 1;
    }
  }
  fclose(out);
  close(enc);
  printf("%s: %d pictures, %d keyframes, written to %s\n", argv[2], count,
         keyframes, argv[4]);
  return 0;
}
