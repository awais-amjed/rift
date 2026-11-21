#ifndef RIFT_CALL_CLIP_CLIP_RING_H_
#define RIFT_CALL_CLIP_CLIP_RING_H_

#include <stdint.h>

#include <algorithm>
#include <cstring>
#include <vector>

namespace rift {

// The last stretch of a sound, interleaved 16-bit frames, the oldest written
// over first. Not thread-safe: ClipStore holds it under a lock.
class ClipRing {
 public:
  ClipRing(int64_t capacity_frames, int channels)
      : capacity_(capacity_frames > 0 ? capacity_frames : 1),
        channels_(channels),
        data_(static_cast<size_t>(capacity_ * channels), 0) {}

  int64_t Capacity() const { return capacity_; }
  int Channels() const { return channels_; }
  // Frames held: what was written, up to the capacity.
  int64_t Size() const { return (std::min)(written_, capacity_); }
  // Every frame ever written, silence included: how far along it is.
  int64_t Written() const { return written_; }

  void Write(const int16_t* interleaved, int64_t frames) {
    // Only the newest capacity_ of a longer write can be kept.
    if (frames > capacity_) {
      interleaved += (frames - capacity_) * channels_;
      written_ += frames - capacity_;
      frames = capacity_;
    }
    while (frames > 0) {
      const int64_t at = written_ % capacity_;
      const int64_t run = (std::min)(frames, capacity_ - at);
      std::memcpy(&data_[at * channels_], interleaved,
                  static_cast<size_t>(run * channels_) * sizeof(int16_t));
      interleaved += run * channels_;
      written_ += run;
      frames -= run;
    }
  }

  void WriteSilence(int64_t frames) {
    if (frames >= capacity_) {
      std::fill(data_.begin(), data_.end(), int16_t{0});
      written_ += frames;
      return;
    }
    while (frames > 0) {
      const int64_t at = written_ % capacity_;
      const int64_t run = (std::min)(frames, capacity_ - at);
      std::fill_n(&data_[at * channels_], run * channels_, int16_t{0});
      written_ += run;
      frames -= run;
    }
  }

  // Copies the newest min(max_frames, Size()) frames to out, oldest first.
  int64_t CopyNewest(int16_t* out, int64_t max_frames) const {
    const int64_t n = (std::min)(max_frames, Size());
    int64_t from = written_ - n;
    int64_t left = n;
    while (left > 0) {
      const int64_t at = from % capacity_;
      const int64_t run = (std::min)(left, capacity_ - at);
      std::memcpy(out, &data_[at * channels_],
                  static_cast<size_t>(run * channels_) * sizeof(int16_t));
      out += run * channels_;
      from += run;
      left -= run;
    }
    return n;
  }

  // A ring of capacity_frames holding the newest of what this one holds.
  ClipRing Resized(int64_t capacity_frames) const {
    ClipRing next(capacity_frames, channels_);
    std::vector<int16_t> kept(
        static_cast<size_t>((std::min)(Size(), next.capacity_) * channels_));
    const int64_t n = CopyNewest(kept.data(), next.capacity_);
    next.Write(kept.data(), n);
    return next;
  }

 private:
  int64_t capacity_;
  int channels_;
  std::vector<int16_t> data_;
  int64_t written_ = 0;
};

}  // namespace rift

#endif  // RIFT_CALL_CLIP_CLIP_RING_H_
