// The runner hears the GPU Flutter draws with go (gpu_watch.h), which is how
// Rift knows to restart when a driver reset leaves its window white. The
// device is a D3D11 one over D3D12 (D3D11On12), whose RemoveDevice removes it
// alone, with no driver reset. No Flutter. Built and run by run.ps1:
//   gpu_watch_test <adapter index>
#include <d3d11.h>
#include <d3d11on12.h>
#include <d3d12.h>
#include <dxgi.h>
#include <windows.h>
#include <wrl/client.h>

#include <cstdio>
#include <cstdlib>

#include "gpu_watch.h"
#include "relaunch.h"

using Microsoft::WRL::ComPtr;

namespace {

int failures = 0;

#define CHECK(cond, ...)                                          \
  do {                                                            \
    if (!(cond)) {                                                \
      std::printf("FAIL %s:%d: %s: ", __FILE__, __LINE__, #cond); \
      std::printf(__VA_ARGS__);                                   \
      std::printf("\n");                                          \
      failures++;                                                 \
    }                                                             \
  } while (0)

// A window that only receives messages, standing in for Rift's.
HWND MessageWindow() {
  return CreateWindowExW(0, L"STATIC", L"", 0, 0, 0, 0, 0, HWND_MESSAGE,
                         nullptr, nullptr, nullptr);
}

// Whether kWmGpuLost reaches |window| within |ms|.
bool Hears(HWND window, DWORD ms) {
  const ULONGLONG until = GetTickCount64() + ms;
  while (GetTickCount64() < until) {
    MSG msg;
    if (PeekMessageW(&msg, window, kWmGpuLost, kWmGpuLost, PM_REMOVE)) {
      return true;
    }
    MsgWaitForMultipleObjects(0, nullptr, FALSE, 20, QS_POSTMESSAGE);
  }
  return false;
}

// A device that can be removed on its own: D3D11 over a D3D12 device.
struct Removable {
  ComPtr<ID3D12Device> d3d12;
  ComPtr<ID3D12CommandQueue> queue;
  ComPtr<ID3D11Device> device;

  explicit Removable(IDXGIAdapter1* adapter) {
    if (FAILED(D3D12CreateDevice(adapter, D3D_FEATURE_LEVEL_11_0,
                                 IID_PPV_ARGS(&d3d12)))) {
      return;
    }
    D3D12_COMMAND_QUEUE_DESC desc = {};
    desc.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
    if (FAILED(d3d12->CreateCommandQueue(&desc, IID_PPV_ARGS(&queue)))) return;
    IUnknown* queues[] = {queue.Get()};
    D3D11On12CreateDevice(d3d12.Get(), 0, nullptr, 0, queues, 1, 0, &device,
                          nullptr, nullptr);
  }

  void Remove() {
    ComPtr<ID3D12Device5> five;
    if (SUCCEEDED(d3d12.As(&five))) five->RemoveDevice();
  }
};

void AWatchDeviceIsMade(IDXGIAdapter1* adapter) {
  std::printf("a device to watch is made on the adapter\n");
  CHECK(GpuWatch::MakeDevice(adapter) != nullptr, "no device");
  CHECK(GpuWatch::MakeDevice(nullptr) == nullptr, "a device with no adapter");
}

void ALiveDeviceSaysNothing(IDXGIAdapter1* adapter) {
  std::printf("a live device says nothing\n");
  HWND window = MessageWindow();
  GpuWatch watch(window, GpuWatch::MakeDevice(adapter));
  CHECK(watch.listening(), "Windows does not signal removal here");
  CHECK(watch.Reason() == S_OK, "a new device reads removed: %08lx",
        watch.Reason());
  CHECK(!Hears(window, 300), "a live device was said lost");
  DestroyWindow(window);
}

void ARemovedDeviceIsSaid(IDXGIAdapter1* adapter) {
  std::printf("a removed device is said, once\n");
  Removable removable(adapter);
  CHECK(removable.device != nullptr, "no D3D11On12 device");
  if (!removable.device) return;
  HWND window = MessageWindow();
  GpuWatch watch(window, removable.device);
  if (!watch.listening()) {
    // D3D11On12 may not signal; then only the asked-for reason is checked.
    std::printf("  (D3D11On12 does not signal removal; Reason only)\n");
  }
  removable.Remove();
  CHECK(watch.Reason() != S_OK, "the removed device reads alive");
  if (watch.listening()) {
    CHECK(Hears(window, 2000), "the removal was not posted");
    CHECK(!Hears(window, 300), "the removal was posted twice");
  }
  DestroyWindow(window);
}

void AWatchGoneSaysNothing(IDXGIAdapter1* adapter) {
  std::printf("a watch let go says nothing after\n");
  Removable removable(adapter);
  if (!removable.device) return;
  HWND window = MessageWindow();
  { GpuWatch watch(window, removable.device); }
  removable.Remove();
  CHECK(!Hears(window, 500), "a watch let go still posted");
  DestroyWindow(window);
}

void TheRunnerKeepsItsFlagFromDart() {
  std::printf("the runner's argument is kept from Dart\n");
  CHECK(IsRunnerArgument("--after-exit=1234"), "the handle reached Dart");
  CHECK(!IsRunnerArgument("--after-gpu-reset"), "Dart lost the reason");
  CHECK(!IsRunnerArgument("--minimized"), "Dart lost --minimized");
}

}  // namespace

int main(int argc, char** argv) {
  std::setvbuf(stdout, nullptr, _IONBF, 0);
  const UINT index = UINT(std::atoi(argc > 1 ? argv[1] : "0"));
  ComPtr<IDXGIFactory1> factory;
  ComPtr<IDXGIAdapter1> adapter;
  DXGI_ADAPTER_DESC1 desc = {};
  if (FAILED(CreateDXGIFactory1(IID_PPV_ARGS(&factory))) ||
      factory->EnumAdapters1(index, &adapter) != S_OK) {
    std::printf("FAIL: no adapter %u\n", index);
    return 1;
  }
  adapter->GetDesc1(&desc);
  std::printf("adapter %u: %ls\n", index, desc.Description);
  AWatchDeviceIsMade(adapter.Get());
  ALiveDeviceSaysNothing(adapter.Get());
  // D3D12 makes one device per adapter in a process, so each removal case
  // gets its own adapter's device after the last one was removed: run apart.
  if (argc > 2 && std::atoi(argv[2]) == 2) {
    AWatchGoneSaysNothing(adapter.Get());
  } else {
    ARemovedDeviceIsSaid(adapter.Get());
  }
  TheRunnerKeepsItsFlagFromDart();
  std::printf(failures ? "FAILED: %d\n" : "all passed\n", failures);
  return failures ? 1 : 0;
}
