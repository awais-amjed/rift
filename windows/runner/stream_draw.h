#ifndef RUNNER_STREAM_DRAW_H_
#define RUNNER_STREAM_DRAW_H_

// A watched share's picture drawn into a texture Flutter can show: one shared
// BGRA texture, drawn on the runner's own D3D11 device and flushed, which ANGLE
// opens by its handle (docs/gpu-codecs/STEP3_WINDOWS.md). No Flutter here, so
// test/stream_draw_test.cpp can drive it alone.

#include <d3d11_4.h>
#include <windows.h>
#include <wrl/client.h>

#include <cstdint>

// rust/src/watching/frames.rs, `WatchPlanes`: the same fields in the same
// order, `#[repr(C)]` there. linux/runner/stream_texture.cc has them too.
struct WatchPlanes {
  uint32_t width, height;
  const uint8_t* y;
  const uint8_t* u;
  const uint8_t* v;
  uint32_t stride_y, stride_u, stride_v;
  // kInMemory: the three planes above. The rest is Linux's until phase B.
  uint32_t kind;
  uint32_t formats[2];
  int32_t fds[2];
  uint32_t offsets[2], pitches[2];
  uint64_t modifiers[2];
  // kBt601, kBt709 or kBt2020, and 1 for full range rather than limited.
  uint32_t matrix, full_range;
  const void* picture;
  int32_t (*copy_to_gl)(const void* picture, const uint32_t* textures,
                        void** link);
  void (*gl_close)(void* link);
};
constexpr uint32_t kInMemory = 0;
constexpr uint32_t kBt601 = 0;
constexpr uint32_t kBt709 = 1;
constexpr uint32_t kBt2020 = 2;

// Where the drawing's warnings go: the debugger's output until the runner
// points it at the app's log.
using StreamLogFn = void (*)(const char* line);
void SetStreamLog(StreamLogFn log);

// The device on the adapter with |luid|, at feature level 11 or above, with
// video support and multithread protection (phase B's decoder shares it); null
// with the reason logged.
Microsoft::WRL::ComPtr<ID3D11Device> MakeDevice(LUID luid);

// One share's picture: a shared BGRA texture, its handle, and what drawing
// into it needs, sized to the picture as it comes. Used from one thread at a
// time (the raster thread's).
class StreamDraw {
 public:
  explicit StreamDraw(ID3D11Device* device);
  ~StreamDraw();
  StreamDraw(const StreamDraw&) = delete;
  StreamDraw& operator=(const StreamDraw&) = delete;

  // Draws |planes| (kInMemory) and waits for the GPU to finish it, so another
  // device (ANGLE's) reads the whole picture. False when it could not: a
  // picture it does not take, or the device removed. The last picture drawn
  // stays.
  bool Draw(const WatchPlanes& planes);
  // The texture's DXGI shared handle, null before the first picture. A new
  // size makes a new texture, and so a new handle.
  HANDLE handle() const { return handle_; }
  uint32_t width() const { return width_; }
  uint32_t height() const { return height_; }

 private:
  bool Prepare();
  bool Size(uint32_t width, uint32_t height);
  void SetColour(uint32_t matrix, uint32_t full_range);
  bool Finish();

  Microsoft::WRL::ComPtr<ID3D11Device> device_;
  Microsoft::WRL::ComPtr<ID3D11DeviceContext> context_;
  Microsoft::WRL::ComPtr<ID3D11VertexShader> vertex_;
  Microsoft::WRL::ComPtr<ID3D11PixelShader> pixel_;
  Microsoft::WRL::ComPtr<ID3D11SamplerState> sampler_;
  Microsoft::WRL::ComPtr<ID3D11Buffer> colour_;
  Microsoft::WRL::ComPtr<ID3D11Texture2D> planes_[3];
  Microsoft::WRL::ComPtr<ID3D11ShaderResourceView> plane_views_[3];
  Microsoft::WRL::ComPtr<ID3D11Texture2D> out_;
  Microsoft::WRL::ComPtr<ID3D11RenderTargetView> target_;
  // Waiting for a draw: a fence and its event, or an event query where there
  // is no fence.
  Microsoft::WRL::ComPtr<ID3D11DeviceContext4> context4_;
  Microsoft::WRL::ComPtr<ID3D11Fence> fence_;
  HANDLE done_ = nullptr;
  uint64_t fenced_ = 0;
  Microsoft::WRL::ComPtr<ID3D11Query> query_;
  HANDLE handle_ = nullptr;
  uint32_t width_ = 0, height_ = 0;
  // The colour the constant buffer holds; ~0 before the first.
  uint32_t matrix_ = ~0u, full_range_ = ~0u;
  bool prepared_ = false;
};

#endif  // RUNNER_STREAM_DRAW_H_
