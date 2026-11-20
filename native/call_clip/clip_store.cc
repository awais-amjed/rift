#include "clip_store.h"

#include <cmath>
#include <numeric>

namespace rift {

namespace {

// Longest block libwebrtc hands over: 10 ms at 48 kHz, with room to spare.
constexpr int kMaxBlockOut = 4800;

// A lane silent this much longer than a block went quiet (the mic muted, the
// call's playout stopped); the gap is kept as silence so what came before
// stays where it was said.
constexpr int64_t kGapUs = 50000;

int16_t ToS16(float v) {
  const float r = std::nearbyint(v);
  if (r > 32767.0f) return 32767;
  if (r < -32768.0f) return -32768;
  return static_cast<int16_t>(r);
}

int16_t Saturate(int32_t v) {
  if (v > 32767) return 32767;
  if (v < -32768) return -32768;
  return static_cast<int16_t>(v);
}

}  // namespace

bool ClipStore::Converter::Ensure(int new_rate) {
  if (new_rate == rate) return rate == kRate || filter != nullptr;
  rate = new_rate;
  filter.reset();
  if (new_rate == kRate) return true;
  if (new_rate != 8000 && new_rate != 16000 && new_rate != 32000) {
    return false;
  }
  const int g = std::gcd(kRate, new_rate);
  filter = std::make_unique<RateConverter>(kRate / g, new_rate / g);
  return true;
}

void ClipStore::Converter::Run(const float* in, int frames, float* out) {
  if (filter == nullptr) {
    std::copy(in, in + frames, out);
    return;
  }
  filter->Process(in, frames, out);
}

void ClipStore::Configure(int seconds, bool include_mic) {
  std::lock_guard<std::mutex> call_lock(call_.lock);
  std::lock_guard<std::mutex> mic_lock(mic_.lock);
  if (seconds <= 0) {
    call_.ring.reset();
    mic_.ring.reset();
    call_.end_us = mic_.end_us = -1;
    return;
  }
  const int64_t capacity = static_cast<int64_t>(seconds) * kRate;
  call_.ring = call_.ring ? call_.ring->Resized(capacity) : ClipRing(capacity, 2);
  if (include_mic) {
    mic_.ring = mic_.ring ? mic_.ring->Resized(capacity) : ClipRing(capacity, 1);
  } else {
    mic_.ring.reset();
    mic_.end_us = -1;
  }
  for (Lane* lane : {&call_, &mic_}) {
    lane->left.reserve(kMaxBlockOut);
    lane->right.reserve(kMaxBlockOut);
    lane->frames.reserve(kMaxBlockOut * 2);
  }
}

void ClipStore::SetWriting(bool on) {
  if (on) epoch_.fetch_add(1, std::memory_order_acq_rel);
  writing_.store(on, std::memory_order_release);
}

void ClipStore::Keep(Lane& lane, int converted, bool stereo, int block_frames,
                     int rate, int64_t now_us) {
  const int epoch = epoch_.load(std::memory_order_acquire);
  if (lane.epoch != epoch) {
    lane.epoch = epoch;
    lane.end_us = -1;
  }
  const int channels = lane.ring->Channels();
  if (lane.end_us >= 0) {
    const int64_t block_us =
        static_cast<int64_t>(block_frames) * 1000000 / rate;
    const int64_t gap_us = now_us - lane.end_us - block_us;
    if (gap_us > kGapUs) lane.ring->WriteSilence(gap_us * kRate / 1000000);
  }
  lane.end_us = now_us;
  lane.frames.resize(static_cast<size_t>(converted * channels));
  for (int i = 0; i < converted; ++i) {
    if (channels == 2) {
      lane.frames[i * 2] = ToS16(lane.left[i]);
      lane.frames[i * 2 + 1] = ToS16(stereo ? lane.right[i] : lane.left[i]);
    } else {
      lane.frames[i] = ToS16(lane.left[i]);
    }
  }
  lane.ring->Write(lane.frames.data(), converted);
}

void ClipStore::WriteCall(const float* planar, int frames, int rate,
                          int channels, int64_t now_us) {
  if (!writing_.load(std::memory_order_acquire) || frames <= 0 || rate <= 0) {
    return;
  }
  std::unique_lock<std::mutex> lock(call_.lock, std::try_to_lock);
  if (!lock.owns_lock() || !call_.ring) return;
  const int converted = static_cast<int>(
      static_cast<int64_t>(frames) * kRate / rate);
  if (converted > kMaxBlockOut) return;
  const bool stereo = channels >= 2;
  if (!call_.convert[0].Ensure(rate)) return;
  if (stereo && !call_.convert[1].Ensure(rate)) return;
  call_.left.resize(converted);
  call_.convert[0].Run(planar, frames, call_.left.data());
  if (stereo) {
    call_.right.resize(converted);
    call_.convert[1].Run(planar + frames, frames, call_.right.data());
  }
  Keep(call_, converted, stereo, frames, rate, now_us);
}

void ClipStore::WriteMic(const float* mono, int frames, int rate,
                         int64_t now_us) {
  if (!writing_.load(std::memory_order_acquire) || frames <= 0 || rate <= 0) {
    return;
  }
  std::unique_lock<std::mutex> lock(mic_.lock, std::try_to_lock);
  if (!lock.owns_lock() || !mic_.ring) return;
  const int converted = static_cast<int>(
      static_cast<int64_t>(frames) * kRate / rate);
  if (converted > kMaxBlockOut) return;
  if (!mic_.convert[0].Ensure(rate)) return;
  mic_.left.resize(converted);
  mic_.convert[0].Run(mono, frames, mic_.left.data());
  Keep(mic_, converted, false, frames, rate, now_us);
}

int64_t ClipStore::Frames() {
  std::lock_guard<std::mutex> lock(call_.lock);
  return call_.ring ? call_.ring->Size() : 0;
}

int64_t ClipStore::Snapshot(int16_t* out, int64_t max_frames) {
  std::lock_guard<std::mutex> call_lock(call_.lock);
  std::lock_guard<std::mutex> mic_lock(mic_.lock);
  if (!call_.ring) return 0;
  const int64_t n = call_.ring->CopyNewest(out, max_frames);
  if (!mic_.ring || n == 0) return n;

  std::vector<int16_t> mic(static_cast<size_t>(n));
  const int64_t m = mic_.ring->CopyNewest(mic.data(), n);
  // The mic's newest frame sits where it was recorded: as far before the
  // call's newest as it stopped before the call did.
  int64_t offset = 0;
  if (call_.end_us >= 0 && mic_.end_us >= 0 && call_.end_us > mic_.end_us) {
    offset = (call_.end_us - mic_.end_us) * kRate / 1000000;
  }
  const int64_t start = n - offset - m;
  for (int64_t i = 0; i < m; ++i) {
    const int64_t at = start + i;
    if (at < 0 || at >= n) continue;
    out[at * 2] = Saturate(int32_t{out[at * 2]} + mic[i]);
    out[at * 2 + 1] = Saturate(int32_t{out[at * 2 + 1]} + mic[i]);
  }
  return n;
}

}  // namespace rift
