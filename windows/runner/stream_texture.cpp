#include "stream_texture.h"

#include <dxgi.h>
#include <flutter/standard_method_codec.h>
#include <flutter_plugin_registrar.h>
#include <flutter_texture_registrar.h>
#include <flutter_windows.h>
#include <windows.h>
#include <wrl/client.h>

#include <atomic>
#include <cstdint>
#include <cstdlib>
#include <map>
#include <mutex>
#include <optional>

#include "stream_device.h"
#include "stream_draw.h"

using Microsoft::WRL::ComPtr;

namespace {

using LockFn = int32_t (*)(uint64_t, WatchPlanes*);
// |drawn| is 0 when a picture could not be drawn, which gives up on drawing
// the share here (rust/src/watching/frames.rs).
using UnlockFn = void (*)(uint64_t, int32_t drawn);

// One watched share's texture. Made on the platform thread; drawn, and freed,
// on the raster thread.
struct Stream {
  Stream(LockFn lock_fn, UnlockFn unlock_fn, std::shared_ptr<Gpu> on)
      : lock(lock_fn), unlock(unlock_fn), gpu(on), draw(on->device.Get()) {}
  LockFn lock;
  UnlockFn unlock;
  std::shared_ptr<Gpu> gpu;
  StreamDraw draw;
  int64_t id = -1;
  FlutterDesktopGpuSurfaceDescriptor descriptor = {};
};

FlutterDesktopPluginRegistrarRef plugin = nullptr;
FlutterDesktopTextureRegistrarRef registrar = nullptr;

// The textures Rust may mark, by id. A texture leaves before it is let go, so
// a mark that finds nothing is a share already stopped.
std::mutex live_mutex;
std::map<int64_t, Stream*> live;

// The app's log: Rust's (rust/src/logging.rs), found in its library by name
// once Dart has loaded it, which is before the first `create`. The
// debugger's output until then.
void AppLog(const char* line) {
  using LogFn = void (*)(const char*);
  static std::atomic<LogFn> log{nullptr};
  LogFn found = log.load();
  if (found == nullptr) {
    HMODULE rust = GetModuleHandleW(L"rust_lib_rift.dll");
    if (rust != nullptr) {
      found = reinterpret_cast<LogFn>(GetProcAddress(rust, "rift_runner_log"));
      log.store(found);
    }
  }
  if (found != nullptr) {
    found(line);
  } else {
    OutputDebugStringA(line);
    OutputDebugStringA("\n");
  }
}

// A black pixel, shared like a picture, for a texture with none yet.
void MakeBlack(Gpu* gpu) {
  const uint8_t pixel[4] = {0, 0, 0, 255};
  D3D11_TEXTURE2D_DESC desc = {};
  desc.Width = desc.Height = 1;
  desc.MipLevels = desc.ArraySize = 1;
  desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  desc.SampleDesc.Count = 1;
  desc.Usage = D3D11_USAGE_DEFAULT;
  // ANGLE binds a shared texture as a render target and a shader resource.
  desc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
  desc.MiscFlags = D3D11_RESOURCE_MISC_SHARED;
  const D3D11_SUBRESOURCE_DATA data = {pixel, 4, 4};
  ComPtr<IDXGIResource> resource;
  HRESULT hr = gpu->device->CreateTexture2D(&desc, &data, &gpu->black);
  if (SUCCEEDED(hr)) hr = gpu->black.As(&resource);
  if (SUCCEEDED(hr)) hr = resource->GetSharedHandle(&gpu->black_handle);
  if (FAILED(hr)) {
    StreamLog("stream texture: no black picture: %08lx", hr);
    gpu->black.Reset();
    gpu->black_handle = nullptr;
  }
}

// Whether |device|, on the adapter with |luid|, can draw what Rust decodes on
// the GPU: Rust chose adapter 0, the one Flutter takes when Rift names no GPU,
// and decodes on this device, which needs video support for that.
bool TakesGpuPictures(ID3D11Device* device, LUID luid) {
  ComPtr<IDXGIFactory1> factory;
  ComPtr<IDXGIAdapter1> first;
  DXGI_ADAPTER_DESC1 desc = {};
  if (FAILED(CreateDXGIFactory1(IID_PPV_ARGS(&factory))) ||
      factory->EnumAdapters1(0, &first) != S_OK ||
      FAILED(first->GetDesc1(&desc))) {
    return false;
  }
  if (desc.AdapterLuid.LowPart != luid.LowPart ||
      desc.AdapterLuid.HighPart != luid.HighPart) {
    StreamLog("stream texture: Flutter draws on another adapter than %ls; "
              "shares are decoded the call's way",
              desc.Description);
    return false;
  }
  ComPtr<ID3D11VideoDevice> video;
  return SUCCEEDED(device->QueryInterface(IID_PPV_ARGS(&video)));
}

// The device new textures are made on: the one there is, unless it was
// removed, or a new one on the adapter Flutter draws with, matched by LUID.
// Null when none can be made; the share is then watched through the call.
// Platform thread.
std::shared_ptr<Gpu> Device() {
  if (std::shared_ptr<Gpu> gpu = CurrentGpu()) return gpu;
  IDXGIAdapter* adapter = nullptr;
  if (!FlutterDesktopPluginRegistrarGetGraphicsAdapter(plugin, &adapter) ||
      adapter == nullptr) {
    StreamLog("stream texture: Flutter named no adapter");
    return nullptr;
  }
  DXGI_ADAPTER_DESC desc = {};
  const HRESULT hr = adapter->GetDesc(&desc);
  adapter->Release();
  if (FAILED(hr)) {
    StreamLog("stream texture: Flutter's adapter: %08lx", hr);
    return nullptr;
  }
  auto gpu = std::make_shared<Gpu>();
  gpu->device = MakeDevice(desc.AdapterLuid);
  if (!gpu->device) return nullptr;
  MakeBlack(gpu.get());
  gpu->takes_gpu_pictures = TakesGpuPictures(gpu->device.Get(), desc.AdapterLuid);
  UseGpu(gpu);
  return gpu;
}

#ifdef _DEBUG
// RIFT_STREAM_TEXTURE_FAIL_AFTER=<n>: the picture after the n-th drawn in
// the process finds its device removed, once. Debug builds only, never a
// release: a test of what device loss does (the plan's Task 6).
bool FailsForTest() {
  static const long after = [] {
    char value[32] = {};
    const DWORD length = GetEnvironmentVariableA(
        "RIFT_STREAM_TEXTURE_FAIL_AFTER", value, sizeof value);
    return length > 0 && length < sizeof value ? std::strtol(value, nullptr, 10)
                                               : 0L;
  }();
  static long drawn = 0;  // the raster thread's alone
  return after > 0 && ++drawn == after + 1;
}
#endif

// Flutter's raster thread asks for the picture. A new one from Rust is
// drawn first and handed back; then the texture is answered, or the black
// pixel before the first picture. Null once the device is lost, which shows
// nothing until Dart has the call's renderer there instead.
const FlutterDesktopGpuSurfaceDescriptor* Obtain(size_t, size_t,
                                                 void* user_data) {
  Stream* self = static_cast<Stream*>(user_data);
  Gpu* gpu = self->gpu.get();
  WatchPlanes planes = {};
  if (self->lock(static_cast<uint64_t>(self->id), &planes) == 1) {
    bool drawn = !gpu->lost && self->draw.Draw(planes);
#ifdef _DEBUG
    if (drawn && FailsForTest()) {
      drawn = false;
      LoseGpu(gpu, DXGI_ERROR_DEVICE_REMOVED);
    }
#endif
    if (!drawn && !gpu->lost) {
      const HRESULT reason = gpu->device->GetDeviceRemovedReason();
      if (reason != S_OK) LoseGpu(gpu, reason);
    }
    self->unlock(static_cast<uint64_t>(self->id), drawn ? 1 : 0);
  }
  if (gpu->lost) return nullptr;
  HANDLE handle = self->draw.handle();
  size_t width = self->draw.width(), height = self->draw.height();
  if (handle == nullptr) {
    handle = gpu->black_handle;
    width = height = 1;
  }
  if (handle == nullptr) return nullptr;
  FlutterDesktopGpuSurfaceDescriptor& d = self->descriptor;
  d.struct_size = sizeof d;
  d.handle = handle;
  d.width = d.visible_width = width;
  d.height = d.visible_height = height;
  d.format = kFlutterDesktopPixelFormatBGRA8888;
  d.release_callback = nullptr;
  d.release_context = nullptr;
  return &d;
}

// Rust's "a new picture is waiting" for texture |id|, from its own thread.
// The engine posts it to the platform thread.
extern "C" void rift_stream_texture_mark(uint64_t id) {
  std::lock_guard<std::mutex> hold(live_mutex);
  if (registrar != nullptr && live.count(static_cast<int64_t>(id)) != 0) {
    FlutterDesktopTextureRegistrarMarkExternalTextureFrameAvailable(
        registrar, static_cast<int64_t>(id));
  }
}

std::optional<int64_t> Int(const flutter::EncodableMap& args,
                           const char* name) {
  auto found = args.find(flutter::EncodableValue(name));
  if (found == args.end()) return std::nullopt;
  return found->second.TryGetLongValue();
}

using Result = std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>;

void Create(const flutter::EncodableMap& args, Result result) {
  const std::optional<int64_t> lock = Int(args, "lock");
  const std::optional<int64_t> unlock = Int(args, "unlock");
  if (!lock || !unlock || *lock == 0 || *unlock == 0) {
    result->Error("bad-args", "create needs Rust's lock and unlock");
    return;
  }
  std::shared_ptr<Gpu> gpu = Device();
  if (!gpu) {
    result->Error("no-device", "no D3D11 device on Flutter's adapter");
    return;
  }
  auto stream = new Stream(reinterpret_cast<LockFn>(*lock),
                           reinterpret_cast<UnlockFn>(*unlock), gpu);
  FlutterDesktopTextureInfo info = {};
  info.type = kFlutterDesktopGpuSurfaceTexture;
  info.gpu_surface_config.struct_size = sizeof info.gpu_surface_config;
  info.gpu_surface_config.type = kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle;
  info.gpu_surface_config.callback = Obtain;
  info.gpu_surface_config.user_data = stream;
  // Its id is set before Dart hears it, and Flutter asks for a texture only
  // once a widget in Dart shows that id.
  const int64_t id =
      FlutterDesktopTextureRegistrarRegisterExternalTexture(registrar, &info);
  if (id < 0) {
    delete stream;
    result->Error("register", "Flutter refused the texture");
    return;
  }
  stream->id = id;
  {
    std::lock_guard<std::mutex> hold(live_mutex);
    live[id] = stream;
  }
  result->Success(flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("textureId"), flutter::EncodableValue(id)},
      {flutter::EncodableValue("mark"),
       flutter::EncodableValue(static_cast<int64_t>(
           reinterpret_cast<intptr_t>(&rift_stream_texture_mark)))},
      {flutter::EncodableValue("takesGpuPictures"),
       flutter::EncodableValue(gpu->takes_gpu_pictures)},
  }));
}

// Out of the live map first, so Rust's marks find nothing; then the engine
// lets go of its own hold (ANGLE's surface on the texture) on the raster
// thread, where it also draws, and only after that is the texture freed,
// there. An engine that is stopping, and draws no more, calls back at once
// on this thread instead (flutter_windows_texture_registrar.cc, 3.47.7).
void Dispose(const flutter::EncodableMap& args, Result result) {
  const std::optional<int64_t> id = Int(args, "textureId");
  if (!id) {
    result->Error("bad-args", "dispose needs a textureId");
    return;
  }
  Stream* stream = nullptr;
  {
    std::lock_guard<std::mutex> hold(live_mutex);
    auto found = live.find(*id);
    if (found != live.end()) {
      stream = found->second;
      live.erase(found);
    }
  }
  if (stream != nullptr) {
    FlutterDesktopTextureRegistrarUnregisterExternalTexture(
        registrar, *id,
        [](void* gone) { delete static_cast<Stream*>(gone); }, stream);
  }
  result->Success();
}

}  // namespace

extern "C" __declspec(dllexport) ID3D11Device* rift_stream_d3d11_device() {
  return LendGpuDevice();
}

namespace rift {

StreamTextures::StreamTextures(flutter::FlutterEngine* engine) {
  SetStreamLog(AppLog);
  plugin = engine->GetRegistrarForPlugin("RiftStreamTexture");
  {
    std::lock_guard<std::mutex> hold(live_mutex);
    registrar = FlutterDesktopRegistrarGetTextureRegistrar(plugin);
  }
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      engine->messenger(), "rift/stream_texture",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         Result result) {
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        if (args == nullptr) {
          result->Error("bad-args", "expected a map");
        } else if (call.method_name() == "create") {
          Create(*args, std::move(result));
        } else if (call.method_name() == "dispose") {
          Dispose(*args, std::move(result));
        } else {
          result->NotImplemented();
        }
      });
}

// The engine goes next, and its texture registrar with it. A texture still
// registered is not freed: the raster thread may be drawing it.
StreamTextures::~StreamTextures() {
  channel_->SetMethodCallHandler(nullptr);
  channel_ = nullptr;
  std::lock_guard<std::mutex> hold(live_mutex);
  live.clear();
  registrar = nullptr;
}

}  // namespace rift
