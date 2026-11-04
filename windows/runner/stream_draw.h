#ifndef RUNNER_STREAM_DRAW_H_
#define RUNNER_STREAM_DRAW_H_

// A watched share's picture drawn into a texture Flutter can show: one shared
// BGRA texture, drawn on the runner's own D3D11 device and waited for, which
// ANGLE opens by its handle (docs/gpu-codecs/STEP3_WINDOWS.md). No Flutter here, so
// test/stream_draw_test.cpp can drive it alone.

// d3d10.h after d3d11_4.h, which brings in d3d10_1.h that must come first.
#include <d3d11_4.h>
#include <d3d10.h>
#include <windows.h>
#include <wrl/client.h>

#include <cstdint>
#include <vector>

// rust/src/watching/frames.rs, `WatchPlanes`: the same fields in the same
// order, `#[repr(C)]` there. linux/runner/stream_texture.cc has them too.
struct WatchPlanes {
  uint32_t width, height;
  const uint8_t* y;
  const uint8_t* u;
  const uint8_t* v;
  uint32_t stride_y, stride_u, stride_v;
  // kInMemory: the three planes above; kInD3d11: |texture| and |slice| below.
  // The DMA-BUF layers and the CUDA picture are Linux's.
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
  // kInD3d11: the decoder's ID3D11Texture2D array, on this runner's device,
  // and the picture's slice in it; NV12 at the decoder's aligned size, the
  // picture its top left.
  void* texture;
  uint32_t slice;
};
constexpr uint32_t kInMemory = 0;
constexpr uint32_t kInD3d11 = 3;
constexpr uint32_t kBt601 = 0;
constexpr uint32_t kBt709 = 1;
constexpr uint32_t kBt2020 = 2;

// Where the drawing's warnings go: the debugger's output until the runner
// points it at the app's log.
using StreamLogFn = void (*)(const char* line);
void SetStreamLog(StreamLogFn log);
// One line there, printf-style.
void StreamLog(const char* format, ...);

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

  // Draws |planes| and waits for the GPU to finish it, so another device
  // (ANGLE's) reads the whole picture. kInMemory is uploaded first; kInD3d11,
  // a slice of a GPU decoder's array on this device, is drawn where it lies,
  // or copied first where the array is no shader resource. Under the device's
  // multithread lock, which the decoder's FFmpeg takes too, so neither uses
  // the immediate context while the other is part way through. False when it
  // could not: a picture it does not take, or the device removed. The last
  // picture drawn stays.
  bool Draw(const WatchPlanes& planes);
  // The texture's DXGI shared handle, null before the first picture. A new
  // size makes a new texture, and so a new handle.
  HANDLE handle() const { return handle_; }
  uint32_t width() const { return width_; }
  uint32_t height() const { return height_; }

 private:
  // NV12's two views of one slice: Y as R8, interleaved UV as R8G8.
  struct SliceViews {
    Microsoft::WRL::ComPtr<ID3D11ShaderResourceView> y, uv;
  };

  bool Prepare();
  bool Size(uint32_t width, uint32_t height);
  void SetColour(uint32_t matrix, uint32_t full_range);
  bool Upload(const WatchPlanes& planes);
  bool Slice(const WatchPlanes& planes);
  bool Source(ID3D11Texture2D* texture);
  bool Views(ID3D11Texture2D* texture, uint32_t slice, SliceViews* views);
  void SetPlace(const WatchPlanes& planes);
  void Run(ID3D11PixelShader* pixel, ID3D11ShaderResourceView* const* views,
           UINT count);
  bool Submit();
  bool Wait();

  Microsoft::WRL::ComPtr<ID3D11Device> device_;
  Microsoft::WRL::ComPtr<ID3D11DeviceContext> context_;
  Microsoft::WRL::ComPtr<ID3D10Multithread> multithread_;
  Microsoft::WRL::ComPtr<ID3D11VertexShader> vertex_;
  Microsoft::WRL::ComPtr<ID3D11PixelShader> pixel_;
  Microsoft::WRL::ComPtr<ID3D11PixelShader> pixel_nv12_;
  Microsoft::WRL::ComPtr<ID3D11SamplerState> sampler_;
  Microsoft::WRL::ComPtr<ID3D11Buffer> colour_;
  Microsoft::WRL::ComPtr<ID3D11Buffer> place_;
  Microsoft::WRL::ComPtr<ID3D11Texture2D> planes_[3];
  Microsoft::WRL::ComPtr<ID3D11ShaderResourceView> plane_views_[3];
  // The decoder's array the slice views below are of, held so its address
  // cannot name another array while they are kept; let go for the next
  // array. Copied into |copy_| first when it is no shader resource.
  Microsoft::WRL::ComPtr<ID3D11Texture2D> source_;
  D3D11_TEXTURE2D_DESC source_desc_ = {};
  bool source_readable_ = false;
  std::vector<SliceViews> slice_views_;
  Microsoft::WRL::ComPtr<ID3D11Texture2D> copy_;
  SliceViews copy_views_;
  float place_written_[4] = {};
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
