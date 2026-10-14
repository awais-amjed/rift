#include "noise_filter.h"

#include <atomic>
#include <chrono>
#include <cmath>

#include <flutter_webrtc.h>
#include <flutter_webrtc/flutter_web_r_t_c_plugin.h>
#include <rnnoise.h>

#include "limiter.h"
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

using DeepFilterProcess = int32_t (*)(float* samples, int32_t count);
using DeepFilterReset = void (*)();

// How long the filter takes over each 10 ms it is handed, kept for Dart to
// read after a call (rift_noise_filter_take_timings) rather than logged: the
// capture thread must never wait on a file. A frame that takes longer than
// the 10 ms it holds is late, and enough late frames are heard as holes.
class Timings {
 public:
  void Add(std::chrono::steady_clock::duration took) {
    const int64_t micros =
        std::chrono::duration_cast<std::chrono::microseconds>(took).count();
    frames_.fetch_add(1, std::memory_order_relaxed);
    if (micros > 5000) over_5ms_.fetch_add(1, std::memory_order_relaxed);
    if (micros > 10000) over_10ms_.fetch_add(1, std::memory_order_relaxed);
    int64_t worst = worst_micros_.load(std::memory_order_relaxed);
    while (micros > worst && !worst_micros_.compare_exchange_weak(
                                 worst, micros, std::memory_order_relaxed)) {
    }
  }

  // Frames, frames over 5 ms, frames over 10 ms and the slowest in
  // microseconds, since the last read; each starts again from 0.
  void Take(int64_t* out) {
    out[0] = frames_.exchange(0, std::memory_order_relaxed);
    out[1] = over_5ms_.exchange(0, std::memory_order_relaxed);
    out[2] = over_10ms_.exchange(0, std::memory_order_relaxed);
    out[3] = worst_micros_.exchange(0, std::memory_order_relaxed);
  }

 private:
  std::atomic<int64_t> frames_{0};
  std::atomic<int64_t> over_5ms_{0};
  std::atomic<int64_t> over_10ms_{0};
  std::atomic<int64_t> worst_micros_{0};
};

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

  void Initialize(int, int) override {
    restart_ = true;
    limiter_frames_ = 0;
  }

  void Reset(int) override {
    restart_ = true;
    limiter_frames_ = 0;
  }

  void Release() override {}

  void Process(int, int num_frames, int, float* buffer) override {
    const auto start = std::chrono::steady_clock::now();
    const bool modelled = Denoise(num_frames, buffer);
    Boost(num_frames, buffer);
    if (modelled) timings_.Add(std::chrono::steady_clock::now() - start);
  }

  void TakeTimings(int64_t* out) { timings_.Take(out); }

 private:
  // Whether a model ran on the frame.
  bool Denoise(int num_frames, float* buffer) {
    const int32_t model = model_.load(std::memory_order_acquire);
    const DeepFilterProcess deep_filter =
        deep_filter_process_.load(std::memory_order_acquire);
    if (model == kNone || (model == kDeepFilter && deep_filter == nullptr)) {
      // Started afresh when one comes back on, rather than carrying on from
      // whatever it last heard.
      restart_ = true;
      return false;
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
    } else {
      // Any other rate passes through untouched.
      return false;
    }
    return true;
  }

  // The mic volume, after the model, so the model hears the voice at the
  // level it was trained on (Limiter).
  void Boost(int num_frames, float* buffer) {
    // Each call is 10 ms, so the rate follows from the frame count.
    if (num_frames != limiter_frames_) {
      limiter_.Reset(num_frames * 100);
      limiter_frames_ = num_frames;
    }
    limiter_.Process(buffer, num_frames, gain_.load(std::memory_order_acquire));
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
  Limiter limiter_;
  // The frame count the limiter was last started for; 0 to start it again.
  int limiter_frames_ = 0;
  std::atomic<float> gain_{1.0f};
  std::atomic<int32_t> model_{kNone};
  std::atomic<DeepFilterProcess> deep_filter_process_{nullptr};
  std::atomic<DeepFilterReset> deep_filter_reset_{nullptr};
  Timings timings_;
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

void rift_noise_filter_take_timings(int64_t* out) {
  if (out == nullptr) return;
  if (rift::g_processing == nullptr) {
    for (int i = 0; i < 4; ++i) out[i] = 0;
    return;
  }
  rift::g_processing->TakeTimings(out);
}

void* rift_noise_filter_rnnoise_create(void) { return rnnoise_create(nullptr); }

void rift_noise_filter_rnnoise_process(void* state, float* frame) {
  if (state == nullptr || frame == nullptr) return;
  rnnoise_process_frame(static_cast<DenoiseState*>(state), frame, frame);
}

void rift_noise_filter_rnnoise_destroy(void* state) {
  if (state != nullptr) rnnoise_destroy(static_cast<DenoiseState*>(state));
}
