// Decodes on a D3D11 device made the way the runner makes its own
// (windows/runner/stream_draw.cpp, MakeDevice), through ffdec's D3D11VA way:
// H264 the library's own encoder made, and VP9 from files the command-line
// ffmpeg made of the same picture. Four coloured quarters go in, and the
// decoder's slice, copied out to the CPU, must hold the same four in NV12, at
// the size sent though H264 codes 1080 lines as 1088. VP8 must fail as a codec
// the GPU cannot decode. Run by native/ffenc/test_ffdec_windows.sh.
//
//   test_ffdec_d3d11 --yuv FILE     writes the picture, yuv420p, for ffmpeg
//   test_ffdec_d3d11 OUT_DIR        decodes, on every GPU in the computer
//
// Exits 2 when no GPU here has a D3D11 video decoder.
#define COBJMACROS
#include "ffdec.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <d3d10.h>
#include <d3d11.h>
#include <dxgi.h>
#include <windows.h>

#define W 1920
#define H 1080
#define PICTURES 30
// Pictures held at once, as the runner may hold them (one waiting, one
// drawn, one on its way): decoding must go on regardless.
#define HELD 3
// FFmpeg's AVERROR(ENOSYS): 40 is ENOSYS on Windows, not 38 as on Linux.
#define NO_GPU_DECODER (-ENOSYS)

static int failures;

#define CHECK(cond, ...)                     \
  do {                                       \
    if (!(cond)) {                           \
      fprintf(stderr, "FAIL: " __VA_ARGS__); \
      fprintf(stderr, "\n");                 \
      failures++;                            \
    }                                        \
  } while (0)

static void log_line(int32_t level, const char* line) {
  (void)level;
  fprintf(stderr, "ffmpeg: %s\n", line);
}

// ── The picture sent ────────────────────────────────────────────────────

// BT.601 in limited range: red, green, blue, white.
static const uint8_t kYuv[4][3] = {
    {81, 90, 240}, {145, 54, 34}, {41, 240, 110}, {235, 128, 128}};

static int quarter_of(int x, int y) { return (y >= H / 2) * 2 + (x >= W / 2); }

static void fill_nv12(uint8_t* nv12) {
  for (int y = 0; y < H; y++) {
    for (int x = 0; x < W; x++) nv12[y * W + x] = kYuv[quarter_of(x, y)][0];
  }
  uint8_t* uv = nv12 + W * H;
  for (int y = 0; y < H / 2; y++) {
    for (int x = 0; x < W / 2; x++) {
      const uint8_t* c = kYuv[quarter_of(x * 2, y * 2)];
      uv[y * W + x * 2] = c[1];
      uv[y * W + x * 2 + 1] = c[2];
    }
  }
}

static int write_yuv(const char* path) {
  FILE* file = fopen(path, "wb");
  if (!file) return 1;
  for (int y = 0; y < H; y++) {
    for (int x = 0; x < W; x++) fputc(kYuv[quarter_of(x, y)][0], file);
  }
  for (int plane = 1; plane <= 2; plane++) {
    for (int y = 0; y < H / 2; y++) {
      for (int x = 0; x < W / 2; x++) {
        fputc(kYuv[quarter_of(x * 2, y * 2)][plane], file);
      }
    }
  }
  return fclose(file) == 0 ? 0 : 1;
}

// ── The device, as the runner makes it ─────────────────────────────────

static ID3D11Device* make_device(IDXGIAdapter1* adapter) {
  const D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_11_1,
                                      D3D_FEATURE_LEVEL_11_0};
  ID3D11Device* device = NULL;
  if (FAILED(D3D11CreateDevice(
          (IDXGIAdapter*)adapter, D3D_DRIVER_TYPE_UNKNOWN, NULL,
          D3D11_CREATE_DEVICE_BGRA_SUPPORT | D3D11_CREATE_DEVICE_VIDEO_SUPPORT,
          levels, 2, D3D11_SDK_VERSION, &device, NULL, NULL))) {
    return NULL;
  }
  ID3D10Multithread* multithread;
  if (SUCCEEDED(ID3D11Device_QueryInterface(device, &IID_ID3D10Multithread,
                                            (void**)&multithread))) {
    ID3D10Multithread_SetMultithreadProtected(multithread, TRUE);
    ID3D10Multithread_Release(multithread);
  }
  return device;
}

static ULONG references(ID3D11Device* device) {
  ID3D11Device_AddRef(device);
  return ID3D11Device_Release(device);
}

// ── A decoded picture, read back ────────────────────────────────────────

// The picture's slice copied out, and each quarter's middle compared.
static void check_colours(ID3D11Device* device, const RiftFfdecPicture* p,
                          const char* what) {
  ID3D11Texture2D* array = p->d3d11_texture;
  D3D11_TEXTURE2D_DESC desc;
  ID3D11Texture2D_GetDesc(array, &desc);
  CHECK(desc.Format == DXGI_FORMAT_NV12, "%s: not NV12 (%d)", what,
        (int)desc.Format);
  // Where the GPU lets the shader read NV12, the runner draws the slice
  // where it lies, so the array must be a shader resource too.
  UINT support = 0;
  ID3D11Device_CheckFormatSupport(device, DXGI_FORMAT_NV12, &support);
  if (support & D3D11_FORMAT_SUPPORT_SHADER_SAMPLE) {
    CHECK(desc.BindFlags & D3D11_BIND_SHADER_RESOURCE,
          "%s: the decoder's array is no shader resource", what);
  }
  CHECK(desc.BindFlags & D3D11_BIND_DECODER, "%s: not the decoder's", what);
  CHECK(p->d3d11_slice >= 0 && (UINT)p->d3d11_slice < desc.ArraySize,
        "%s: slice %d outside an array of %u", what, p->d3d11_slice,
        desc.ArraySize);
  CHECK(desc.Width >= (UINT)p->width && desc.Height >= (UINT)p->height,
        "%s: the array (%ux%u) is smaller than the picture", what, desc.Width,
        desc.Height);
  D3D11_TEXTURE2D_DESC staging_desc = desc;
  staging_desc.ArraySize = 1;
  staging_desc.Usage = D3D11_USAGE_STAGING;
  staging_desc.BindFlags = 0;
  staging_desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
  staging_desc.MiscFlags = 0;
  ID3D11Texture2D* staging;
  if (FAILED(ID3D11Device_CreateTexture2D(device, &staging_desc, NULL,
                                          &staging))) {
    CHECK(0, "%s: no staging texture", what);
    return;
  }
  ID3D11DeviceContext* context;
  ID3D11Device_GetImmediateContext(device, &context);
  ID3D11DeviceContext_CopySubresourceRegion(
      context, (ID3D11Resource*)staging, 0, 0, 0, 0, (ID3D11Resource*)array,
      (UINT)p->d3d11_slice, NULL);
  D3D11_MAPPED_SUBRESOURCE mapped;
  if (FAILED(ID3D11DeviceContext_Map(context, (ID3D11Resource*)staging, 0,
                                     D3D11_MAP_READ, 0, &mapped))) {
    CHECK(0, "%s: the copy did not map", what);
  } else {
    const uint8_t* y_plane = mapped.pData;
    const uint8_t* uv_plane = y_plane + (size_t)mapped.RowPitch * desc.Height;
    for (int q = 0; q < 4; q++) {
      int x = (q & 1) ? W * 3 / 4 : W / 4;
      int y = (q & 2) ? H * 3 / 4 : H / 4;
      int got[3] = {y_plane[(size_t)y * mapped.RowPitch + x],
                    uv_plane[(size_t)(y / 2) * mapped.RowPitch + x / 2 * 2],
                    uv_plane[(size_t)(y / 2) * mapped.RowPitch + x / 2 * 2 + 1]};
      for (int c = 0; c < 3; c++) {
        CHECK(abs(got[c] - kYuv[q][c]) <= 8,
              "%s: quarter %d is %d,%d,%d, not %d,%d,%d", what, q, got[0],
              got[1], got[2], kYuv[q][0], kYuv[q][1], kYuv[q][2]);
        if (abs(got[c] - kYuv[q][c]) > 8) break;
      }
    }
    ID3D11DeviceContext_Unmap(context, (ID3D11Resource*)staging, 0);
  }
  ID3D11DeviceContext_Release(context);
  ID3D11Texture2D_Release(staging);
}

static void check_picture(const RiftFfdecPicture* p, const char* what) {
  CHECK(p->width == W && p->height == H, "%s: size %dx%d", what, p->width,
        p->height);
  CHECK(p->planes == 2 && p->memory == RIFT_FFDEC_IN_D3D11 && p->d3d11_texture,
        "%s: not a D3D11 slice", what);
}

// ── Decoding ────────────────────────────────────────────────────────────

typedef struct Run {
  ID3D11Device* device;
  RiftFfdec* dec;
  RiftFfdecPicture held[HELD];
  int sent, decoded;
  const char* what;
  int32_t matrix, full_range;
} Run;

static int open_run(Run* run, ID3D11Device* device, int32_t codec,
                    const char* what) {
  memset(run, 0, sizeof(*run));
  run->device = device;
  run->what = what;
  run->matrix = -1;
  char error[256] = {0};
  RiftFfdecConfig config = {
      .codec = codec, .api = RIFT_FFDEC_D3D11VA, .d3d11_device = device};
  run->dec = rift_ffdec_open(&config, error, sizeof error);
  CHECK(run->dec != NULL, "%s: the decoder did not open: %s", what, error);
  return run->dec != NULL;
}

// One access unit in, and every picture out kept, the oldest let go once
// HELD are held. The first and last are read back.
static void decode(Run* run, const uint8_t* data, size_t len, int last) {
  int sent = run->sent++;
  int err = rift_ffdec_send(run->dec, data, len, sent * 16667);
  CHECK(err == 0, "%s: unit %d did not decode (%d)", run->what, sent, err);
  RiftFfdecPicture picture;
  int got;
  while ((got = rift_ffdec_receive(run->dec, &picture)) == 1) {
    check_picture(&picture, run->what);
    if (run->decoded == 0) {
      run->matrix = picture.matrix;
      run->full_range = picture.full_range;
    }
    CHECK(picture.matrix == run->matrix && picture.full_range == run->full_range,
          "%s: the colour changed between pictures", run->what);
    if (run->decoded == 0 || last) check_colours(run->device, &picture, run->what);
    RiftFfdecPicture* slot = &run->held[run->decoded % HELD];
    rift_ffdec_release(slot);
    *slot = picture;
    run->decoded++;
  }
  CHECK(got == 0, "%s: receive failed: %d", run->what, got);
  CHECK(run->decoded == run->sent, "%s: %d sent but %d out", run->what,
        run->sent, run->decoded);
}

// The decoder closed with pictures still held, as the runner may hold them,
// then those let go: each must still read and release.
static void close_run(Run* run) {
  rift_ffdec_close(run->dec);
  for (int i = 0; i < HELD; i++) {
    if (run->held[i].held) check_picture(&run->held[i], run->what);
    rift_ffdec_release(&run->held[i]);
    rift_ffdec_release(&run->held[i]);
  }
}

// H264 from the library's own encoder, whichever opens here, from memory.
static int h264(ID3D11Device* device) {
  static const char* encoders[] = {"h264_nvenc", "h264_qsv", "h264_amf"};
  RiftFfenc* enc = NULL;
  const char* name = NULL;
  char error[256] = {0};
  for (int i = 0; i < 3 && !enc; i++) {
    RiftFfencConfig config = {
        .encoder = encoders[i],
        .width = W,
        .height = H,
        .fps = 60,
        .bitrate_bps = 8000000,
        .peak_percent = 100,
        .gop = 600,
        .max_bitrate_bps = 8000000,
    };
    enc = rift_ffenc_open(&config, error, sizeof error);
    name = encoders[i];
  }
  if (!enc) {
    fprintf(stderr, "no H264 encoder opens here: %s\n", error);
    return 0;
  }
  Run run;
  if (!open_run(&run, device, RIFT_FFDEC_H264, "H264")) {
    rift_ffenc_close(enc);
    return 1;
  }
  uint8_t* nv12 = malloc(W * H * 3 / 2);
  fill_nv12(nv12);
  for (int i = 0; i < PICTURES; i++) {
    CHECK(rift_ffenc_send(enc, nv12, i * 16667, i == 0) == 0, "encode %d", i);
    RiftFfencPacket packet;
    while (rift_ffenc_receive(enc, &packet) == 1) {
      decode(&run, packet.data, packet.len, run.sent == PICTURES - 1);
    }
  }
  free(nv12);
  rift_ffenc_close(enc);
  printf("  H264 from %s: %d of %d decoded on %s\n", name, run.decoded,
         PICTURES, rift_ffdec_driver(run.dec));
  CHECK(run.decoded == PICTURES, "H264: %d of %d decoded", run.decoded,
        PICTURES);
  CHECK(run.matrix == RIFT_FFDEC_BT601 && !run.full_range,
        "H264: matrix %d, full range %d, not BT.601 limited", run.matrix,
        run.full_range);
  close_run(&run);
  return 1;
}

// An IVF file's frames: a 32-byte header, then a 12-byte header before each.
static void vp9(ID3D11Device* device, const char* path, int32_t matrix,
                int32_t full_range) {
  FILE* file = fopen(path, "rb");
  if (!file) {
    CHECK(0, "no %s", path);
    return;
  }
  Run run;
  if (!open_run(&run, device, RIFT_FFDEC_VP9, path)) {
    fclose(file);
    return;
  }
  uint8_t header[32];
  CHECK(fread(header, 1, 32, file) == 32 && memcmp(header, "DKIF", 4) == 0,
        "%s is not IVF", path);
  uint32_t frames = header[24] | header[25] << 8 | header[26] << 16 |
                    (uint32_t)header[27] << 24;
  uint8_t frame_header[12];
  while (fread(frame_header, 1, 12, file) == 12) {
    size_t len = frame_header[0] | frame_header[1] << 8 |
                 frame_header[2] << 16 | (size_t)frame_header[3] << 24;
    uint8_t* data = malloc(len);
    if (fread(data, 1, len, file) != len) {
      free(data);
      break;
    }
    decode(&run, data, len, (uint32_t)run.sent + 1 == frames);
    free(data);
  }
  fclose(file);
  printf("  VP9 %s: %d decoded, matrix %d, full range %d\n", path, run.decoded,
         run.matrix, run.full_range);
  CHECK(run.decoded >= 4, "%s: only %d decoded", path, run.decoded);
  CHECK(run.matrix == matrix && run.full_range == full_range,
        "%s: matrix %d and full range %d, not %d and %d", path, run.matrix,
        run.full_range, matrix, full_range);
  close_run(&run);
}

static void vp8_fails(ID3D11Device* device) {
  char error[256] = {0};
  RiftFfdecConfig config = {
      .codec = RIFT_FFDEC_VP8, .api = RIFT_FFDEC_D3D11VA, .d3d11_device = device};
  RiftFfdec* dec = rift_ffdec_open(&config, error, sizeof error);
  CHECK(dec != NULL, "VP8: did not open, so would not fail by name: %s", error);
  if (!dec) return;
  const uint8_t unit[16] = {0};
  int err = rift_ffdec_send(dec, unit, sizeof unit, 0);
  CHECK(err == NO_GPU_DECODER, "VP8: sent answered %d, not ENOSYS", err);
  rift_ffdec_close(dec);
}

static void refused(ID3D11Device* device) {
  char error[256] = {0};
  RiftFfdecConfig none = {.codec = RIFT_FFDEC_H264, .api = RIFT_FFDEC_D3D11VA};
  CHECK(rift_ffdec_open(&none, error, sizeof error) == NULL,
        "D3D11VA opened with no device");
  RiftFfdecConfig bad = {
      .codec = 99, .api = RIFT_FFDEC_D3D11VA, .d3d11_device = device};
  CHECK(rift_ffdec_open(&bad, error, sizeof error) == NULL,
        "a codec that is not one opened");
}

int main(int argc, char** argv) {
  if (argc == 3 && strcmp(argv[1], "--yuv") == 0) return write_yuv(argv[2]);
  if (argc != 2) {
    fprintf(stderr, "usage: test_ffdec_d3d11 OUT_DIR | --yuv FILE\n");
    return 1;
  }
  const char* out = argv[1];
  rift_ffenc_set_log(log_line, 16);
  char vp9_601[MAX_PATH], vp9_709[MAX_PATH];
  snprintf(vp9_601, sizeof vp9_601, "%s/quarters_vp9.ivf", out);
  snprintf(vp9_709, sizeof vp9_709, "%s/quarters_vp9_709_full.ivf", out);

  IDXGIFactory1* factory;
  if (FAILED(CreateDXGIFactory1(&IID_IDXGIFactory1, (void**)&factory))) {
    fprintf(stderr, "no DXGI factory\n");
    return 1;
  }
  int tried = 0;
  IDXGIAdapter1* adapter;
  for (UINT i = 0; IDXGIFactory1_EnumAdapters1(factory, i, &adapter) == S_OK; i++) {
    DXGI_ADAPTER_DESC1 desc;
    IDXGIAdapter1_GetDesc1(adapter, &desc);
    ID3D11Device* device = (desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE)
                               ? NULL
                               : make_device(adapter);
    IDXGIAdapter1_Release(adapter);
    if (!device) continue;
    UINT support = 0;
    ID3D11Device_CheckFormatSupport(device, DXGI_FORMAT_NV12, &support);
    printf("%ls: NV12 %s shader views of decoder surfaces\n", desc.Description,
           (support & D3D11_FORMAT_SUPPORT_SHADER_SAMPLE) ? "takes" : "takes no");
    ULONG before = references(device);
    tried++;
    refused(device);
    h264(device);
    vp9(device, vp9_601, RIFT_FFDEC_BT601, 0);
    vp9(device, vp9_709, RIFT_FFDEC_BT709, 1);
    vp8_fails(device);
    CHECK(references(device) == before,
          "%ls: the decoders kept %lu references to the device",
          desc.Description, references(device) - before);
    ID3D11Device_Release(device);
  }
  IDXGIFactory1_Release(factory);
  if (!tried) {
    fprintf(stderr, "no GPU here decodes through D3D11\n");
    return 2;
  }
  if (failures) {
    fprintf(stderr, "%d failures\n", failures);
    return 1;
  }
  printf("ok: decoded on D3D11, on every GPU here\n");
  return 0;
}
