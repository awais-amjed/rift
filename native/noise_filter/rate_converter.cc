#include "rate_converter.h"

#include <algorithm>
#include <cmath>

namespace rift {

namespace {

constexpr double kPi = 3.14159265358979323846;

// Taps per phase. 32 keeps the band edge clean for speech; at most 48 * 32
// multiply-adds per 10 ms block for each direction.
constexpr int kTapsPerPhase = 32;

}  // namespace

RateConverter::RateConverter(int up, int down)
    : up_(up),
      down_(down),
      taps_per_phase_(kTapsPerPhase),
      taps_(static_cast<size_t>(up) * kTapsPerPhase),
      history_(kTapsPerPhase - 1, 0.0f) {
  // One low-pass at the up-sampled rate, cut a little under the lower of the
  // two Nyquist rates, with a gain of `up` to make up for the zeros put
  // between samples.
  const int length = up * kTapsPerPhase;
  const double cutoff = 0.45 / std::max(up, down);
  const double centre = (length - 1) / 2.0;
  for (int n = 0; n < length; ++n) {
    const double x = n - centre;
    const double sinc =
        x == 0 ? 2 * cutoff : std::sin(2 * kPi * cutoff * x) / (kPi * x);
    const double window = 0.42 - 0.5 * std::cos(2 * kPi * n / (length - 1)) +
                          0.08 * std::cos(4 * kPi * n / (length - 1));
    const int phase = n % up;
    const int tap = n / up;
    taps_[phase * kTapsPerPhase + tap] =
        static_cast<float>(sinc * window * up);
  }
}

void RateConverter::Process(const float* in, int in_count, float* out) {
  const int kept = taps_per_phase_ - 1;
  work_.resize(kept + in_count);
  std::copy(history_.begin(), history_.end(), work_.begin());
  std::copy(in, in + in_count, work_.begin() + kept);

  const int out_count = in_count * up_ / down_;
  for (int m = 0; m < out_count; ++m) {
    const int t = m * down_;
    const float* phase_taps = &taps_[(t % up_) * taps_per_phase_];
    // The newest input sample this output sees, in work_.
    const float* newest = &work_[kept + t / up_];
    float sum = 0;
    for (int k = 0; k < taps_per_phase_; ++k) sum += phase_taps[k] * newest[-k];
    out[m] = sum;
  }

  std::copy(work_.end() - kept, work_.end(), history_.begin());
}

void RateConverter::Reset() {
  std::fill(history_.begin(), history_.end(), 0.0f);
}

}  // namespace rift
