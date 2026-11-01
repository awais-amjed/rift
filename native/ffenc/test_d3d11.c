// A share's Windows Graphics Capture picture through ffenc's D3D11 input
// (d3d11_nv12.c), from a BGRA texture on the encoder's own adapter, as
// capture_wgc.rs gives it. Writes each stream to the folder it is given, for
// check_d3d11.py to decode, and prints what a picture cost. Run by
// native/ffenc/test_windows.sh.
//
//   test_d3d11 OUT_DIR ENCODER [--exit-open]
//
// ENCODER is FFmpeg's name (h264_nvenc, h264_qsv, h264_amf). Exits 2 when it
// does not open here, or its maker's GPU is not in this computer.
// `--exit-open` returns from main with an encoder open, which must end at once.
#define COBJMACROS
#include "ffenc.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <d3d10.h>
#include <d3d11.h>
#include <dxgi.h>
#include <windows.h>

#define WIDTH 1920
#define HEIGHT 1080

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
  fprintf(stderr, "ffmpeg: %s", line);
}

static double now_ms(void) {
  LARGE_INTEGER count, frequency;
  QueryPerformanceCounter(&count);
  QueryPerformanceFrequency(&frequency);
  return (double)count.QuadPart * 1000.0 / (double)frequency.QuadPart;
}

// ── The device, on the encoder's maker's GPU ──────────────────────────────

static const char* encoder;
static const char* out_dir;
static ID3D11Device* device;
static ID3D11DeviceContext* context;

static UINT vendor_of(const char* name) {
  if (strcmp(name, "h264_nvenc") == 0) return 0x10de;
  if (strcmp(name, "h264_qsv") == 0) return 0x8086;
  if (strcmp(name, "h264_amf") == 0) return 0x1002;
  return 0;
}

// As capture_wgc.rs opens it: by vendor, BGRA, and protected for two threads.
static int open_device(UINT vendor) {
  IDXGIFactory1* factory;
  if (FAILED(CreateDXGIFactory1(&IID_IDXGIFactory1, (void**)&factory))) return 0;
  IDXGIAdapter1* adapter;
  int opened = 0;
  for (UINT i = 0; !opened && IDXGIFactory1_EnumAdapters1(factory, i, &adapter) == S_OK; i++) {
    DXGI_ADAPTER_DESC1 desc;
    IDXGIAdapter1_GetDesc1(adapter, &desc);
    if (desc.VendorId == vendor && !(desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE)) {
      opened = SUCCEEDED(D3D11CreateDevice(
          (IDXGIAdapter*)adapter, D3D_DRIVER_TYPE_UNKNOWN, NULL,
          D3D11_CREATE_DEVICE_BGRA_SUPPORT, NULL, 0, D3D11_SDK_VERSION, &device,
          NULL, &context));
    }
    IDXGIAdapter1_Release(adapter);
  }
  IDXGIFactory1_Release(factory);
  if (!opened) return 0;
  ID3D10Multithread* multithread;
  if (SUCCEEDED(ID3D11Device_QueryInterface(device, &IID_ID3D10Multithread,
                                            (void**)&multithread))) {
    ID3D10Multithread_SetMultithreadProtected(multithread, TRUE);
    ID3D10Multithread_Release(multithread);
  }
  return 1;
}

// ── Pictures ──────────────────────────────────────────────────────────────

typedef struct Picture {
  ID3D11Texture2D* texture;
  uint32_t* pixels;  // BGRA, what the texture was last given
  int width, height;
} Picture;

static Picture make_picture(int width, int height) {
  Picture p = {.width = width, .height = height};
  p.pixels = calloc((size_t)width * height, 4);
  D3D11_TEXTURE2D_DESC desc = {
      .Width = width,
      .Height = height,
      .MipLevels = 1,
      .ArraySize = 1,
      .Format = DXGI_FORMAT_B8G8R8A8_UNORM,
      .SampleDesc = {1, 0},
      .Usage = D3D11_USAGE_DEFAULT,
      .BindFlags = D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_RENDER_TARGET,
  };
  if (FAILED(ID3D11Device_CreateTexture2D(device, &desc, NULL, &p.texture))) {
    fprintf(stderr, "no %dx%d BGRA texture\n", width, height);
    exit(1);
  }
  return p;
}

static void fill(Picture* p, int x, int y, int w, int h, uint32_t bgra) {
  for (int row = y; row < y + h; row++) {
    for (int col = x; col < x + w; col++) p->pixels[row * p->width + col] = bgra;
  }
}

static void upload(Picture* p) {
  ID3D11DeviceContext_UpdateSubresource(context, (ID3D11Resource*)p->texture, 0,
                                        NULL, p->pixels, p->width * 4, 0);
}

static void free_picture(Picture* p) {
  ID3D11Texture2D_Release(p->texture);
  free(p->pixels);
}

#define RED 0xffff0000u
#define GREEN 0xff00ff00u
#define BLUE 0xff0000ffu
#define GRAY 0xff7f7f7fu
#define DARK 0xff282828u
#define WHITE 0xffffffffu

// Red, green, blue and gray quarters, red top left (check_d3d11.py).
static void quarters(Picture* p) {
  int w = p->width / 2, h = p->height / 2;
  fill(p, 0, 0, w, h, RED);
  fill(p, w, 0, p->width - w, h, GREEN);
  fill(p, 0, h, w, p->height - h, BLUE);
  fill(p, w, h, p->width - w, p->height - h, GRAY);
  upload(p);
}

// ── The encoder, and what it writes ───────────────────────────────────────

static RiftFfenc* open_encoder(void) {
  RiftFfencConfig config = {
      .encoder = encoder,
      .width = WIDTH,
      .height = HEIGHT,
      .fps = 60,
      .bitrate_bps = 15000000,
      .peak_percent = 100,
      .gop = 600,
      .max_bitrate_bps = 30000000,
      .d3d11_device = device,
  };
  char error[256] = "";
  RiftFfenc* enc = rift_ffenc_open(&config, error, sizeof(error));
  if (!enc) fprintf(stderr, "%s does not open: %s\n", encoder, error);
  return enc;
}

typedef struct Stream {
  FILE* file;
  int packets;
} Stream;

static Stream open_stream(const char* name) {
  char path[512];
  snprintf(path, sizeof(path), "%s/%s-%s.h264", out_dir, encoder, name);
  Stream s = {.file = fopen(path, "wb")};
  if (!s.file) {
    fprintf(stderr, "cannot write %s\n", path);
    exit(1);
  }
  return s;
}

static void drain(RiftFfenc* enc, Stream* stream) {
  RiftFfencPacket packet;
  int got;
  while ((got = rift_ffenc_receive(enc, &packet)) == 1) {
    fwrite(packet.data, 1, packet.len, stream->file);
    stream->packets++;
  }
  CHECK(got == 0, "receive said %d", got);
}

static double send_picture(RiftFfenc* enc, Picture* p, const RiftRect* place, int number,
                   Stream* stream) {
  double start = now_ms();
  int err = rift_ffenc_send_d3d11(enc, p->texture, p->width, p->height, place,
                                  (int64_t)number * 16667, number == 0);
  double took = now_ms() - start;
  CHECK(err == 0, "send_d3d11 said %d at picture %d", err, number);
  drain(enc, stream);
  return took;
}

// ── The cases ─────────────────────────────────────────────────────────────

// Quarters, then repeats of the last with a keyframe asked for in the middle:
// every picture decodes to the same quarters.
static void quarters_and_repeats(RiftFfenc* enc) {
  Picture p = make_picture(WIDTH, HEIGHT);
  quarters(&p);
  Stream stream = open_stream("quarters");
  int i = 0;
  for (; i < 60; i++) send_picture(enc, &p, NULL, i, &stream);
  for (; i < 90; i++) {
    int err = rift_ffenc_repeat(enc, (int64_t)i * 16667, i == 75);
    CHECK(err == 0, "repeat said %d", err);
    drain(enc, &stream);
  }
  fclose(stream.file);
  CHECK(stream.packets == 90, "quarters: %d packets", stream.packets);
  free_picture(&p);
}

// A white bar 40 wide that moves 8 to the right each picture: each decoded
// picture's bar is where its number puts it, so no picture is late or torn.
static void moving_bar(RiftFfenc* enc) {
  Picture p = make_picture(WIDTH, HEIGHT);
  Stream stream = open_stream("bar");
  double total = 0, longest = 0;
  for (int i = 0; i < 300; i++) {
    fill(&p, 0, 0, WIDTH, HEIGHT, DARK);
    fill(&p, (i * 8) % (WIDTH - 40), 0, 40, HEIGHT, WHITE);
    upload(&p);
    double took = send_picture(enc, &p, NULL, i, &stream);
    total += took;
    if (took > longest) longest = took;
  }
  fclose(stream.file);
  CHECK(stream.packets == 300, "bar: %d packets", stream.packets);
  printf("%s: send_d3d11 %.3f ms a picture on average, longest %.3f\n", encoder,
         total / 300, longest);
  free_picture(&p);
}

// A 1000x800 blue picture letterboxed into 1920x1080: black either side.
static void letterboxed(RiftFfenc* enc) {
  Picture p = make_picture(1000, 800);
  fill(&p, 0, 0, 1000, 800, BLUE);
  upload(&p);
  RiftRect place = {285, 0, 1350, 1080};
  Stream stream = open_stream("letterbox");
  for (int i = 0; i < 30; i++) send_picture(enc, &p, &place, i, &stream);
  fclose(stream.file);
  CHECK(stream.packets == 30, "letterbox: %d packets", stream.packets);
  free_picture(&p);
}

// Pictures from memory on the same encoder, between GPU ones, as when a
// share hands over to libwebrtc's capturer and back.
static void memory_between(RiftFfenc* enc) {
  Picture p = make_picture(WIDTH, HEIGHT);
  quarters(&p);
  size_t size = (size_t)WIDTH * HEIGHT * 3 / 2;
  uint8_t* nv12 = malloc(size);
  memset(nv12, 200, (size_t)WIDTH * HEIGHT);
  for (size_t i = (size_t)WIDTH * HEIGHT; i + 1 < size; i += 2) {
    nv12[i] = 100;
    nv12[i + 1] = 150;
  }
  Stream stream = open_stream("memory");
  int i = 0;
  for (; i < 30; i++) send_picture(enc, &p, NULL, i, &stream);
  for (; i < 60; i++) {
    int err = rift_ffenc_send(enc, nv12, (int64_t)i * 16667, 0);
    CHECK(err == 0, "send said %d", err);
    drain(enc, &stream);
  }
  for (; i < 90; i++) send_picture(enc, &p, NULL, i, &stream);
  fclose(stream.file);
  CHECK(stream.packets == 90, "memory: %d packets", stream.packets);
  free(nv12);
  free_picture(&p);
}

int main(int argc, char** argv) {
  if (argc < 3) {
    fprintf(stderr, "usage: test_d3d11 OUT_DIR ENCODER [--exit-open]\n");
    return 1;
  }
  out_dir = argv[1];
  encoder = argv[2];
  int exit_open = argc > 3 && strcmp(argv[3], "--exit-open") == 0;
  rift_ffenc_set_log(log_line, 24 /* AV_LOG_WARNING */);
  UINT vendor = vendor_of(encoder);
  if (!vendor || !open_device(vendor)) {
    fprintf(stderr, "%s: no GPU of its maker here\n", encoder);
    return 2;
  }
  RiftFfenc* enc = open_encoder();
  if (!enc) return 2;
  if (!rift_ffenc_takes_d3d11(enc)) {
    fprintf(stderr, "FAIL: %s opened but takes no D3D11 picture\n", encoder);
    return 1;
  }
  if (exit_open) {
    Picture p = make_picture(WIDTH, HEIGHT);
    quarters(&p);
    Stream stream = open_stream("exit");
    for (int i = 0; i < 10; i++) send_picture(enc, &p, NULL, i, &stream);
    fclose(stream.file);
    return failures ? 1 : 0;  // the encoder still open
  }
  quarters_and_repeats(enc);
  rift_ffenc_close(enc);
  // A fresh encoder per case, as each share opens its own.
  void (*cases[])(RiftFfenc*) = {moving_bar, letterboxed, memory_between};
  for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
    RiftFfenc* next = open_encoder();
    CHECK(next, "the encoder did not open again");
    if (!next) continue;
    cases[i](next);
    rift_ffenc_close(next);
  }
  ID3D11DeviceContext_Release(context);
  ID3D11Device_Release(device);
  if (failures) fprintf(stderr, "%s: %d failures\n", encoder, failures);
  return failures ? 1 : 0;
}
