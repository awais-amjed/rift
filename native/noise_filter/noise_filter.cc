#include "noise_filter.h"

#include <atomic>
#include <cmath>

#include <flutter_webrtc.h>
#include <flutter_webrtc/flutter_web_r_t_c_plugin.h>
#include <rnnoise.h>

#include "rate_converter.h"

namespace rift {

namespace {

// Both models work on 10 ms at 48 kHz, which is also what libwebrtc hands
// over at that rate.
constexpr int kFrameSize = 480;

// The conversions to and from 48 kHz for one rate libwebrtc may process at.
// A Bluetooth headset's microphone is the usual reason for one below 48 kHz.
struct RatePath {
  int frames;
  RateConverter up;
  RateConverter down;
};

// The model values Dart passes to rift_noise_filter_set_model.
enum Model : int32_t { kNone = 0, kRnnoise = 1, kDeepFilter = 2 };

// The loudest a boosted voice may come out: 2 dB under full scale, in the
// units libwebrtc processes in (16-bit range, as floats). Opus does not give
// back exactly the wave it was handed, and at 1 dB under its peaks came out
// past full scale at the listener.
constexpr float kCeiling = 0.79f * 32767.0f;

// How fast the limiter lets go once a loud syllable has passed. Short enough
// that the next quiet word is not held down; long enough that the gain does
// not follow the waveform, which would be distortion of its own.
constexpr float kReleaseSeconds = 0.1f;

using DeepFilterProcess = int32_t (*)(float* samples, int32_t count);
using DeepFilterReset = void (*)();

// Called by libwebrtc on its capture thread, under a lock it holds for
// Initialize, Reset and Process alike. What Dart sets is atomic.
class NoiseProcessing final
    : public libwebrtc::RTCAudioProcessing::CustomProcessing {
 public:
  NoiseProcessing()
      : rnnoise_(rnnoise_create(nullptr)),
        paths_{{80, {6, 1}, {1, 6}},
               {160, {3, 1}, {1, 3}},
               {320, {3, 2}, {2, 3}}} {}

  // Kept for the life of the process, as libwebrtc holds a raw pointer.
  ~NoiseProcessing() override = default;

  bool ok() const { return rnnoise_ != nullptr; }

  void SetModel(int32_t model) {
    model_.store(model == kRnnoise || model == kDeepFilter ? model : kNone,
                 std::memory_order_release);
  }

  void SetDeepFilter(DeepFilterProcess process, DeepFilterReset reset) {
    deep_filter_reset_.store(reset, std::memory_order_relaxed);
    deep_filter_process_.store(process, std::memory_order_release);
  }

  // The mic volume, as a gain: 1 leaves the voice as it is.
  void SetGain(float gain) {
    gain_.store(gain > 0 && std::isfinite(gain) ? gain : 1.0f,
                std::memory_order_release);
  }

  void Initialize(int, int) override { restart_ = true; }

  void Reset(int) override { restart_ = true; }

  void Release() override {}

  void Process(int, int num_frames, int, float* buffer) override {
    Denoise(num_frames, buffer);
    Boost(num_frames, buffer);
  }

 private:
  void Denoise(int num_frames, float* buffer) {
    const int32_t model = model_.load(std::memory_order_acquire);
    const DeepFilterProcess deep_filter =
        deep_filter_process_.load(std::memory_order_acquire);
    if (model == kNone || (model == kDeepFilter && deep_filter == nullptr)) {
      // Started afresh when one comes back on, rather than carrying on from
      // whatever it last heard.
      restart_ = true;
      return;
    }
    if (restart_ || model != running_ || num_frames != frames_) {
      Restart(model, num_frames);
    }

    if (num_frames == kFrameSize) {
      RunModel(buffer, deep_filter);
    } else if (path_ != nullptr) {
      path_->up.Process(buffer, num_frames, frame_);
      RunModel(frame_, deep_filter);
      path_->down.Process(frame_, kFrameSize, buffer);
    }
    // Any other rate passes through untouched.
  }

  // The mic volume, after the model, so the model hears the voice at the
  // level it was trained on. Turned up, a voice that already peaks near full
  // scale would be cut off flat, so a limiter holds the peaks under
  // [kCeiling] instead: it takes the gain down at once on a peak and gives it
  // back over [kReleaseSeconds]. The mic test does the same in Rust
  // (`mic_test::boost`).
  void Boost(int num_frames, float* buffer) {
    const float gain = gain_.load(std::memory_order_acquire);
    if (gain == 1.0f) {
      envelope_ = 0;
      return;
    }
    if (gain < 1.0f) {
      envelope_ = 0;
      for (int i = 0; i < num_frames; ++i) buffer[i] *= gain;
      return;
    }
    // Each call is 10 ms, so the rate follows from the frame count.
    if (num_frames != release_frames_) {
      release_ = std::exp(-1.0f / (kReleaseSeconds * num_frames * 100.0f));
      release_frames_ = num_frames;
    }
    for (int i = 0; i < num_frames; ++i) {
      const float boosted = buffer[i] * gain;
      envelope_ = std::fmax(std::fabs(boosted), envelope_ * release_);
      buffer[i] = envelope_ > kCeiling ? boosted * (kCeiling / envelope_)
                                       : boosted;
    }
  }

  void RunModel(float* frame, DeepFilterProcess deep_filter) {
    if (running_ == kRnnoise) {
      rnnoise_process_frame(rnnoise_, frame, frame);
    } else {
      // Leaves the frame as it was if the model cannot take it.
      deep_filter(frame, kFrameSize);
    }
  }

  void Restart(int32_t model, int num_frames) {
    if (model == kRnnoise) {
      rnnoise_init(rnnoise_, nullptr);
    } else if (DeepFilterReset reset =
                   deep_filter_reset_.load(std::memory_order_relaxed)) {
      reset();
    }
    running_ = model;
    frames_ = num_frames;
    path_ = nullptr;
    for (RatePath& path : paths_) {
      if (path.frames != num_frames) continue;
      path.up.Reset();
      path.down.Reset();
      path_ = &path;
    }
    restart_ = false;
  }

  DenoiseState* rnnoise_;
  RatePath paths_[3];
  RatePath* path_ = nullptr;
  float frame_[kFrameSize] = {};
  int frames_ = 0;
  int32_t running_ = kNone;
  bool restart_ = true;
  float envelope_ = 0;
  float release_ = 0;
  int release_frames_ = 0;
  std::atomic<float> gain_{1.0f};
  std::atomic<int32_t> model_{kNone};
  std::atomic<DeepFilterProcess> deep_filter_process_{nullptr};
  std::atomic<DeepFilterReset> deep_filter_reset_{nullptr};
};

NoiseProcessing* g_processing = nullptr;

flutter_webrtc_plugin::FlutterWebRTC* SharedWebRTC() {
#if defined(_WIN32)
  return FlutterWebRTCPluginSharedInstance();
#else
  return flutter_webrtc_plugin_get_shared_instance();
#endif
}

}  // namespace

bool InstallNoiseFilter() {
  if (g_processing != nullptr) return true;
  flutter_webrtc_plugin::FlutterWebRTC* webrtc = SharedWebRTC();
  if (webrtc == nullptr) return false;
  libwebrtc::scoped_refptr<libwebrtc::RTCAudioProcessing> processing =
      webrtc->audio_processing();
  if (processing.get() == nullptr) return false;

  // Never freed: libwebrtc keeps the pointer for as long as the factory lives,
  // and calls it from the capture thread until the process ends.
  auto* filter = new NoiseProcessing();
  if (!filter->ok()) {
    delete filter;
    return false;
  }
  processing->SetCapturePostProcessing(filter);
  g_processing = filter;
  return true;
}

}  // namespace rift

int32_t rift_noise_filter_available(void) {
  return rift::g_processing != nullptr ? 1 : 0;
}

void rift_noise_filter_set_model(int32_t model) {
  if (rift::g_processing != nullptr) rift::g_processing->SetModel(model);
}

void rift_noise_filter_set_gain(float gain) {
  if (rift::g_processing != nullptr) rift::g_processing->SetGain(gain);
}

void rift_noise_filter_set_deep_filter(void* process, void* reset) {
  if (rift::g_processing == nullptr) return;
  rift::g_processing->SetDeepFilter(
      reinterpret_cast<rift::DeepFilterProcess>(process),
      reinterpret_cast<rift::DeepFilterReset>(reset));
}

void* rift_noise_filter_rnnoise_create(void) {
  return rnnoise_create(nullptr);
}

void rift_noise_filter_rnnoise_process(void* state, float* frame) {
  if (state == nullptr || frame == nullptr) return;
  rnnoise_process_frame(static_cast<DenoiseState*>(state), frame, frame);
}

void rift_noise_filter_rnnoise_destroy(void* state) {
  if (state != nullptr) rnnoise_destroy(static_cast<DenoiseState*>(state));
}
