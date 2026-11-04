// Draws pictures with StreamDraw on a real device and reads the shared texture
// back as Flutter would, through its handle: the colours, which way up, and
// resizing. No Flutter. Built and run by run.ps1:
//   stream_draw_test <adapter index>
#include <d3d11.h>
#include <dxgi.h>
#include <windows.h>
#include <wrl/client.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "stream_draw.h"

using Microsoft::WRL::ComPtr;

namespace {

int failures = 0;

#define CHECK(cond, ...)                                       \
  do {                                                         \
    if (!(cond)) {                                             \
      std::printf("FAIL %s:%d: %s: ", __FILE__, __LINE__, #cond); \
      std::printf(__VA_ARGS__);                                \
      std::printf("\n");                                       \
      failures++;                                              \
    }                                                          \
  } while (0)

struct Yuv {
  uint8_t y, u, v;
};
struct Rgb {
  int r, g, b;
};

// BT.601 limited range, as libwebrtc's pictures are drawn: red, green, blue
// and white, top left, top right, bottom left, bottom right.
constexpr Yuv kBlocks[4] = {{81, 90, 240}, {145, 54, 34}, {41, 240, 110},
                            {235, 128, 128}};
constexpr Rgb kWant[4] = {{255, 0, 0}, {0, 255, 0}, {0, 0, 255},
                          {255, 255, 255}};

// An I420 picture of the four blocks, with each plane's rows padded past its
// width, so a draw that ignores the strides shows it.
struct Picture {
  uint32_t width, height, cw, ch;
  std::vector<uint8_t> y, u, v;
  uint32_t sy, su, sv;

  // |flipped|: the bottom blocks on top, so two pictures in turn differ
  // everywhere.
  Picture(uint32_t w, uint32_t h, bool flipped = false)
      : width(w), height(h), cw((w + 1) / 2), ch((h + 1) / 2) {
    sy = w + 32;
    su = sv = cw + 16;
    y.assign(size_t(sy) * h, 0);
    u.assign(size_t(su) * ch, 0);
    v.assign(size_t(sv) * ch, 0);
    for (uint32_t r = 0; r < h; r++)
      for (uint32_t c = 0; c < w; c++)
        y[r * sy + c] = kBlocks[Block(c, r, w, h, flipped)].y;
    for (uint32_t r = 0; r < ch; r++)
      for (uint32_t c = 0; c < cw; c++) {
        const Yuv& b = kBlocks[Block(c * 2, r * 2, w, h, flipped)];
        u[r * su + c] = b.u;
        v[r * sv + c] = b.v;
      }
  }

  static int Block(uint32_t c, uint32_t r, uint32_t w, uint32_t h,
                   bool flipped) {
    return ((r >= h / 2) != flipped ? 2 : 0) + (c >= w / 2 ? 1 : 0);
  }

  WatchPlanes Planes() const {
    WatchPlanes p{};
    p.width = width;
    p.height = height;
    p.y = y.data();
    p.u = u.data();
    p.v = v.data();
    p.stride_y = sy;
    p.stride_u = su;
    p.stride_v = sv;
    p.kind = kInMemory;
    p.fds[0] = p.fds[1] = -1;
    return p;
  }
};

ComPtr<IDXGIAdapter1> Adapter(UINT index, DXGI_ADAPTER_DESC1* desc) {
  ComPtr<IDXGIFactory1> factory;
  ComPtr<IDXGIAdapter1> adapter;
  if (FAILED(CreateDXGIFactory1(IID_PPV_ARGS(&factory))) ||
      factory->EnumAdapters1(index, &adapter) != S_OK)
    return nullptr;
  adapter->GetDesc1(desc);
  return adapter;
}

// The picture as Flutter sees it: opened by its shared handle, copied to a
// staging texture and mapped. BGRA rows, top first.
struct Readback {
  uint32_t width = 0, height = 0, pitch = 0;
  std::vector<uint8_t> bytes;
  Rgb At(uint32_t x, uint32_t y) const {
    const uint8_t* p = &bytes[size_t(y) * pitch + x * 4];
    return {p[2], p[1], p[0]};
  }
};

// The second device, which keeps the texture it opened and its staging copy
// until the handle changes, as ANGLE keeps its surface: opening again for each
// read gives the GPU time to finish and hides a missing wait.
class Reader {
 public:
  explicit Reader(ID3D11Device* device) : device_(device) {
    device_->GetImmediateContext(&context_);
  }
  ID3D11Device* device() const { return device_; }

  bool Read(HANDLE handle, Readback* out) {
    if (handle != handle_) {
      shared_.Reset();
      staging_.Reset();
      handle_ = nullptr;
      if (FAILED(device_->OpenSharedResource(handle, IID_PPV_ARGS(&shared_))))
        return false;
      shared_->GetDesc(&desc_);
      D3D11_TEXTURE2D_DESC desc = desc_;
      desc.Usage = D3D11_USAGE_STAGING;
      desc.BindFlags = 0;
      desc.MiscFlags = 0;
      desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
      if (FAILED(device_->CreateTexture2D(&desc, nullptr, &staging_)))
        return false;
      handle_ = handle;
    }
    context_->CopyResource(staging_.Get(), shared_.Get());
    D3D11_MAPPED_SUBRESOURCE mapped;
    if (FAILED(context_->Map(staging_.Get(), 0, D3D11_MAP_READ, 0, &mapped)))
      return false;
    out->width = desc_.Width;
    out->height = desc_.Height;
    out->pitch = mapped.RowPitch;
    const uint8_t* rows = static_cast<const uint8_t*>(mapped.pData);
    out->bytes.assign(rows, rows + size_t(mapped.RowPitch) * desc_.Height);
    context_->Unmap(staging_.Get(), 0);
    return true;
  }

 private:
  ID3D11Device* device_;
  ComPtr<ID3D11DeviceContext> context_;
  HANDLE handle_ = nullptr;
  ComPtr<ID3D11Texture2D> shared_, staging_;
  D3D11_TEXTURE2D_DESC desc_ = {};
};

bool Near(const Rgb& got, const Rgb& want) {
  return std::abs(got.r - want.r) <= 2 && std::abs(got.g - want.g) <= 2 &&
         std::abs(got.b - want.b) <= 2;
}

// Draws a w x h picture and checks each block's centre and the texture's size.
void DrawAndCheck(StreamDraw& draw, Reader& reader, uint32_t w,
                  uint32_t h) {
  Picture picture(w, h);
  CHECK(draw.Draw(picture.Planes()), "%ux%u: Draw failed", w, h);
  CHECK(draw.width() == w && draw.height() == h, "%ux%u: size %ux%u", w, h,
        draw.width(), draw.height());
  CHECK(draw.handle() != nullptr, "%ux%u: no handle", w, h);
  Readback back;
  if (!reader.Read(draw.handle(), &back)) {
    CHECK(false, "%ux%u: could not read the shared texture back", w, h);
    return;
  }
  CHECK(back.width == w && back.height == h, "%ux%u: texture is %ux%u", w, h,
        back.width, back.height);
  const uint32_t xs[2] = {w / 4, w * 3 / 4}, ys[2] = {h / 4, h * 3 / 4};
  for (int i = 0; i < 4; i++) {
    const Rgb got = back.At(xs[i & 1], ys[i >> 1]);
    std::printf("  %ux%u block %d at (%u,%u): %d,%d,%d\n", w, h, i, xs[i & 1],
                ys[i >> 1], got.r, got.g, got.b);
    CHECK(Near(got, kWant[i]), "%ux%u block %d: %d,%d,%d, want %d,%d,%d", w, h,
          i, got.r, got.g, got.b, kWant[i].r, kWant[i].g, kWant[i].b);
  }
  // Row 0 is the top: the first row is red then green, never blue then white.
  CHECK(Near(back.At(0, 0), kWant[0]) && Near(back.At(w - 1, 0), kWant[1]),
        "%ux%u: row 0 is not the top", w, h);
  CHECK(Near(back.At(0, h - 1), kWant[2]) &&
            Near(back.At(w - 1, h - 1), kWant[3]),
        "%ux%u: the last row is not the bottom", w, h);
}

// Two pictures in turn, each read back by the other device the moment Draw
// returns, as ANGLE reads on the raster thread, at 1440p, where a draw takes
// long enough to be caught: without the wait in Draw the RTX gave a half-drawn
// picture (the new bottom under the old top) in almost every read.
void ReadsTheWholePictureAtOnce(StreamDraw& draw, Reader& reader) {
  const Picture pictures[2] = {Picture(2560, 1440),
                               Picture(2560, 1440, true)};
  int wrong = 0;
  for (int n = 0; n < 200; n++) {
    const bool flipped = n & 1;
    if (!draw.Draw(pictures[flipped].Planes())) {
      CHECK(false, "draw %d failed", n);
      return;
    }
    Readback back;
    if (!reader.Read(draw.handle(), &back)) {
      CHECK(false, "read %d failed", n);
      return;
    }
    const int top = flipped ? 2 : 0, bottom = flipped ? 0 : 2;
    if (!Near(back.At(640, 360), kWant[top]) ||
        !Near(back.At(640, 1080), kWant[bottom])) {
      wrong++;
    }
  }
  std::printf("  200 pictures in turn, read at once: %d wrong\n", wrong);
  CHECK(wrong == 0, "%d of 200 pictures were read stale or half drawn", wrong);
}

}  // namespace

int main(int argc, char** argv) {
  const UINT index = argc > 1 ? UINT(std::atoi(argv[1])) : 0;
  DXGI_ADAPTER_DESC1 desc{};
  if (!Adapter(index, &desc)) {
    std::printf("FAIL: no adapter %u\n", index);
    return 1;
  }
  std::printf("adapter %u: %ls\n", index, desc.Description);

  ComPtr<ID3D11Device> device = MakeDevice(desc.AdapterLuid);
  CHECK(device != nullptr, "MakeDevice failed");
  if (!device) return 1;
  {
    ComPtr<ID3D11VideoDevice> video;
    CHECK(SUCCEEDED(device.As(&video)), "the device has no video support");
  }

  // A second device on the same adapter reads the texture, as ANGLE's does.
  ComPtr<ID3D11Device> reader_device;
  {
    ComPtr<IDXGIAdapter1> adapter = Adapter(index, &desc);
    D3D11CreateDevice(adapter.Get(), D3D_DRIVER_TYPE_UNKNOWN, nullptr, 0,
                      nullptr, 0, D3D11_SDK_VERSION, &reader_device, nullptr,
                      nullptr);
  }
  CHECK(reader_device != nullptr, "no reader device");
  if (!reader_device) return 1;
  Reader reader(reader_device.Get());

  StreamDraw draw(device.Get());
  CHECK(draw.handle() == nullptr && draw.width() == 0,
        "a StreamDraw with no picture yet has a texture");
  DrawAndCheck(draw, reader, 1920, 1080);
  HANDLE first = draw.handle();
  DrawAndCheck(draw, reader, 1920, 1080);
  CHECK(draw.handle() == first, "the same size made a new texture");
  DrawAndCheck(draw, reader, 1280, 720);
  DrawAndCheck(draw, reader, 1279, 719);
  ReadsTheWholePictureAtOnce(draw, reader);

  // A picture it cannot draw is refused, and the last one stays.
  WatchPlanes empty{};
  empty.kind = kInMemory;
  CHECK(!draw.Draw(empty), "a 0x0 picture was drawn");
  Picture other(64, 64);
  WatchPlanes odd = other.Planes();
  odd.kind = 7;
  CHECK(!draw.Draw(odd), "a picture of an unknown kind was drawn");
  CHECK(draw.width() == 2560 && draw.height() == 1440,
        "a refused picture changed the texture");

  if (failures) {
    std::printf("%d failed\n", failures);
    return 1;
  }
  std::printf("all passed\n");
  return 0;
}
