#ifndef RIFT_CALL_CLIP_CLIP_STORE_H_
#define RIFT_CALL_CLIP_CLIP_STORE_H_

#include <stdint.h>

#include <atomic>
#include <memory>
#include <mutex>
#include <optional>
#include <vector>

#include "../noise_filter/rate_converter.h"
#include "clip_ring.h"

namespace rift {

// The last stretch of a call, kept for clips (CALLS.md, "Clipping a call"):
// what the call played, 48 kHz stereo, and on request the microphone beside
// it, mixed in when a clip is taken.
//
// Written from libwebrtc's audio threads (render for the call, capture for
// the mic), configured and read from Dart's. An audio thread never waits: it
// only try-locks, and a block that finds the lock taken is dropped, which
// costs a clip 10 ms rather than costing the call a glitch.
class ClipStore {
 public:
  static constexpr int kRate = 48000;

  // seconds 0 frees everything. A shorter length keeps the newest audio.
  void Configure(int seconds, bool include_mic);

  // Whether blocks are kept. Off while Rift rejoins a call; on again once
  // the call has been told (the `clipping` attribute). The pause is not
  // filled with silence: the clip simply jumps over it.
  void SetWriting(bool on);

  // A 10 ms block of what the call plays, channel-planar (channels 1 or 2,
  // the right after the left, as libwebrtc lays them out), in its S16 float
  // range, at `rate`.
  void WriteCall(const float* planar, int frames, int rate, int channels,
                 int64_t now_us);

  // A 10 ms block of the microphone as the call hears it.
  void WriteMic(const float* mono, int frames, int rate, int64_t now_us);

  // Frames a snapshot would hold now.
  int64_t Frames();

  // The newest call audio, interleaved stereo, with the mic mixed into both
  // channels where it was recorded. Returns the frames written.
  int64_t Snapshot(int16_t* out, int64_t max_frames);

 private:
  // One channel brought to kRate.
  struct Converter {
    int rate = 0;
    std::unique_ptr<RateConverter> filter;
    // False for a rate libwebrtc's processing never runs at.
    bool Ensure(int new_rate);
    // Writes frames * kRate / rate samples.
    void Run(const float* in, int frames, float* out);
  };

  struct Lane {
    std::mutex lock;
    std::optional<ClipRing> ring;
    Converter convert[2];
    // When the last block arrived, or -1 after a pause.
    int64_t end_us = -1;
    int epoch = 0;
    std::vector<float> left, right;
    std::vector<int16_t> frames;
  };

  // Keeps `converted` frames (left, and right for stereo) after filling a
  // gap the lane went silent for while writing stayed on.
  void Keep(Lane& lane, int converted, bool stereo, int block_frames,
            int rate, int64_t now_us);

  Lane call_;
  Lane mic_;
  std::atomic<bool> writing_{false};
  std::atomic<int> epoch_{0};
};

}  // namespace rift

#endif  // RIFT_CALL_CLIP_CLIP_STORE_H_
