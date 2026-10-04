#ifndef RIFT_NOISE_FILTER_RATE_CONVERTER_H_
#define RIFT_NOISE_FILTER_RATE_CONVERTER_H_

#include <vector>

namespace rift {

// Converts a stream by the ratio up/down, one block at a time: a polyphase
// windowed-sinc filter, enough for speech going to RNNoise and back.
//
// Only for the rates libwebrtc's audio processing runs at (8, 16, 32 and
// 48 kHz), so every block converts to a whole number of samples and nothing
// is carried over but the filter's history.
class RateConverter {
 public:
  RateConverter(int up, int down);

  // Writes in_count * up / down samples to out. in and out may not overlap.
  void Process(const float* in, int in_count, float* out);

  void Reset();

 private:
  int up_;
  int down_;
  int taps_per_phase_;
  // Phase p's taps are taps_[p * taps_per_phase_ ...], newest sample first.
  std::vector<float> taps_;
  // The last taps_per_phase_ - 1 input samples, oldest first.
  std::vector<float> history_;
  std::vector<float> work_;
};

}  // namespace rift

#endif  // RIFT_NOISE_FILTER_RATE_CONVERTER_H_
