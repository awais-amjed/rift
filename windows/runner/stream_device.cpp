#include "stream_device.h"

#include <mutex>

#include "stream_draw.h"

namespace {

std::mutex gpu_mutex;
std::shared_ptr<Gpu> current;

}  // namespace

std::shared_ptr<Gpu> CurrentGpu() {
  std::shared_ptr<Gpu> gpu;
  {
    std::lock_guard<std::mutex> hold(gpu_mutex);
    gpu = current;
  }
  if (!gpu || gpu->lost) return nullptr;
  const HRESULT reason = gpu->device->GetDeviceRemovedReason();
  if (reason != S_OK) {
    LoseGpu(gpu.get(), reason);
    return nullptr;
  }
  return gpu;
}

void UseGpu(std::shared_ptr<Gpu> gpu) {
  std::lock_guard<std::mutex> hold(gpu_mutex);
  current = std::move(gpu);
}

void LoseGpu(Gpu* gpu, HRESULT reason) {
  if (gpu->lost.exchange(true)) return;
  StreamLog(
      "stream texture: the device was lost (%08lx); watching goes back to "
      "the call, and the next watch makes a new device",
      reason);
  std::lock_guard<std::mutex> hold(gpu_mutex);
  if (current.get() == gpu) current.reset();
}

ID3D11Device* LendGpuDevice() {
  std::shared_ptr<Gpu> gpu = CurrentGpu();
  if (!gpu) return nullptr;
  gpu->device->AddRef();
  return gpu->device.Get();
}
