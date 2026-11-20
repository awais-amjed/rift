#ifndef RUNNER_GPU_WATCH_H_
#define RUNNER_GPU_WATCH_H_

// Hears the GPU Flutter draws with being reset or removed, which Flutter
// itself never recovers from.
//
// A game that crashes the graphics driver, or closes badly enough that
// Windows resets it (TDR), takes every Direct3D device on that GPU with it.
// Rift's own devices notice and start again, but Flutter's renderer (ANGLE
// over D3D11) only logs "Context Lost" and keeps drawing on the dead one, so
// the window stays white while the call goes on underneath (report 03008880,
// Nov 18 2026, closing a game on an RTX 4060). Nothing outside the engine can
// make it a new one. So the runner keeps a device of its own on Flutter's
// adapter, which the same reset removes, and asks Windows to signal when it
// goes; Dart then restarts Rift (GpuResetListener).

#include <d3d11.h>
#include <d3d11_4.h>
#include <windows.h>
#include <wrl/client.h>

// Posted to the window once the watched device is gone, with the tick
// (GetTickCount64) Windows signalled it at in its LPARAM, so the log can say
// how long the window took to hear it.
static constexpr UINT kWmGpuLost = WM_APP + 103;

class GpuWatch {
 public:
  // A small device on |adapter|, made for watching and nothing else; null
  // when none can be made.
  static Microsoft::WRL::ComPtr<ID3D11Device> MakeDevice(IDXGIAdapter* adapter);

  // Watches |device|, posting kWmGpuLost to |window| once Windows removes it.
  GpuWatch(HWND window, Microsoft::WRL::ComPtr<ID3D11Device> device);
  ~GpuWatch();

  GpuWatch(const GpuWatch&) = delete;
  GpuWatch& operator=(const GpuWatch&) = delete;

  // Whether Windows signals the removal (ID3D11Device4, Windows 10 1607 and
  // later). Without it, the loss is found only when Reason is asked.
  bool listening() const { return wait_ != nullptr; }

  // S_OK while the device is alive; once it is gone, why.
  HRESULT Reason() const;

 private:
  static void CALLBACK OnRemoved(PVOID window, BOOLEAN timed_out);

  Microsoft::WRL::ComPtr<ID3D11Device> device_;
  Microsoft::WRL::ComPtr<ID3D11Device4> device4_;
  HANDLE event_ = nullptr;
  HANDLE wait_ = nullptr;
  DWORD cookie_ = 0;
  bool registered_ = false;
};

#endif  // RUNNER_GPU_WATCH_H_
