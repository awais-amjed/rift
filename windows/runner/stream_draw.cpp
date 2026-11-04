#include "stream_draw.h"

#include <d3d10.h>
#include <d3d11_4.h>
#include <dxgi.h>

#include <cstdarg>
#include <cstdio>
#include <cstring>

// Made at build time from stream_draw_vs.hlsl, stream_draw_ps.hlsl and
// stream_draw_nv12_ps.hlsl, by MSBuild's shader step (CMakeLists.txt) or by
// test/run.ps1.
#include "stream_draw_nv12_ps.h"
#include "stream_draw_ps.h"
#include "stream_draw_vs.h"

using Microsoft::WRL::ComPtr;

namespace {

void DebuggerLog(const char* line) {
  OutputDebugStringA(line);
  OutputDebugStringA("\n");
}

StreamLogFn sink = DebuggerLog;

// The pixel shader's Colour: what Y, U and V each add to red, green and blue,
// then black's Y, U and V. Four float4s, as HLSL packs them.
struct ColourSums {
  float from_y[4], from_u[4], from_v[4], black[4];
};

// linux/runner/stream_texture.cc's Colour, the same sums: each matrix's own
// (ITU-R BT.601, BT.709, BT.2020), with limited range's 219 and 224 steps
// stretched to the full 255.
ColourSums Sums(uint32_t matrix, uint32_t full_range) {
  float kr = 0.299f, kb = 0.114f;
  if (matrix == kBt709) {
    kr = 0.2126f;
    kb = 0.0722f;
  } else if (matrix == kBt2020) {
    kr = 0.2627f;
    kb = 0.0593f;
  }
  const float kg = 1.0f - kr - kb;
  const bool full = full_range != 0;
  const float sy = full ? 1.0f : 255.0f / 219.0f;
  const float sc = full ? 1.0f : 255.0f / 224.0f;
  return ColourSums{
      {sy, sy, sy, 0},
      {0.0f, -sc * 2.0f * kb * (1.0f - kb) / kg, sc * 2.0f * (1.0f - kb), 0},
      {sc * 2.0f * (1.0f - kr), -sc * 2.0f * kr * (1.0f - kr) / kg, 0.0f, 0},
      {full ? 0.0f : 16.0f / 255.0f, 128.0f / 255.0f, 128.0f / 255.0f, 0}};
}

bool Plane(ID3D11Device* device, uint32_t width, uint32_t height,
           ComPtr<ID3D11Texture2D>* texture,
           ComPtr<ID3D11ShaderResourceView>* view) {
  D3D11_TEXTURE2D_DESC desc = {};
  desc.Width = width;
  desc.Height = height;
  desc.MipLevels = desc.ArraySize = 1;
  desc.Format = DXGI_FORMAT_R8_UNORM;
  desc.SampleDesc.Count = 1;
  desc.Usage = D3D11_USAGE_DEFAULT;
  desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
  HRESULT hr = device->CreateTexture2D(&desc, nullptr, texture->ReleaseAndGetAddressOf());
  if (SUCCEEDED(hr)) {
    hr = device->CreateShaderResourceView(texture->Get(), nullptr,
                                          view->ReleaseAndGetAddressOf());
  }
  if (FAILED(hr)) {
    StreamLog("stream texture: plane %ux%u: %08lx", width, height, hr);
  }
  return SUCCEEDED(hr);
}

}  // namespace

void SetStreamLog(StreamLogFn log) { sink = log ? log : DebuggerLog; }

void StreamLog(const char* format, ...) {
  char line[512];
  va_list args;
  va_start(args, format);
  std::vsnprintf(line, sizeof line, format, args);
  va_end(args);
  sink(line);
}

ComPtr<ID3D11Device> MakeDevice(LUID luid) {
  ComPtr<IDXGIFactory1> factory;
  HRESULT hr = CreateDXGIFactory1(IID_PPV_ARGS(&factory));
  if (FAILED(hr)) {
    StreamLog("stream texture: no DXGI factory: %08lx", hr);
    return nullptr;
  }
  ComPtr<IDXGIAdapter1> adapter;
  DXGI_ADAPTER_DESC1 desc = {};
  for (UINT i = 0; factory->EnumAdapters1(i, &adapter) == S_OK; i++) {
    adapter->GetDesc1(&desc);
    if (desc.AdapterLuid.LowPart == luid.LowPart &&
        desc.AdapterLuid.HighPart == luid.HighPart) {
      break;
    }
    adapter.Reset();
  }
  if (!adapter) {
    StreamLog("stream texture: no adapter with Flutter's LUID %08lx:%08lx",
        luid.HighPart, luid.LowPart);
    return nullptr;
  }

  // Feature level 11 for the shaders (model 5.0). Video support is for phase
  // B's decoder; a driver without it still draws.
  const D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_11_1,
                                      D3D_FEATURE_LEVEL_11_0};
  const UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
  ComPtr<ID3D11Device> device;
  hr = D3D11CreateDevice(adapter.Get(), D3D_DRIVER_TYPE_UNKNOWN, nullptr,
                         flags | D3D11_CREATE_DEVICE_VIDEO_SUPPORT, levels,
                         ARRAYSIZE(levels), D3D11_SDK_VERSION, &device, nullptr,
                         nullptr);
  if (FAILED(hr)) {
    StreamLog("stream texture: no video device on %ls (%08lx), drawing only",
        desc.Description, hr);
    hr = D3D11CreateDevice(adapter.Get(), D3D_DRIVER_TYPE_UNKNOWN, nullptr,
                           flags, levels, ARRAYSIZE(levels), D3D11_SDK_VERSION,
                           &device, nullptr, nullptr);
  }
  if (FAILED(hr)) {
    StreamLog("stream texture: no D3D11 device at level 11 on %ls: %08lx",
        desc.Description, hr);
    return nullptr;
  }
  ComPtr<ID3D10Multithread> multithread;
  if (SUCCEEDED(device.As(&multithread))) {
    multithread->SetMultithreadProtected(TRUE);
  }
  StreamLog("stream texture: device on %ls", desc.Description);
  return device;
}

StreamDraw::StreamDraw(ID3D11Device* device) : device_(device) {
  device_->GetImmediateContext(&context_);
  device_.As(&multithread_);
}

StreamDraw::~StreamDraw() {
  if (done_) CloseHandle(done_);
}

bool StreamDraw::Prepare() {
  if (prepared_) return true;
  HRESULT hr = device_->CreateVertexShader(kStreamDrawVs, sizeof kStreamDrawVs,
                                           nullptr, &vertex_);
  if (SUCCEEDED(hr)) {
    hr = device_->CreatePixelShader(kStreamDrawPs, sizeof kStreamDrawPs,
                                    nullptr, &pixel_);
  }
  if (SUCCEEDED(hr)) {
    hr = device_->CreatePixelShader(kStreamDrawNv12Ps, sizeof kStreamDrawNv12Ps,
                                    nullptr, &pixel_nv12_);
  }
  if (SUCCEEDED(hr)) {
    D3D11_SAMPLER_DESC desc = {};
    desc.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
    desc.AddressU = desc.AddressV = desc.AddressW =
        D3D11_TEXTURE_ADDRESS_CLAMP;
    desc.MaxLOD = D3D11_FLOAT32_MAX;
    hr = device_->CreateSamplerState(&desc, &sampler_);
  }
  if (SUCCEEDED(hr)) {
    D3D11_BUFFER_DESC desc = {};
    desc.ByteWidth = sizeof(ColourSums);
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    hr = device_->CreateBuffer(&desc, nullptr, &colour_);
  }
  if (SUCCEEDED(hr)) {
    D3D11_BUFFER_DESC desc = {};
    desc.ByteWidth = sizeof place_written_;
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    hr = device_->CreateBuffer(&desc, nullptr, &place_);
  }
  if (FAILED(hr)) {
    StreamLog("stream texture: shaders: %08lx", hr);
    return false;
  }
  prepared_ = true;
  return true;
}

// The shared texture at the picture's size, made again only when it changes.
bool StreamDraw::Size(uint32_t width, uint32_t height) {
  if (out_ && width == width_ && height == height_) return true;
  out_.Reset();
  target_.Reset();
  handle_ = nullptr;
  width_ = height_ = 0;
  D3D11_TEXTURE2D_DESC desc = {};
  desc.Width = width;
  desc.Height = height;
  desc.MipLevels = desc.ArraySize = 1;
  desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  desc.SampleDesc.Count = 1;
  desc.Usage = D3D11_USAGE_DEFAULT;
  desc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
  // A legacy shared handle, which ANGLE opens as a pbuffer
  // (EGL_D3D_TEXTURE_2D_SHARE_HANDLE_ANGLE). No keyed mutex, which ANGLE never
  // takes: Draw waits for the GPU instead (Submit and Wait, STEP3_WINDOWS.md).
  desc.MiscFlags = D3D11_RESOURCE_MISC_SHARED;
  ComPtr<ID3D11Texture2D> out;
  HRESULT hr = device_->CreateTexture2D(&desc, nullptr, &out);
  if (SUCCEEDED(hr)) hr = device_->CreateRenderTargetView(out.Get(), nullptr, &target_);
  ComPtr<IDXGIResource> resource;
  HANDLE handle = nullptr;
  if (SUCCEEDED(hr)) hr = out.As(&resource);
  if (SUCCEEDED(hr)) hr = resource->GetSharedHandle(&handle);
  if (FAILED(hr)) {
    StreamLog("stream texture: texture %ux%u: %08lx", width, height, hr);
    target_.Reset();
    return false;
  }
  out_ = out;
  handle_ = handle;
  width_ = width;
  height_ = height;
  return true;
}

void StreamDraw::SetColour(uint32_t matrix, uint32_t full_range) {
  if (matrix == matrix_ && full_range == full_range_) return;
  const ColourSums sums = Sums(matrix, full_range);
  context_->UpdateSubresource(colour_.Get(), 0, nullptr, &sums, 0, 0);
  matrix_ = matrix;
  full_range_ = full_range;
}

bool StreamDraw::Draw(const WatchPlanes& p) {
  if (p.width == 0 || p.height == 0) return false;
  if (p.kind == kInMemory && (!p.y || !p.u || !p.v)) return false;
  if (p.kind == kInD3d11 && !p.texture) return false;
  if (p.kind != kInMemory && p.kind != kInD3d11) return false;
  if (device_->GetDeviceRemovedReason() != S_OK) return false;
  // Held through everything the draw puts on the immediate context, and let
  // go before the wait: the decoder's FFmpeg takes the same lock for its own
  // calls on the decode thread.
  if (multithread_) multithread_->Enter();
  bool drawn = Prepare() && Size(p.width, p.height) &&
               (p.kind == kInMemory ? Upload(p) : Slice(p)) && Submit();
  if (multithread_) multithread_->Leave();
  if (!drawn || !Wait()) return false;
  return device_->GetDeviceRemovedReason() == S_OK;
}

// libwebrtc's I420, uploaded into three planes of the picture's size, the
// chroma planes half the size each way, rounded up; made again only when the
// size changes.
bool StreamDraw::Upload(const WatchPlanes& p) {
  D3D11_TEXTURE2D_DESC desc = {};
  if (planes_[0]) planes_[0]->GetDesc(&desc);
  if (!planes_[0] || desc.Width != p.width || desc.Height != p.height) {
    const uint32_t cw = (p.width + 1) / 2, ch = (p.height + 1) / 2;
    if (!Plane(device_.Get(), p.width, p.height, &planes_[0], &plane_views_[0]) ||
        !Plane(device_.Get(), cw, ch, &planes_[1], &plane_views_[1]) ||
        !Plane(device_.Get(), cw, ch, &planes_[2], &plane_views_[2])) {
      planes_[0].Reset();
      return false;
    }
  }
  context_->UpdateSubresource(planes_[0].Get(), 0, nullptr, p.y, p.stride_y, 0);
  context_->UpdateSubresource(planes_[1].Get(), 0, nullptr, p.u, p.stride_u, 0);
  context_->UpdateSubresource(planes_[2].Get(), 0, nullptr, p.v, p.stride_v, 0);
  SetColour(p.matrix, p.full_range);
  ID3D11ShaderResourceView* views[3] = {plane_views_[0].Get(),
                                        plane_views_[1].Get(),
                                        plane_views_[2].Get()};
  Run(pixel_.Get(), views, 3);
  return true;
}

// A GPU decoder's picture: one slice of its NV12 array, on this device,
// sampled where it lies through views cached per slice, or copied into a
// texture of ours first where the array is no shader resource (Moonlight's
// d3d11va.cpp does the same).
bool StreamDraw::Slice(const WatchPlanes& p) {
  auto* texture = static_cast<ID3D11Texture2D*>(p.texture);
  if (texture != source_.Get() && !Source(texture)) return false;
  if (p.slice >= source_desc_.ArraySize || p.width > source_desc_.Width ||
      p.height > source_desc_.Height) {
    return false;
  }
  SliceViews* views = &copy_views_;
  if (source_readable_) {
    if (slice_views_.size() < source_desc_.ArraySize) {
      slice_views_.resize(source_desc_.ArraySize);
    }
    views = &slice_views_[p.slice];
    if (!views->y && !Views(texture, p.slice, views)) {
      // Views the GPU would not make after all: copied from here on.
      StreamLog("stream texture: no views of the decoder's slices; each "
                "picture is copied");
      source_readable_ = false;
      slice_views_.clear();
      views = &copy_views_;
    }
  }
  if (!source_readable_) {
    if (!copy_) {
      D3D11_TEXTURE2D_DESC desc = source_desc_;
      desc.ArraySize = 1;
      desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
      desc.MiscFlags = 0;
      desc.CPUAccessFlags = 0;
      desc.Usage = D3D11_USAGE_DEFAULT;
      const HRESULT hr = device_->CreateTexture2D(&desc, nullptr, &copy_);
      if (FAILED(hr)) {
        StreamLog("stream texture: no NV12 texture to copy into: %08lx", hr);
        return false;
      }
      if (!Views(copy_.Get(), 0, &copy_views_)) {
        copy_.Reset();
        return false;
      }
    }
    context_->CopySubresourceRegion(copy_.Get(), 0, 0, 0, 0, texture,
                                    D3D11CalcSubresource(0, p.slice, 1),
                                    nullptr);
  }
  SetColour(p.matrix, p.full_range);
  SetPlace(p);
  ID3D11ShaderResourceView* bound[2] = {views->y.Get(), views->uv.Get()};
  Run(pixel_nv12_.Get(), bound, 2);
  return true;
}

// A new decoder's array: checked to be NV12 on this device, and the views
// and copy kept for the last one let go.
bool StreamDraw::Source(ID3D11Texture2D* texture) {
  source_.Reset();
  slice_views_.clear();
  copy_.Reset();
  copy_views_ = {};
  ComPtr<ID3D11Device> owner;
  texture->GetDevice(&owner);
  if (owner.Get() != device_.Get()) {
    StreamLog("stream texture: a decoded picture from another device");
    return false;
  }
  texture->GetDesc(&source_desc_);
  if (source_desc_.Format != DXGI_FORMAT_NV12) {
    StreamLog("stream texture: a decoded picture in format %d, not NV12",
              int(source_desc_.Format));
    return false;
  }
  source_readable_ =
      (source_desc_.BindFlags & D3D11_BIND_SHADER_RESOURCE) != 0;
  if (!source_readable_) {
    StreamLog("stream texture: the decoder's surfaces are no shader "
              "resources; each picture is copied");
  }
  source_ = texture;
  return true;
}

bool StreamDraw::Views(ID3D11Texture2D* texture, uint32_t slice,
                       SliceViews* views) {
  D3D11_SHADER_RESOURCE_VIEW_DESC desc = {};
  desc.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2DARRAY;
  desc.Texture2DArray.MostDetailedMip = 0;
  desc.Texture2DArray.MipLevels = 1;
  desc.Texture2DArray.FirstArraySlice = slice;
  desc.Texture2DArray.ArraySize = 1;
  desc.Format = DXGI_FORMAT_R8_UNORM;
  HRESULT hr = device_->CreateShaderResourceView(texture, &desc, &views->y);
  if (SUCCEEDED(hr)) {
    desc.Format = DXGI_FORMAT_R8G8_UNORM;
    hr = device_->CreateShaderResourceView(texture, &desc, &views->uv);
  }
  if (FAILED(hr)) {
    StreamLog("stream texture: views of slice %u: %08lx", slice, hr);
    *views = {};
    return false;
  }
  return true;
}

// The picture's part of the coded slice, for the NV12 shader's Place.
void StreamDraw::SetPlace(const WatchPlanes& p) {
  const float coded_w = float(source_desc_.Width);
  const float coded_h = float(source_desc_.Height);
  const float chroma_w = float((p.width + 1) / 2);
  const float chroma_h = float((p.height + 1) / 2);
  const float place[4] = {
      float(p.width) / coded_w, float(p.height) / coded_h,
      (chroma_w - 0.5f) / (coded_w / 2), (chroma_h - 0.5f) / (coded_h / 2)};
  if (std::memcmp(place, place_written_, sizeof place) == 0) return;
  context_->UpdateSubresource(place_.Get(), 0, nullptr, place, 0, 0);
  std::memcpy(place_written_, place, sizeof place);
}

// One triangle over the shared texture through |pixel|, reading |views|.
void StreamDraw::Run(ID3D11PixelShader* pixel,
                     ID3D11ShaderResourceView* const* views, UINT count) {
  ID3D11RenderTargetView* target = target_.Get();
  context_->OMSetRenderTargets(1, &target, nullptr);
  context_->OMSetBlendState(nullptr, nullptr, 0xffffffff);
  context_->OMSetDepthStencilState(nullptr, 0);
  context_->RSSetState(nullptr);
  const D3D11_VIEWPORT viewport = {0, 0, float(width_), float(height_), 0, 1};
  context_->RSSetViewports(1, &viewport);
  context_->IASetInputLayout(nullptr);
  context_->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
  context_->VSSetShader(vertex_.Get(), nullptr, 0);
  context_->PSSetShader(pixel, nullptr, 0);
  context_->PSSetShaderResources(0, count, views);
  ID3D11SamplerState* sampler = sampler_.Get();
  context_->PSSetSamplers(0, 1, &sampler);
  ID3D11Buffer* buffers[2] = {colour_.Get(), place_.Get()};
  context_->PSSetConstantBuffers(0, 2, buffers);
  context_->Draw(3, 0);
  // Out of the pipeline again, so nothing of ours stays bound between draws:
  // a decoder's slice bound here would still be read by the next draw.
  ID3D11ShaderResourceView* none[3] = {};
  context_->PSSetShaderResources(0, 3, none);
  context_->OMSetRenderTargets(0, nullptr, nullptr);
}

// Flushes the draw with a way to wait for it, and Wait waits. ANGLE reads the
// texture on its own device, and a flush alone does not order that read after
// the draw: read back at once from a second device, the RTX gave 198
// half-drawn 1440p pictures in 200 and the Iris Xe 1; waiting first, none
// (STEP3_WINDOWS.md, A read at once does tear). A fence with an event lets
// the thread sleep through the wait; without one (Windows 10 before 1703) an
// event query is polled.
bool StreamDraw::Submit() {
  if (!fence_ && !query_) {
    ComPtr<ID3D11Device5> device5;
    if (SUCCEEDED(device_.As(&device5)) && SUCCEEDED(context_.As(&context4_)) &&
        SUCCEEDED(device5->CreateFence(0, D3D11_FENCE_FLAG_NONE,
                                       IID_PPV_ARGS(&fence_)))) {
      done_ = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    }
    if (!done_) {
      fence_.Reset();
      D3D11_QUERY_DESC desc = {D3D11_QUERY_EVENT, 0};
      HRESULT hr = device_->CreateQuery(&desc, &query_);
      if (FAILED(hr)) {
        StreamLog("stream texture: no way to wait for a draw: %08lx", hr);
        return false;
      }
    }
  }
  if (fence_) {
    const uint64_t value = ++fenced_;
    context4_->Signal(fence_.Get(), value);
    context_->Flush();
    return SUCCEEDED(fence_->SetEventOnCompletion(value, done_));
  }
  context_->End(query_.Get());
  context_->Flush();
  return true;
}

bool StreamDraw::Wait() {
  if (fence_) {
    // A removed device never signals: give up after a second.
    return WaitForSingleObject(done_, 1000) == WAIT_OBJECT_0;
  }
  const ULONGLONG give_up = GetTickCount64() + 1000;
  for (;;) {
    const HRESULT hr = context_->GetData(query_.Get(), nullptr, 0, 0);
    if (hr == S_OK) return true;
    if (hr != S_FALSE || GetTickCount64() > give_up) return false;
    SwitchToThread();
  }
}
