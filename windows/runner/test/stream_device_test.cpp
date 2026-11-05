// The runner's device found removed by whoever asks for it, not only by a
// draw that failed: a GPU decoder failing on a removed device draws nothing,
// and before this the next watch was made on the dead device, over and over.
// The device is a D3D11 one over D3D12 (D3D11On12), whose RemoveDevice removes
// this device alone, with no driver reset. D3D12 makes one device per adapter
// in a process, so each case runs in a process of its own. No Flutter. Built
// and run by run.ps1:
//   stream_device_test <adapter index> [case]
#include <d3d11.h>
#include <d3d11on12.h>
#include <d3d12.h>
#include <dxgi.h>
#include <windows.h>
#include <wrl/client.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#include "stream_device.h"
#include "stream_draw.h"

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

std::string logged;

void Log(const char* line) {
  std::printf("  log: %s\n", line);
  logged += line;
  logged += "\n";
}

int Count(const std::string& in, const char* what) {
  int n = 0;
  for (size_t at = in.find(what); at != std::string::npos;
       at = in.find(what, at + 1)) {
    n++;
  }
  return n;
}

// A device that can be removed on its own: D3D11 over a D3D12 device.
struct Removable {
  ComPtr<ID3D12Device> d3d12;
  ComPtr<ID3D12CommandQueue> queue;
  std::shared_ptr<Gpu> gpu = std::make_shared<Gpu>();

  explicit Removable(IDXGIAdapter1* adapter) {
    if (FAILED(D3D12CreateDevice(adapter, D3D_FEATURE_LEVEL_11_0,
                                 IID_PPV_ARGS(&d3d12)))) {
      return;
    }
    D3D12_COMMAND_QUEUE_DESC desc = {};
    desc.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
    if (FAILED(d3d12->CreateCommandQueue(&desc, IID_PPV_ARGS(&queue)))) return;
    IUnknown* queues[] = {queue.Get()};
    D3D11On12CreateDevice(d3d12.Get(), D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                          nullptr, 0, queues, 1, 0, &gpu->device, nullptr,
                          nullptr);
  }

  void Remove() {
    ComPtr<ID3D12Device5> five;
    if (SUCCEEDED(d3d12.As(&five))) five->RemoveDevice();
  }
};

void Release(ID3D11Device* device) {
  if (device != nullptr) device->Release();
}

// A removed device in use is let go when the next watch asks for one, though
// nothing drew on it: the next watch makes a new one.
void TheNextWatchLetsARemovedDeviceGo(IDXGIAdapter1* adapter) {
  std::printf("the next watch lets a removed device go\n");
  Removable removable(adapter);
  CHECK(removable.gpu->device != nullptr, "no D3D11On12 device");
  if (!removable.gpu->device) return;
  UseGpu(removable.gpu);
  CHECK(CurrentGpu() == removable.gpu, "the device in use is not the one used");
  ID3D11Device* lent = LendGpuDevice();
  CHECK(lent == removable.gpu->device.Get(), "the live device was not lent");
  Release(lent);

  logged.clear();
  removable.Remove();
  CHECK(removable.gpu->device->GetDeviceRemovedReason() != S_OK,
        "RemoveDevice did not remove the D3D11 device");
  CHECK(CurrentGpu() == nullptr, "a removed device is still the one in use");
  CHECK(removable.gpu->lost, "a removed device is not marked lost");
  CHECK(Count(logged, "the device was lost") == 1,
        "the loss was said %d times", Count(logged, "the device was lost"));
  CHECK(CurrentGpu() == nullptr, "asked again, a removed device came back");
  CHECK(Count(logged, "the device was lost") == 1, "the loss was said again");
}

// The decoder asks for the device and finds it removed: the export answers
// none and lets it go too, so a decoder that noticed first is enough.
void TheExportLetsARemovedDeviceGo(IDXGIAdapter1* adapter) {
  std::printf("the export lets a removed device go\n");
  Removable removable(adapter);
  CHECK(removable.gpu->device != nullptr, "no D3D11On12 device");
  if (!removable.gpu->device) return;
  UseGpu(removable.gpu);
  logged.clear();
  removable.Remove();
  ID3D11Device* lent = LendGpuDevice();
  CHECK(lent == nullptr, "a removed device was lent");
  Release(lent);
  CHECK(removable.gpu->lost, "the export did not let the removed device go");
  CHECK(Count(logged, "the device was lost") == 1,
        "the loss was said %d times", Count(logged, "the device was lost"));
}

// A device lost by a draw is not lent, nor in use.
void ADeviceLostByADrawIsNotLent(IDXGIAdapter1* adapter) {
  std::printf("a device lost by a draw is not lent\n");
  Removable removable(adapter);
  CHECK(removable.gpu->device != nullptr, "no D3D11On12 device");
  if (!removable.gpu->device) return;
  UseGpu(removable.gpu);
  LoseGpu(removable.gpu.get(), DXGI_ERROR_DEVICE_REMOVED);
  CHECK(CurrentGpu() == nullptr, "a lost device is still in use");
  ID3D11Device* lent = LendGpuDevice();
  CHECK(lent == nullptr, "a lost device was lent");
  Release(lent);
}

using Case = void (*)(IDXGIAdapter1*);
struct Named {
  const char* name;
  Case run;
};
constexpr Named kCases[] = {
    {"next-watch", TheNextWatchLetsARemovedDeviceGo},
    {"export", TheExportLetsARemovedDeviceGo},
    {"draw", ADeviceLostByADrawIsNotLent},
};

// Runs this program again for |name|, answering whether it passed.
bool RunApart(const char* adapter, const char* name) {
  wchar_t self[MAX_PATH];
  GetModuleFileNameW(nullptr, self, MAX_PATH);
  std::wstring line = L"\"" + std::wstring(self) + L"\" ";
  for (const char* c = adapter; *c; c++) line += wchar_t(*c);
  line += L" ";
  for (const char* c = name; *c; c++) line += wchar_t(*c);
  STARTUPINFOW start = {sizeof start};
  PROCESS_INFORMATION process = {};
  if (!CreateProcessW(nullptr, line.data(), nullptr, nullptr, FALSE, 0,
                      nullptr, nullptr, &start, &process)) {
    std::printf("FAIL: could not run case %s\n", name);
    return false;
  }
  WaitForSingleObject(process.hProcess, INFINITE);
  DWORD code = 1;
  GetExitCodeProcess(process.hProcess, &code);
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return code == 0;
}

}  // namespace

int main(int argc, char** argv) {
  std::setvbuf(stdout, nullptr, _IONBF, 0);
  const char* index_arg = argc > 1 ? argv[1] : "0";
  if (argc <= 2) {
    int failed = 0;
    for (const Named& c : kCases) failed += RunApart(index_arg, c.name) ? 0 : 1;
    std::printf(failed ? "FAILED: %d case(s)\n" : "all passed\n", failed);
    return failed ? 1 : 0;
  }
  SetStreamLog(Log);
  const UINT index = UINT(std::atoi(index_arg));
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
  for (const Named& c : kCases) {
    if (std::strcmp(c.name, argv[2]) == 0) c.run(adapter.Get());
  }
  UseGpu(nullptr);
  if (failures) std::printf("FAILED: %d\n", failures);
  return failures ? 1 : 0;
}
