#include "call_clip.h"

#include <atomic>
#include <chrono>

#include <flutter_webrtc.h>
#include <flutter_webrtc/flutter_web_r_t_c_plugin.h>

#include "clip_store.h"

namespace rift {

namespace {

ClipStore g_store;
std::atomic<bool> g_installed{false};
std::atomic<int32_t> g_render_rate{0};
std::atomic<int32_t> g_render_channels{0};

int64_t NowUs() {
  return std::chrono::duration_cast<std::chrono::microseconds>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}

// What the call plays, before libwebrtc plays it. It only reads.
//
// flutter_webrtc's libwebrtc installs an empty render pre-processor of its
// own and plays its copy of the audio whether or not one is set (CALLS.md,
// "How a call is played out on the desktop"), so putting this one there
// changes nothing about what is heard. `buffer` is the first channel of
// libwebrtc's full-band buffer, in its S16 float range; a second channel
// follows it in the same block, num_frames later. Read only when Initialize
// said there are two (verified with a left-only tone, TESTING.md).
class RenderTap final : public libwebrtc::RTCAudioProcessing::CustomProcessing {
 public:
  void Initialize(int sample_rate_hz, int num_channels) override {
    rate_ = sample_rate_hz;
    channels_ = num_channels;
    g_render_rate.store(rate_, std::memory_order_relaxed);
    g_render_channels.store(channels_, std::memory_order_relaxed);
  }

  void Reset(int new_rate) override {
    rate_ = new_rate;
    g_render_rate.store(rate_, std::memory_order_relaxed);
  }

  void Process(int, int num_frames, int, float* buffer) override {
    if (rate_ <= 0 || num_frames * 100 != rate_) return;
    g_store.WriteCall(buffer, num_frames, rate_, channels_ >= 2 ? 2 : 1,
                      NowUs());
  }

  void Release() override {}

  // Kept for the life of the process, as libwebrtc holds a raw pointer.
  ~RenderTap() override = default;

 private:
  int rate_ = 0;
  int channels_ = 1;
};

flutter_webrtc_plugin::FlutterWebRTC* SharedWebRTC() {
#if defined(_WIN32)
  return FlutterWebRTCPluginSharedInstance();
#else
  return flutter_webrtc_plugin_get_shared_instance();
#endif
}

}  // namespace

bool InstallCallClip() {
  if (g_installed.load()) return true;
  flutter_webrtc_plugin::FlutterWebRTC* webrtc = SharedWebRTC();
  if (webrtc == nullptr) return false;
  libwebrtc::scoped_refptr<libwebrtc::RTCAudioProcessing> processing =
      webrtc->audio_processing();
  if (processing.get() == nullptr) return false;
  // Never freed: libwebrtc calls it from the playout thread until the
  // process ends.
  processing->SetRenderPreProcessing(new RenderTap());
  g_installed.store(true);
  return true;
}

void CallClipMic(const float* mono, int frames, int rate) {
  g_store.WriteMic(mono, frames, rate, NowUs());
}

}  // namespace rift

int32_t rift_call_clip_available(void) {
  return rift::g_installed.load() ? 1 : 0;
}

void rift_call_clip_configure(int32_t seconds, int32_t include_mic) {
  rift::g_store.Configure(seconds, include_mic != 0);
}

void rift_call_clip_set_writing(int32_t on) {
  rift::g_store.SetWriting(on != 0, rift::NowUs());
}

int64_t rift_call_clip_frames(void) { return rift::g_store.Frames(); }

int64_t rift_call_clip_snapshot(int16_t* out, int64_t max_frames) {
  if (out == nullptr || max_frames <= 0) return 0;
  return rift::g_store.Snapshot(out, max_frames);
}

void rift_call_clip_format(int32_t* rate, int32_t* channels) {
  if (rate != nullptr) *rate = rift::g_render_rate.load();
  if (channels != nullptr) *channels = rift::g_render_channels.load();
}
