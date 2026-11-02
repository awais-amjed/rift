#ifndef RUNNER_STREAM_TEXTURE_H_
#define RUNNER_STREAM_TEXTURE_H_

#include <flutter_linux/flutter_linux.h>

// A watched share's picture, drawn by a shader on the GPU into a texture
// Flutter shows (`Texture` in Dart).
//
// The Rust library receives the share on its own connection
// (rust/src/watching) and keeps the newest picture: three I420 planes in
// libwebrtc's decoder's own buffer, or a picture decoded on the GPU. When one
// arrives it calls the mark function this gives Dart, and Flutter asks for
// the texture on its next frame: `populate`, on the raster thread with
// Flutter's GL context current, borrows the picture through Rust's lock and
// unlock (`rift_watch_frame_lock`, whose addresses Dart hands over on
// `create`) and draws it through a YUV-to-RGB shader. I420's planes are
// uploaded as one-byte textures; Intel's and AMD's pictures are imported
// where they lie, as DMA-BUFs; NVIDIA's are copied by CUDA into textures of
// ours on the GPU. The picture never becomes RGBA on the CPU, which is what
// flutter_webrtc's renderer did for every frame
// (docs/gpu-codecs/STEP3_PLAN.md). A GPU picture that cannot be drawn is
// handed back saying so, and the app watches through the call instead.
//
// The `rift/stream_texture` channel: `create` {lock, unlock} answers
// {textureId, mark}; `dispose` {textureId} lets one go, after Rust has
// stopped marking it.
namespace rift {

// Opens the channel on |view|'s engine.
void InstallStreamTextures(FlView* view);

}  // namespace rift

#endif  // RUNNER_STREAM_TEXTURE_H_
