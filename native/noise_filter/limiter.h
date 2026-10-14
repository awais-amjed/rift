#ifndef RIFT_NOISE_FILTER_LIMITER_H_
#define RIFT_NOISE_FILTER_LIMITER_H_

#include <cstdint>

namespace rift {

// The mic volume: a gain, and above 1 a limiter that holds the peaks under a
// ceiling rather than cutting them off flat. The mic test runs the same
// algorithm with the same constants in Rust (`mic_test::boost`).
//
// For each sample, the gain it needs to stay under the ceiling (1 when it
// does already); the least of those over the look-ahead and the hold; that
// let back up towards 1 over the release; and the mean of the last
// look-ahead's worth of it applied to the sample that look-ahead ago. Every
// value in that mean comes from a window holding the sample it is applied
// to, so none is more than that sample needs, and the ceiling holds; the
// mean makes the gain glide down over the look-ahead instead of stepping.
//
// The voice comes out the look-ahead late at every volume, 1 included, so
// that dragging the slider across 100% never makes it jump. Nothing is
// allocated: libwebrtc calls it on its capture thread.
class Limiter {
 public:
  // Starts afresh for a stream at `rate` samples a second.
  void Reset(int rate);

  // Applies `gain` to `count` samples in place, on the 16-bit scale as
  // floats.
  void Process(float* samples, int count, float gain);

 private:
  // Takes one boosted sample and gives back the one a look-ahead ago.
  float Next(float boosted, bool limit);

  // 1.5 ms and 1.5 ms + 20 ms at 48 kHz, the highest rate libwebrtc
  // processes at.
  static constexpr int kMaxLookAhead = 72;
  static constexpr int kMaxWindow = kMaxLookAhead + 960;

  // A gain a sample needed, and which sample.
  struct Need {
    uint64_t at;
    float gain;
  };

  // Samples looked ahead; the voice comes out one fewer late.
  int look_ahead_ = 1;
  // Look-ahead and hold together: how far back the least gain is taken.
  uint64_t window_ = 1;
  float release_ = 0;
  // Samples seen.
  uint64_t count_ = 0;
  // The last look-ahead's boosted samples, oldest next to be written.
  float delayed_[kMaxLookAhead] = {};
  // The last look-ahead's held gains, and their sum.
  float held_[kMaxLookAhead] = {};
  double held_sum_ = 0;
  // The gain held after the latest sample.
  float hold_ = 1;
  // The gains needed over the window that are less than every one needed
  // after them, oldest first, in a ring: the least is at the front.
  Need least_[kMaxWindow] = {};
  int least_front_ = 0;
  int least_size_ = 0;
};

}  // namespace rift

#endif  // RIFT_NOISE_FILTER_LIMITER_H_
