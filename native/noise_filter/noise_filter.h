#ifndef RIFT_NOISE_FILTER_NOISE_FILTER_H_
#define RIFT_NOISE_FILTER_NOISE_FILTER_H_

#include <stdint.h>

#if defined(_WIN32)
#define RIFT_NOISE_FILTER_EXPORT extern "C" __declspec(dllexport)
#else
#define RIFT_NOISE_FILTER_EXPORT \
  extern "C" __attribute__((visibility("default")))
#endif

namespace rift {

// Puts a noise model — RNNoise, or DeepFilterNet from the Rust library — and
// the mic volume into libwebrtc's processing of the microphone, after its own
// echo cancellation, noise suppression and gain control. Off until Dart picks
// one. Call once, after the plugins are registered: flutter_webrtc makes its
// one peer connection factory, and with it the audio processing every capture
// track goes through, as it registers.
//
// Returns false, and the filter stays unavailable, when there is no factory.
bool InstallNoiseFilter();

}  // namespace rift

// Looked up by Dart through dart:ffi in the executable (NoiseFilter), which is
// why these are exported from it.

// 1 when InstallNoiseFilter succeeded.
RIFT_NOISE_FILTER_EXPORT int32_t rift_noise_filter_available(void);

// Which model filters every capture track, from the next 10 ms: 0 for none,
// 1 for RNNoise, 2 for DeepFilterNet. Anything else is treated as none, and
// DeepFilterNet as none until rift_noise_filter_set_deep_filter.
RIFT_NOISE_FILTER_EXPORT void rift_noise_filter_set_model(int32_t model);

// The mic volume, as a gain on every capture track, after the model: 1 as it
// is, below 1 quieter, above 1 louder with the peaks limited rather than cut.
RIFT_NOISE_FILTER_EXPORT void rift_noise_filter_set_gain(float gain);

// Where DeepFilterNet is, once the Rust library has loaded it: its
// rift_deep_filter_process and rift_deep_filter_reset (rust/src/deep_filter.rs).
// The runner does not link that library, so Dart passes the addresses on.
RIFT_NOISE_FILTER_EXPORT void rift_noise_filter_set_deep_filter(void* process,
                                                                void* reset);

#endif  // RIFT_NOISE_FILTER_NOISE_FILTER_H_
