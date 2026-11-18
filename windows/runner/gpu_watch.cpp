#include "gpu_watch.h"

#include <utility>

using Microsoft::WRL::ComPtr;

ComPtr<ID3D11Device> GpuWatch::MakeDevice(IDXGIAdapter* adapter) {
  if (adapter == nullptr) return nullptr;
  ComPtr<ID3D11Device> device;
  // Nothing is drawn on it: it is there to be removed with Flutter's.
  if (FAILED(D3D11CreateDevice(adapter, D3D_DRIVER_TYPE_UNKNOWN, nullptr, 0,
                               nullptr, 0, D3D11_SDK_VERSION, &device, nullptr,
                               nullptr))) {
    return nullptr;
  }
  return device;
}

GpuWatch::GpuWatch(HWND window, ComPtr<ID3D11Device> device)
    : device_(std::move(device)) {
  if (!device_ || FAILED(device_.As(&device4_))) return;
  event_ = ::CreateEventW(nullptr, FALSE, FALSE, nullptr);
  if (event_ == nullptr) return;
  registered_ = SUCCEEDED(device4_->RegisterDeviceRemovedEvent(event_, &cookie_));
  if (!registered_) return;
  // Once: a device removed stays removed.
  ::RegisterWaitForSingleObject(&wait_, event_, OnRemoved, window, INFINITE,
                                WT_EXECUTEONLYONCE);
}

GpuWatch::~GpuWatch() {
  // Waits for a callback in flight, so none posts after this.
  if (wait_ != nullptr) ::UnregisterWaitEx(wait_, INVALID_HANDLE_VALUE);
  if (registered_) device4_->UnregisterDeviceRemoved(cookie_);
  if (event_ != nullptr) ::CloseHandle(event_);
}

HRESULT GpuWatch::Reason() const {
  return device_ ? device_->GetDeviceRemovedReason() : S_OK;
}

void CALLBACK GpuWatch::OnRemoved(PVOID window, BOOLEAN /*timed_out*/) {
  ::PostMessageW(static_cast<HWND>(window), kWmGpuLost, 0, 0);
}
