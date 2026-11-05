#ifndef RUNNER_STREAM_DEVICE_H_
#define RUNNER_STREAM_DEVICE_H_

// The runner's device for watched shares (stream_texture.h): one for the
// process, made on the first `create` and shared by every texture made on it
// and by Rust's GPU decoder, which takes it through `rift_stream_d3d11_device`.
// No Flutter here, so test/stream_device_test.cpp can drive it alone.

#include <d3d11.h>
#include <windows.h>
#include <wrl/client.h>

#include <atomic>
#include <memory>

// The device, and the black picture shown before a share's first. A lost one
// stays alive, unused, until the last texture made on it is let go.
struct Gpu {
  Microsoft::WRL::ComPtr<ID3D11Device> device;
  Microsoft::WRL::ComPtr<ID3D11Texture2D> black;
  HANDLE black_handle = nullptr;
  std::atomic<bool> lost{false};
  // Rust decodes on the GPU on adapter 0 (rust/src/watching/decode/
  // windows.rs), and on this device: it can draw those pictures only when
  // this is that adapter, with a video device.
  bool takes_gpu_pictures = false;
};

// The device in use, or null when there is none. One found removed is let go
// first (LoseGpu), whoever noticed: a decoder failing on it draws nothing, so
// the draw never would, and the next watch makes a new one.
std::shared_ptr<Gpu> CurrentGpu();

// |gpu| becomes the device in use.
void UseGpu(std::shared_ptr<Gpu> gpu);

// The device is gone, a reset or a driver update: said once, and no new
// texture is made on it.
void LoseGpu(Gpu* gpu, HRESULT reason);

// What `rift_stream_d3d11_device` answers: the device in use with a reference
// added for the caller, or null.
ID3D11Device* LendGpuDevice();

#endif  // RUNNER_STREAM_DEVICE_H_
