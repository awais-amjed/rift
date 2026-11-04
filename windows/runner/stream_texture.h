#ifndef RUNNER_STREAM_TEXTURE_H_
#define RUNNER_STREAM_TEXTURE_H_

#include <d3d11.h>

#include <flutter/encodable_value.h>
#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>

#include <memory>

// A watched share's picture, drawn on the GPU into a texture Flutter shows
// (`Texture` in Dart), as linux/runner/stream_texture.cc does with GL.
//
// The Rust library receives the share on its own connection
// (rust/src/watching) and keeps the newest picture. When one arrives it calls
// the mark function this gives Dart, and Flutter asks for the texture on its
// next frame: on the raster thread, the descriptor callback borrows the
// picture through Rust's lock and unlock (`rift_watch_frame_lock`, whose
// addresses Dart hands over on `create`), draws it into a shared D3D11
// texture with a YUV-to-RGB shader (stream_draw.h), waits for the GPU, and
// answers the texture's DXGI handle, which ANGLE opens on its own device
// (docs/gpu-codecs/STEP3_WINDOWS.md).
//
// The device is the runner's, one for the process, made on the first `create`
// on the adapter Flutter draws with. When it is lost, each picture is handed
// back undrawn, which sends the share back to the call's connection, and the
// next `create` makes a new one.
//
// The `rift/stream_texture` channel: `create` {lock, unlock} answers
// {textureId, mark, takesGpuPictures}; `dispose` {textureId} lets one go,
// after Rust has stopped marking it.
namespace rift {

class StreamTextures {
 public:
  // Opens the channel on |engine|'s messenger.
  explicit StreamTextures(flutter::FlutterEngine* engine);
  // Closes it. Marks from Rust after this find nothing.
  ~StreamTextures();
  StreamTextures(const StreamTextures&) = delete;
  StreamTextures& operator=(const StreamTextures&) = delete;

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

}  // namespace rift

// The runner's device, with a reference added for the caller to release, or
// null when there is none yet or it was lost. Rust finds it among the
// executable's exports when it opens a share's decoder on the GPU.
extern "C" __declspec(dllexport) ID3D11Device* rift_stream_d3d11_device();

#endif  // RUNNER_STREAM_TEXTURE_H_
