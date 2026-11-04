#include "stream_draw.h"

#include <d3d10.h>
#include <d3d11_4.h>
#include <dxgi.h>

#include <cstdarg>
#include <cstdio>

// Made at build time from stream_draw_vs.hlsl and stream_draw_ps.hlsl, by
// MSBuild's shader step (CMakeLists.txt) or by test/run.ps1.
#include "stream_draw_ps.h"
#include "stream_draw_vs.h"

using Microsoft::WRL::ComPtr;

namespace {

void DebuggerLog(const char* line) {
  OutputDebugStringA(line);
  OutputDebugStringA("\n");
}

StreamLogFn sink = DebuggerLog;

void Log(const char* format, ...) {
  char line[512];
  va_list args;
  va_start(args, format);
  std::vsnprintf(line, sizeof line, format, args);
  va_end(args);
  sink(line);
}

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
  if (FAILED(hr)) Log("stream texture: plane %ux%u: %08lx", width, height, hr);
  return SUCCEEDED(hr);
}

}  // namespace

void SetStreamLog(StreamLogFn log) { sink = log ? log : DebuggerLog; }

ComPtr<ID3D11Device> MakeDevice(LUID luid) {
  ComPtr<IDXGIFactory1> factory;
  HRESULT hr = CreateDXGIFactory1(IID_PPV_ARGS(&factory));
  if (FAILED(hr)) {
    Log("stream texture: no DXGI factory: %08lx", hr);
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
    Log("stream texture: no adapter with Flutter's LUID %08lx:%08lx",
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
    Log("stream texture: no video device on %ls (%08lx), drawing only",
        desc.Description, hr);
    hr = D3D11CreateDevice(adapter.Get(), D3D_DRIVER_TYPE_UNKNOWN, nullptr,
                           flags, levels, ARRAYSIZE(levels), D3D11_SDK_VERSION,
                           &device, nullptr, nullptr);
  }
  if (FAILED(hr)) {
    Log("stream texture: no D3D11 device at level 11 on %ls: %08lx",
        desc.Description, hr);
    return nullptr;
  }
  ComPtr<ID3D10Multithread> multithread;
  if (SUCCEEDED(device.As(&multithread))) {
    multithread->SetMultithreadProtected(TRUE);
  }
  Log("stream texture: device on %ls", desc.Description);
  return device;
}

StreamDraw::StreamDraw(ID3D11Device* device) : device_(device) {
  device_->GetImmediateContext(&context_);
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
  if (FAILED(hr)) {
    Log("stream texture: shaders: %08lx", hr);
    return false;
  }
  prepared_ = true;
  return true;
}

// The planes and the shared texture at the picture's size, made again only
// when it changes. The chroma planes are half the size each way, rounded up.
bool StreamDraw::Size(uint32_t width, uint32_t height) {
  if (out_ && width == width_ && height == height_) return true;
  out_.Reset();
  target_.Reset();
  handle_ = nullptr;
  width_ = height_ = 0;
  const uint32_t cw = (width + 1) / 2, ch = (height + 1) / 2;
  if (!Plane(device_.Get(), width, height, &planes_[0], &plane_views_[0]) ||
      !Plane(device_.Get(), cw, ch, &planes_[1], &plane_views_[1]) ||
      !Plane(device_.Get(), cw, ch, &planes_[2], &plane_views_[2])) {
    return false;
  }
  D3D11_TEXTURE2D_DESC desc = {};
  desc.Width = width;
  desc.Height = height;
  desc.MipLevels = desc.ArraySize = 1;
  desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  desc.SampleDesc.Count = 1;
  desc.Usage = D3D11_USAGE_DEFAULT;
  desc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
  // A legacy shared handle, which ANGLE opens as a pbuffer
  // (EGL_D3D_TEXTURE_2D_SHARE_HANDLE_ANGLE). No keyed mutex: the flush after
  // each draw orders it before Flutter's read (STEP3_WINDOWS.md).
  desc.MiscFlags = D3D11_RESOURCE_MISC_SHARED;
  ComPtr<ID3D11Texture2D> out;
  HRESULT hr = device_->CreateTexture2D(&desc, nullptr, &out);
  if (SUCCEEDED(hr)) hr = device_->CreateRenderTargetView(out.Get(), nullptr, &target_);
  ComPtr<IDXGIResource> resource;
  HANDLE handle = nullptr;
  if (SUCCEEDED(hr)) hr = out.As(&resource);
  if (SUCCEEDED(hr)) hr = resource->GetSharedHandle(&handle);
  if (FAILED(hr)) {
    Log("stream texture: texture %ux%u: %08lx", width, height, hr);
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
  if (p.kind != kInMemory || p.width == 0 || p.height == 0 || !p.y || !p.u ||
      !p.v) {
    return false;
  }
  if (device_->GetDeviceRemovedReason() != S_OK) return false;
  if (!Prepare() || !Size(p.width, p.height)) return false;

  context_->UpdateSubresource(planes_[0].Get(), 0, nullptr, p.y, p.stride_y, 0);
  context_->UpdateSubresource(planes_[1].Get(), 0, nullptr, p.u, p.stride_u, 0);
  context_->UpdateSubresource(planes_[2].Get(), 0, nullptr, p.v, p.stride_v, 0);
  SetColour(p.matrix, p.full_range);

  ID3D11RenderTargetView* target = target_.Get();
  context_->OMSetRenderTargets(1, &target, nullptr);
  context_->OMSetBlendState(nullptr, nullptr, 0xffffffff);
  context_->OMSetDepthStencilState(nullptr, 0);
  context_->RSSetState(nullptr);
  const D3D11_VIEWPORT viewport = {0, 0, float(p.width), float(p.height), 0, 1};
  context_->RSSetViewports(1, &viewport);
  context_->IASetInputLayout(nullptr);
  context_->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
  context_->VSSetShader(vertex_.Get(), nullptr, 0);
  context_->PSSetShader(pixel_.Get(), nullptr, 0);
  ID3D11ShaderResourceView* views[3] = {plane_views_[0].Get(),
                                        plane_views_[1].Get(),
                                        plane_views_[2].Get()};
  context_->PSSetShaderResources(0, 3, views);
  ID3D11SamplerState* sampler = sampler_.Get();
  context_->PSSetSamplers(0, 1, &sampler);
  ID3D11Buffer* colour = colour_.Get();
  context_->PSSetConstantBuffers(0, 1, &colour);
  context_->Draw(3, 0);
  // Out of the pipeline again, so nothing of ours stays bound between draws.
  ID3D11ShaderResourceView* none[3] = {};
  context_->PSSetShaderResources(0, 3, none);
  context_->OMSetRenderTargets(0, nullptr, nullptr);
  if (!Finish()) return false;
  return device_->GetDeviceRemovedReason() == S_OK;
}

// Flushes and waits for the GPU to finish the draw. ANGLE reads the texture on
// its own device, and a flush alone does not order that read after the draw:
// read back at once from a second device, the RTX gave 93 half-drawn pictures
// in 400 and the Iris Xe 2 stale ones; waiting first, none (STEP3_WINDOWS.md,
// Probe evidence). A fence with an event lets the thread sleep through the
// wait; without one (Windows 10 before 1703) an event query is polled.
bool StreamDraw::Finish() {
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
        Log("stream texture: no way to wait for a draw: %08lx", hr);
        return false;
      }
    }
  }
  if (fence_) {
    const uint64_t value = ++fenced_;
    context4_->Signal(fence_.Get(), value);
    context_->Flush();
    if (FAILED(fence_->SetEventOnCompletion(value, done_))) return false;
    // A removed device never signals: give up after a second.
    return WaitForSingleObject(done_, 1000) == WAIT_OBJECT_0;
  }
  context_->End(query_.Get());
  context_->Flush();
  const ULONGLONG give_up = GetTickCount64() + 1000;
  for (;;) {
    const HRESULT hr = context_->GetData(query_.Get(), nullptr, 0, 0);
    if (hr == S_OK) return true;
    if (hr != S_FALSE || GetTickCount64() > give_up) return false;
    SwitchToThread();
  }
}
