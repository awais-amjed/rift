#include "limiter.h"

#include <algorithm>
#include <cmath>

namespace rift {

namespace {

// The loudest a boosted voice may come out: 2 dB under full scale, in the
// units libwebrtc processes in (16-bit range, as floats). Opus does not give
// back exactly the wave it was handed, and at 1 dB under its peaks came out
// past full scale at the listener.
constexpr float kCeiling = 0.79f * 32767.0f;

// How fast the limiter lets go once a loud syllable has passed. Short enough
// that the next quiet word is not held down.
constexpr float kReleaseSeconds = 0.1f;

// How far ahead the limiter looks: the gain starts down this long before a
// peak, so it is never pinned to the ceiling for the peak itself, which is
// heard as a fuzz on loud vowels.
constexpr float kLookAheadSeconds = 0.0015f;

// How long the gain is held down after a peak before it is let go: longer
// than one pitch period of a low voice, or the gain would rise and fall with
// every cycle of it, which is distortion of its own.
constexpr float kHoldSeconds = 0.02f;

}  // namespace

void Limiter::Reset(int rate) {
  look_ahead_ =
      std::clamp(static_cast<int>(std::lround(kLookAheadSeconds * rate)), 1,
                 kMaxLookAhead);
  window_ = static_cast<uint64_t>(std::clamp(
      look_ahead_ + static_cast<int>(std::lround(kHoldSeconds * rate)),
      look_ahead_, kMaxWindow));
  release_ = std::exp(-1.0f / (kReleaseSeconds * static_cast<float>(rate)));
  count_ = 0;
  std::fill(delayed_, delayed_ + kMaxLookAhead, 0.0f);
  std::fill(held_, held_ + kMaxLookAhead, 1.0f);
  held_sum_ = look_ahead_;
  hold_ = 1.0f;
  least_front_ = 0;
  least_size_ = 0;
}

void Limiter::Process(float* samples, int count, float gain) {
  const bool limit = gain > 1.0f;
  for (int i = 0; i < count; ++i) samples[i] = Next(samples[i] * gain, limit);
}

float Limiter::Next(float boosted, bool limit) {
  const float magnitude = std::fabs(boosted);
  const float needs =
      limit && magnitude > kCeiling ? kCeiling / magnitude : 1.0f;
  const uint64_t n = count_++;

  // Out of the window first, so the ring never holds more than it.
  while (least_size_ > 0 && least_[least_front_].at + window_ <= n) {
    least_front_ = (least_front_ + 1) % kMaxWindow;
    --least_size_;
  }
  while (least_size_ > 0 &&
         least_[(least_front_ + least_size_ - 1) % kMaxWindow].gain >= needs) {
    --least_size_;
  }
  least_[(least_front_ + least_size_) % kMaxWindow] = {n, needs};
  ++least_size_;
  const float least = least_[least_front_].gain;
  hold_ = std::fmin(least, 1.0f - (1.0f - hold_) * release_);

  const int slot = static_cast<int>(n % static_cast<uint64_t>(look_ahead_));
  held_sum_ += static_cast<double>(hold_) - held_[slot];
  held_[slot] = hold_;
  if (slot == 0) {
    // Summed afresh once a look-ahead, so rounding never builds up.
    held_sum_ = 0;
    for (int i = 0; i < look_ahead_; ++i) held_sum_ += held_[i];
  }
  delayed_[slot] = boosted;
  const float oldest = delayed_[(slot + 1) % look_ahead_];
  return oldest * static_cast<float>(held_sum_ / look_ahead_);
}

}  // namespace rift
