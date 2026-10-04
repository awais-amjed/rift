#include "noise_filter.h"

#include <atomic>
#include <memory>

#include <flutter_webrtc.h>
#include <flutter_webrtc/flutter_web_r_t_c_plugin.h>
#include <rnnoise.h>

#include "rate_converter.h"

namespace rift {

namespace {

// RNNoise works on 10 ms at 48 kHz, which is also what libwebrtc hands over
// at that rate.
constexpr int kFrameSize = 480;

// The conversions to and from 48 kHz for one rate libwebrtc may process at.
// A Bluetooth headset's microphone is the usual reason for one below 48 kHz.
struct RatePath {
  int frames;
  RateConverter up;
  RateConverter down;
};

// The model values Dart passes to rift_noise_filter_set_model.
enum Model : int32_t { kNone = 0, kRnnoise = 1 };

// Called by libwebrtc on its capture thread, under a lock it holds for
// Initialize, Reset and Process alike, so only [model_] is shared.
class RnnoiseProcessing final
    : public libwebrtc::RTCAudioProcessing::CustomProcessing {
 public:
  RnnoiseProcessing()
      : state_(rnnoise_create(nullptr)),
        paths_{{80, {6, 1}, {1, 6}},
               {160, {3, 1}, {1, 3}},
               {320, {3, 2}, {2, 3}}} {}

  // Kept for the life of the process, as libwebrtc holds a raw pointer.
  ~RnnoiseProcessing() override = default;

  bool ok() const { return state_ != nullptr; }

  void SetModel(int32_t model) {
    model_.store(model == kRnnoise ? kRnnoise : kNone,
                 std::memory_order_relaxed);
  }

  void Initialize(int, int) override { restart_ = true; }

  void Reset(int) override { restart_ = true; }

  void Release() override {}

  void Process(int, int num_frames, int, float* buffer) override {
    if (model_.load(std::memory_order_relaxed) != kRnnoise) {
      // Started afresh when it comes back on, rather than carrying on from
      // whatever it last heard.
      restart_ = true;
      return;
    }
    if (restart_ || num_frames != frames_) Restart(num_frames);

    if (num_frames == kFrameSize) {
      rnnoise_process_frame(state_, buffer, buffer);
    } else if (path_ != nullptr) {
      path_->up.Process(buffer, num_frames, frame_);
      rnnoise_process_frame(state_, frame_, frame_);
      path_->down.Process(frame_, kFrameSize, buffer);
    }
    // Any other rate passes through untouched.
  }

 private:
  void Restart(int num_frames) {
    rnnoise_init(state_, nullptr);
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

  DenoiseState* state_;
  RatePath paths_[3];
  RatePath* path_ = nullptr;
  float frame_[kFrameSize] = {};
  int frames_ = 0;
  bool restart_ = true;
  std::atomic<int32_t> model_{kNone};
};

RnnoiseProcessing* g_processing = nullptr;

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
  auto* filter = new RnnoiseProcessing();
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
