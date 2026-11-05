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
#include <string>
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

// Reads back what |draw| drew and checks the texture's size, each block's
// centre, and its corners: row 0 the top, and the last row the picture's own.
// |flipped|: the bottom blocks on top.
void CheckDrawn(StreamDraw& draw, Reader& reader, uint32_t w, uint32_t h,
                bool flipped, const char* what) {
  CHECK(draw.width() == w && draw.height() == h, "%s %ux%u: size %ux%u", what,
        w, h, draw.width(), draw.height());
  CHECK(draw.handle() != nullptr, "%s %ux%u: no handle", what, w, h);
  Readback back;
  if (!reader.Read(draw.handle(), &back)) {
    CHECK(false, "%s %ux%u: could not read the shared texture back", what, w,
          h);
    return;
  }
  CHECK(back.width == w && back.height == h, "%s %ux%u: texture is %ux%u",
        what, w, h, back.width, back.height);
  auto want = [&](int block) { return kWant[flipped ? block ^ 2 : block]; };
  const uint32_t xs[2] = {w / 4, w * 3 / 4}, ys[2] = {h / 4, h * 3 / 4};
  for (int i = 0; i < 4; i++) {
    const Rgb got = back.At(xs[i & 1], ys[i >> 1]);
    std::printf("  %s %ux%u block %d at (%u,%u): %d,%d,%d\n", what, w, h, i,
                xs[i & 1], ys[i >> 1], got.r, got.g, got.b);
    CHECK(Near(got, want(i)), "%s %ux%u block %d: %d,%d,%d, want %d,%d,%d",
          what, w, h, i, got.r, got.g, got.b, want(i).r, want(i).g, want(i).b);
  }
  // Row 0 is the top: the first row is red then green, never blue then white.
  CHECK(Near(back.At(0, 0), want(0)) && Near(back.At(w - 1, 0), want(1)),
        "%s %ux%u: row 0 is not the top", what, w, h);
  const Rgb last_left = back.At(0, h - 1), last_right = back.At(w - 1, h - 1);
  CHECK(Near(last_left, want(2)) && Near(last_right, want(3)),
        "%s %ux%u: the last row is %d,%d,%d and %d,%d,%d, not the bottom's",
        what, w, h, last_left.r, last_left.g, last_left.b, last_right.r,
        last_right.g, last_right.b);
}

// Draws a w x h picture from memory and checks it.
void DrawAndCheck(StreamDraw& draw, Reader& reader, uint32_t w,
                  uint32_t h) {
  Picture picture(w, h);
  CHECK(draw.Draw(picture.Planes()), "%ux%u: Draw failed", w, h);
  CheckDrawn(draw, reader, w, h, false, "memory");
}

// ── A GPU decoder's pictures (phase B) ────────────────────────────────────

// The four blocks in BT.709 full range, as a stream may say it is coded.
Yuv Bt709Full(const Rgb& c) {
  auto byte = [](double v) {
    return static_cast<uint8_t>(v < 0 ? 0 : v > 255 ? 255 : v + 0.5);
  };
  const double y = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
  return {byte(y), byte(128 + (c.b - y) / 1.8556),
          byte(128 + (c.r - y) / 1.5748)};
}

// As FFmpeg's d3d11va makes a decoder's surfaces: one NV12 array, coded
// 16-line aligned (1088 lines for 1080), the decoder's and, where |readable|,
// a shader resource too. Slices |at| and |flipped_at| hold the four blocks in
// |blocks|, the second upside down; every other slice is magenta, and so are
// the coded rows past the picture in all of them, which would show if they
// were drawn or bled into the last row.
constexpr uint32_t kSlices = 8;
ComPtr<ID3D11Texture2D> DecoderArray(ID3D11Device* device, uint32_t w,
                                     uint32_t h, bool readable,
                                     const Yuv blocks[4], uint32_t at,
                                     uint32_t flipped_at) {
  const uint32_t coded_w = (w + 15) / 16 * 16, coded_h = (h + 15) / 16 * 16;
  D3D11_TEXTURE2D_DESC desc = {};
  desc.Width = coded_w;
  desc.Height = coded_h;
  desc.MipLevels = 1;
  desc.ArraySize = kSlices;
  desc.Format = DXGI_FORMAT_NV12;
  desc.SampleDesc.Count = 1;
  desc.Usage = D3D11_USAGE_DEFAULT;
  desc.BindFlags =
      D3D11_BIND_DECODER | (readable ? D3D11_BIND_SHADER_RESOURCE : 0);
  ComPtr<ID3D11Texture2D> array;
  if (FAILED(device->CreateTexture2D(&desc, nullptr, &array))) return nullptr;

  D3D11_TEXTURE2D_DESC one = desc;
  one.ArraySize = 1;
  one.Usage = D3D11_USAGE_STAGING;
  one.BindFlags = 0;
  one.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
  ComPtr<ID3D11DeviceContext> context;
  device->GetImmediateContext(&context);
  const Yuv magenta = {105, 212, 234};
  for (uint32_t slice = 0; slice < kSlices; slice++) {
    ComPtr<ID3D11Texture2D> staging;
    if (FAILED(device->CreateTexture2D(&one, nullptr, &staging))) return nullptr;
    D3D11_MAPPED_SUBRESOURCE mapped;
    if (FAILED(context->Map(staging.Get(), 0, D3D11_MAP_WRITE, 0, &mapped)))
      return nullptr;
    uint8_t* rows = static_cast<uint8_t*>(mapped.pData);
    uint8_t* uv = rows + size_t(mapped.RowPitch) * coded_h;
    auto colour = [&](uint32_t c, uint32_t r) -> const Yuv& {
      if (r >= h || c >= w || (slice != at && slice != flipped_at))
        return magenta;
      return blocks[Picture::Block(c, r, w, h, slice == flipped_at)];
    };
    for (uint32_t r = 0; r < coded_h; r++)
      for (uint32_t c = 0; c < coded_w; c++)
        rows[size_t(r) * mapped.RowPitch + c] = colour(c, r).y;
    for (uint32_t r = 0; r < coded_h / 2; r++)
      for (uint32_t c = 0; c < coded_w / 2; c++) {
        const Yuv& b = colour(c * 2, r * 2);
        uv[size_t(r) * mapped.RowPitch + c * 2] = b.u;
        uv[size_t(r) * mapped.RowPitch + c * 2 + 1] = b.v;
      }
    context->Unmap(staging.Get(), 0);
    context->CopySubresourceRegion(array.Get(),
                                   D3D11CalcSubresource(0, slice, 1), 0, 0, 0,
                                   staging.Get(), 0, nullptr);
  }
  return array;
}

WatchPlanes Slice(ID3D11Texture2D* array, uint32_t slice, uint32_t w,
                  uint32_t h, uint32_t matrix, uint32_t full_range) {
  WatchPlanes p{};
  p.width = w;
  p.height = h;
  p.kind = kInD3d11;
  p.fds[0] = p.fds[1] = -1;
  p.matrix = matrix;
  p.full_range = full_range;
  p.texture = array;
  p.slice = slice;
  return p;
}

// Slices of a decoder's array drawn where they lie (or copied first, where
// the array is no shader resource): the right slice, the right way up, only
// the picture's part of the coded size, and the colour the stream says.
void DrawsDecodedSlices(ID3D11Device* device, Reader& reader, bool readable) {
  const char* what = readable ? "slice" : "copied slice";
  const uint32_t w = 1920, h = 1080;
  ComPtr<ID3D11Texture2D> array =
      DecoderArray(device, w, h, readable, kBlocks, 3, 5);
  CHECK(array != nullptr, "%s: no decoder array", what);
  if (!array) return;
  StreamDraw draw(device);
  // Slice 3, then 5 (upside down), then 3 again: each slice's own views.
  for (uint32_t slice : {3u, 5u, 3u}) {
    CHECK(draw.Draw(Slice(array.Get(), slice, w, h, kBt601, 0)),
          "%s %u: Draw failed", what, slice);
    CheckDrawn(draw, reader, w, h, slice == 5, what);
  }

  // BT.709 in full range, as the stream says.
  Yuv bt709[4];
  for (int i = 0; i < 4; i++) bt709[i] = Bt709Full(kWant[i]);
  ComPtr<ID3D11Texture2D> full =
      DecoderArray(device, w, h, readable, bt709, 2, 6);
  CHECK(full != nullptr, "%s: no BT.709 array", what);
  if (full) {
    CHECK(draw.Draw(Slice(full.Get(), 2, w, h, kBt709, 1)),
          "%s BT.709: Draw failed", what);
    CheckDrawn(draw, reader, w, h, false, readable ? "BT.709 slice"
                                                   : "BT.709 copied slice");
  }

  // A slice outside the array, or a picture larger than it, is refused.
  CHECK(!draw.Draw(Slice(array.Get(), kSlices, w, h, kBt601, 0)),
        "%s: a slice outside the array was drawn", what);
  CHECK(!draw.Draw(Slice(array.Get(), 3, w, 2000, kBt601, 0)),
        "%s: a picture taller than its array was drawn", what);
  WatchPlanes none = Slice(nullptr, 0, w, h, kBt601, 0);
  CHECK(!draw.Draw(none), "%s: a slice of no texture was drawn", what);
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

std::string logged;

void Log(const char* line) {
  std::printf("  log: %s\n", line);
  logged += line;
  logged += "\n";
}

// A draw's wait that timed out leaves its fence's event to be set when that
// draw finishes, after the wait gave up; the event is auto-reset, so the next
// draw's wait woke on it at once and answered drawn while its own draw was
// still on the GPU, a half-drawn picture for ANGLE (found by review). Driven
// with a fence of the draw's device and an event that is set late that way.
void AStaleWakeUpIsNotTakenForTheDraw(ID3D11Device* device) {
  std::printf("a stale wake-up is not taken for the draw\n");
  ComPtr<ID3D11Device5> device5;
  ComPtr<ID3D11DeviceContext> context;
  ComPtr<ID3D11DeviceContext4> context4;
  ComPtr<ID3D11Fence> fence;
  device->GetImmediateContext(&context);
  if (FAILED(device->QueryInterface(IID_PPV_ARGS(&device5))) ||
      FAILED(context.As(&context4)) ||
      FAILED(device5->CreateFence(0, D3D11_FENCE_FLAG_NONE,
                                  IID_PPV_ARGS(&fence)))) {
    std::printf("  no fence here; StreamDraw polls a query instead\n");
    return;
  }
  HANDLE event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
  CHECK(event != nullptr, "no event");
  if (!event) return;

  // Draw 1 finishes after its wait gave up: the event is left set.
  context4->Signal(fence.Get(), 1);
  context->Flush();
  fence->SetEventOnCompletion(1, event);
  const ULONGLONG until = GetTickCount64() + 1000;
  while (fence->GetCompletedValue() < 1 && GetTickCount64() < until) {
    SwitchToThread();
  }
  CHECK(fence->GetCompletedValue() >= 1, "the fence never reached 1");

  // Draw 2 is not on the GPU yet: its wait must not answer drawn.
  logged.clear();
  fence->SetEventOnCompletion(2, event);
  const ULONGLONG start = GetTickCount64();
  const bool drawn = WaitForFence(fence.Get(), 2, event, 200);
  const ULONGLONG took = GetTickCount64() - start;
  CHECK(!drawn, "answered drawn after %llu ms with the fence at %llu of 2",
        took, fence->GetCompletedValue());
  CHECK(took >= 150, "gave up after %llu ms, not the 200 asked", took);
  CHECK(logged.find("did not finish a draw") != std::string::npos,
        "the timeout was not logged by name");

  // Draw 2 lands, after a stale wake-up again: answered once it is there.
  SetEvent(event);
  context4->Signal(fence.Get(), 2);
  context->Flush();
  CHECK(WaitForFence(fence.Get(), 2, event, 1000), "draw 2 was not waited for");
  CHECK(fence->GetCompletedValue() >= 2, "answered with the fence at %llu of 2",
        fence->GetCompletedValue());
  CloseHandle(event);
}

}  // namespace

int main(int argc, char** argv) {
  // Every line out at once, so a crash still shows how far it got.
  std::setvbuf(stdout, nullptr, _IONBF, 0);
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

  // A GPU decoder's pictures: in place where the GPU lets the shader read
  // NV12, and copied either way.
  UINT support = 0;
  device->CheckFormatSupport(DXGI_FORMAT_NV12, &support);
  const bool readable = (support & D3D11_FORMAT_SUPPORT_SHADER_SAMPLE) != 0;
  std::printf("NV12 %s shader views here\n", readable ? "takes" : "takes no");
  if (readable) DrawsDecodedSlices(device.Get(), reader, true);
  DrawsDecodedSlices(device.Get(), reader, false);

  SetStreamLog(Log);
  AStaleWakeUpIsNotTakenForTheDraw(device.Get());

  if (failures) {
    std::printf("%d failed\n", failures);
    return 1;
  }
  std::printf("all passed\n");
  return 0;
}
