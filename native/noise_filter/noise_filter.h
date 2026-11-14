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

// Puts a noise model — RNNoise, or DPDFNet from the Rust library — and the mic volume into libwebrtc's processing of the microphone,
// after its own echo cancellation, noise suppression and gain control. Off
// until Dart picks one. Call once, after the plugins are registered:
// flutter_webrtc makes its one peer connection factory, and with it the audio
// processing every capture track goes through, as it registers.
//
// Returns false, and the filter stays unavailable, when there is no factory.
bool InstallNoiseFilter();

}  // namespace rift

// Looked up by Dart through dart:ffi in the executable (NoiseFilter), which is
// why these are exported from it.

// 1 when InstallNoiseFilter succeeded.
RIFT_NOISE_FILTER_EXPORT int32_t rift_noise_filter_available(void);

// Which model filters every capture track, from the next 10 ms: 0 for none,
// 1 for RNNoise, 3 for DPDFNet (2 was DeepFilterNet). Anything else is
// treated as none, RNNoise as none until rift_noise_filter_set_rnnoise has
// loaded its weights, and DPDFNet as none until rift_noise_filter_set_dpdfnet
// has been called.
RIFT_NOISE_FILTER_EXPORT void rift_noise_filter_set_model(int32_t model);

// The mic volume, as a gain on every capture track, after the model: 1 as it
// is, below 1 quieter down to 0, which is silence, above 1 louder with the
// peaks limited rather than cut.
RIFT_NOISE_FILTER_EXPORT void rift_noise_filter_set_gain(float gain);

// Push-to-talk with the key up: 1 sends silence from the next 10 ms while the
// microphone keeps running, 0 sends it again. Faded over one frame.
RIFT_NOISE_FILTER_EXPORT void rift_noise_filter_set_silenced(int32_t silenced);

// RNNoise's weights, the file the app downloads (ModelCatalog.rnnoise) as
// RNNoise's write_weights.c writes it: the runner carries none of its own.
// Copied, and kept for the life of the process, since every state reads them
// in place. Returns 1 once weights are loaded, these or earlier ones, and 0
// when these do not load.
RIFT_NOISE_FILTER_EXPORT int32_t rift_noise_filter_set_rnnoise(
    const void* data,
    int32_t size);

// Where DPDFNet is, once the Rust library has loaded it: its
// rift_dpdfnet_process and rift_dpdfnet_reset (rust/src/dpdfnet). The
// runner does not link that library, so Dart passes the addresses on.
RIFT_NOISE_FILTER_EXPORT void rift_noise_filter_set_dpdfnet(void* process,
                                                            void* reset);

// How long the model and the mic volume took over each 10 ms since the last
// call, for the app's log after a call: writes four numbers to `out` — frames
// a model ran on, how many took over 5 ms, how many over 10 ms (late), and the
// slowest in microseconds — and starts counting again. All 0 with no filter.
RIFT_NOISE_FILTER_EXPORT void rift_noise_filter_take_timings(int64_t* out);

// RNNoise for the settings mic test, which reads the microphone in the Rust
// library rather than through libwebrtc (rust/src/mic_test). Its own state,
// apart from the call's, so a test and a call never share what the model has
// heard. The runner holds the weights (rift_noise_filter_set_rnnoise), so Dart
// passes these addresses on rather than the library loading a second copy.

// A fresh RNNoise state, or null before its weights are loaded.
RIFT_NOISE_FILTER_EXPORT void* rift_noise_filter_rnnoise_create(void);

// Filters 10 ms at 48 kHz in place, on the 16-bit scale as floats.
RIFT_NOISE_FILTER_EXPORT void rift_noise_filter_rnnoise_process(void* state,
                                                                float* frame);

RIFT_NOISE_FILTER_EXPORT void rift_noise_filter_rnnoise_destroy(void* state);

#endif  // RIFT_NOISE_FILTER_NOISE_FILTER_H_
