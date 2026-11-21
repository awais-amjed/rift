// The clip store's own tests: the ring, the rates it takes in, the mic lined
// up with the call, and Dart reconfiguring it while the audio thread writes.
// Run by native/call_clip/test.sh (no libwebrtc needed).
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <thread>
#include <vector>

#include "../clip_ring.h"
#include "../clip_store.h"

namespace {

int g_failed = 0;

#define CHECK(cond)                                              \
  do {                                                           \
    if (!(cond)) {                                               \
      std::fprintf(stderr, "%s:%d: CHECK(%s)\n", __FILE__, __LINE__, \
                   #cond);                                       \
      ++g_failed;                                                \
    }                                                            \
  } while (0)

constexpr double kPi = 3.14159265358979323846;

// One 10 ms block of a call at `rate`: channel-planar, left then right, in
// libwebrtc's S16 float range.
std::vector<float> Block(int rate, double left_hz, double right_hz,
                         int64_t start) {
  const int frames = rate / 100;
  std::vector<float> out(frames * 2);
  for (int i = 0; i < frames; ++i) {
    const double t = static_cast<double>(start + i) / rate;
    out[i] = left_hz > 0 ? 10000.0 * std::sin(2 * kPi * left_hz * t) : 0;
    out[frames + i] =
        right_hz > 0 ? 10000.0 * std::sin(2 * kPi * right_hz * t) : 0;
  }
  return out;
}


// Zero crossings of one channel of interleaved stereo, per second.
double CrossingsPerSecond(const std::vector<int16_t>& pcm, int channel,
                          int64_t from, int64_t to) {
  int crossings = 0;
  for (int64_t i = from + 1; i < to; ++i) {
    const int a = pcm[(i - 1) * 2 + channel];
    const int b = pcm[i * 2 + channel];
    if ((a < 0) != (b < 0)) ++crossings;
  }
  return crossings * 48000.0 / static_cast<double>(to - from);
}

double Rms(const std::vector<int16_t>& pcm, int channel, int64_t from,
           int64_t to) {
  double sum = 0;
  for (int64_t i = from; i < to; ++i) {
    const double v = pcm[i * 2 + channel];
    sum += v * v;
  }
  return std::sqrt(sum / static_cast<double>(to - from));
}

void RingWraps() {
  rift::ClipRing ring(4, 2);
  const int16_t a[] = {1, 1, 2, 2, 3, 3};
  ring.Write(a, 3);
  CHECK(ring.Size() == 3);
  const int16_t b[] = {4, 4, 5, 5, 6, 6};
  ring.Write(b, 3);
  CHECK(ring.Size() == 4);
  CHECK(ring.Written() == 6);
  int16_t out[8] = {};
  CHECK(ring.CopyNewest(out, 4) == 4);
  CHECK(out[0] == 3 && out[2] == 4 && out[4] == 5 && out[6] == 6);
  CHECK(ring.CopyNewest(out, 2) == 2);
  CHECK(out[0] == 5 && out[2] == 6);
}

void RingResizeKeepsNewest() {
  rift::ClipRing ring(10, 1);
  for (int16_t i = 0; i < 10; ++i) ring.Write(&i, 1);
  rift::ClipRing smaller = ring.Resized(4);
  CHECK(smaller.Size() == 4);
  int16_t out[4] = {};
  smaller.CopyNewest(out, 4);
  CHECK(out[0] == 6 && out[3] == 9);
  rift::ClipRing larger = ring.Resized(20);
  CHECK(larger.Size() == 10);
}

void OffWritesNothing() {
  rift::ClipStore store;
  auto block = Block(48000, 1000, 1000, 0);
  store.WriteCall(block.data(), 480, 48000, 2, 0);
  CHECK(store.Frames() == 0);
  store.Configure(30, false);
  store.WriteCall(block.data(), 480, 48000, 2, 0);
  CHECK(store.Frames() == 0);  // configured but not writing yet
  store.SetWriting(true, 0);
  store.WriteCall(block.data(), 480, 48000, 2, 0);
  CHECK(store.Frames() == 480);
  store.Configure(0, false);
  CHECK(store.Frames() == 0);
}

// A tone in at 16 kHz and then 32 kHz comes out at 48 kHz at its own pitch,
// with left staying left.
void RatesKeepPitchAndSide() {
  rift::ClipStore store;
  store.Configure(30, false);
  store.SetWriting(true, 0);
  int64_t now = 0;
  for (int rate : {16000, 32000}) {
    for (int64_t f = 0; f < rate; f += rate / 100) {
      auto block = Block(rate, 1000, 0, f);
      store.WriteCall(block.data(), rate / 100, rate, 2, now);
      now += 10000;
    }
  }
  std::vector<int16_t> pcm(store.Frames() * 2);
  const int64_t n = store.Snapshot(pcm.data(), store.Frames());
  CHECK(n >= 95000 && n <= 96000);
  // The middle of each second, clear of the filter's start.
  const double first = CrossingsPerSecond(pcm, 0, 12000, 36000);
  const double second = CrossingsPerSecond(pcm, 0, n - 36000, n - 12000);
  CHECK(std::fabs(first - 2000) < 20);
  CHECK(std::fabs(second - 2000) < 20);
  CHECK(Rms(pcm, 0, 12000, 36000) > 5000);
  CHECK(Rms(pcm, 1, 12000, 36000) < 50);
}

// A mono call (one channel) is heard in both ears.
void MonoGoesToBoth() {
  rift::ClipStore store;
  store.Configure(30, false);
  store.SetWriting(true, 0);
  int64_t now = 0;
  for (int64_t f = 0; f < 48000; f += 480) {
    auto block = Block(48000, 500, 0, f);
    store.WriteCall(block.data(), 480, 48000, 1, now);
    now += 10000;
  }
  std::vector<int16_t> pcm(store.Frames() * 2);
  const int64_t n = store.Snapshot(pcm.data(), store.Frames());
  CHECK(Rms(pcm, 0, 0, n) > 5000);
  CHECK(Rms(pcm, 1, 0, n) > 5000);
}

// The mic stops (muted) while the call goes on: what it said stays where it
// was said, not slid up to the end of the clip.
void MicLinesUpWithTheCall() {
  rift::ClipStore store;
  store.Configure(30, true);
  store.SetWriting(true, 0);
  int64_t now = 0;
  for (int64_t f = 0; f < 48000 * 2; f += 480) {
    auto call = Block(48000, 0, 0, f);
    store.WriteCall(call.data(), 480, 48000, 2, now);
    if (f < 24000) {
      auto mic = Block(16000, 700, 0, f / 3);
      store.WriteMic(mic.data(), 160, 16000, now);
    }
    now += 10000;
  }
  std::vector<int16_t> pcm(store.Frames() * 2);
  const int64_t n = store.Snapshot(pcm.data(), store.Frames());
  CHECK(n == 96000);
  CHECK(Rms(pcm, 0, 2400, 20000) > 3000);
  CHECK(Rms(pcm, 1, 2400, 20000) > 3000);
  CHECK(Rms(pcm, 0, 30000, n) < 50);
}

// Without the mic chosen, its frames are not kept.
void MicLeftOutUnlessChosen() {
  rift::ClipStore store;
  store.Configure(30, false);
  store.SetWriting(true, 0);
  int64_t now = 0;
  for (int64_t f = 0; f < 48000; f += 480) {
    auto call = Block(48000, 0, 0, f);
    store.WriteCall(call.data(), 480, 48000, 2, now);
    auto mic = Block(48000, 700, 0, f);
    store.WriteMic(mic.data(), 480, 48000, now);
    now += 10000;
  }
  std::vector<int16_t> pcm(store.Frames() * 2);
  const int64_t n = store.Snapshot(pcm.data(), store.Frames());
  CHECK(Rms(pcm, 0, 0, n) < 50);
}

// Paused (Rift rejoining) and resumed: the pause is not filled with minutes
// of silence that push the older call out.
void PauseIsNotFilled() {
  rift::ClipStore store;
  store.Configure(30, false);
  store.SetWriting(true, 0);
  int64_t now = 0;
  for (int64_t f = 0; f < 48000; f += 480) {
    auto call = Block(48000, 1000, 1000, f);
    store.WriteCall(call.data(), 480, 48000, 2, now);
    now += 10000;
  }
  store.SetWriting(false, now);
  now += 20 * 1000000;
  store.SetWriting(true, now);
  for (int64_t f = 0; f < 48000; f += 480) {
    auto call = Block(48000, 1000, 1000, f);
    store.WriteCall(call.data(), 480, 48000, 2, now);
    now += 10000;
  }
  CHECK(store.Frames() == 96000);
}

// The call goes quiet and libwebrtc stops handing over blocks; then Rift
// rejoins, and the call stays quiet a while longer. The quiet on both sides
// of the pause is still part of the call and is kept: without it, audio from
// minutes earlier was joined straight onto what came after the rejoin (live
// check, Nov 21). Only the pause itself is skipped.
void QuietAroundPauseIsKept() {
  rift::ClipStore store;
  store.Configure(30, false);
  store.SetWriting(true, 0);
  int64_t now = 0;
  for (int64_t f = 0; f < 48000; f += 480) {
    auto call = Block(48000, 1000, 1000, f);
    store.WriteCall(call.data(), 480, 48000, 2, now);
    now += 10000;
  }
  now += 5 * 1000000;
  store.SetWriting(false, now);
  now += 20 * 1000000;
  store.SetWriting(true, now);
  now += 3 * 1000000;
  for (int64_t f = 0; f < 48000; f += 480) {
    auto call = Block(48000, 1000, 1000, f);
    store.WriteCall(call.data(), 480, 48000, 2, now);
    now += 10000;
  }
  CHECK(store.Frames() == 48000 * 10);
  std::vector<int16_t> pcm(store.Frames() * 2);
  const int64_t n = store.Snapshot(pcm.data(), store.Frames());
  CHECK(Rms(pcm, 0, 0, 48000) > 5000);
  CHECK(Rms(pcm, 0, 48000 + 2400, 48000 * 9 - 2400) < 50);
  CHECK(Rms(pcm, 0, 48000 * 9, n) > 5000);
}

// The call has been quiet since a tone ended, so libwebrtc has handed over
// nothing since. A clip taken now ends in that quiet: without it, a clip
// pressed minutes after the last sound held that sound (win11 live check,
// Nov 21).
void QuietUntilNowIsKept() {
  rift::ClipStore store;
  store.Configure(30, false);
  store.SetWriting(true, 0);
  int64_t now = 0;
  for (int64_t f = 0; f < 48000 * 10; f += 480) {
    auto call = Block(48000, 1000, 1000, f);
    store.WriteCall(call.data(), 480, 48000, 2, now);
    now += 10000;
  }
  now += 15 * 1000000;
  store.CatchUp(now);
  // The last block is stamped at 9.99 s: the quiet runs from there.
  CHECK(store.Frames() == 48000 * 25 + 480);
  std::vector<int16_t> pcm(store.Frames() * 2);
  const int64_t n = store.Snapshot(pcm.data(), store.Frames());
  CHECK(Rms(pcm, 0, 0, 48000 * 10 - 2400) > 5000);
  CHECK(Rms(pcm, 0, 48000 * 10, n) < 50);

  // A block after the catch-up is not preceded by the same quiet twice.
  now += 10000;
  auto call = Block(48000, 1000, 1000, 0);
  store.WriteCall(call.data(), 480, 48000, 2, now);
  CHECK(store.Frames() == 48000 * 25 + 960);
}

// Caught up while Rift rejoins: the quiet before the pause is kept, and the
// pause is not, nor counted again by the first block after it.
void CatchUpSkipsThePause() {
  rift::ClipStore store;
  store.Configure(60, false);
  store.SetWriting(true, 0);
  int64_t now = 0;
  for (int64_t f = 0; f < 48000 * 5; f += 480) {
    auto call = Block(48000, 1000, 1000, f);
    store.WriteCall(call.data(), 480, 48000, 2, now);
    now += 10000;
  }
  now += 2 * 1000000;
  store.SetWriting(false, now);
  now += 20 * 1000000;
  store.CatchUp(now);
  CHECK(store.Frames() == 48000 * 7 + 480);
  store.SetWriting(true, now);
  now += 3 * 1000000;
  store.CatchUp(now);
  CHECK(store.Frames() == 48000 * 10 + 480);
  now += 1 * 1000000;
  auto call = Block(48000, 1000, 1000, 0);
  store.WriteCall(call.data(), 480, 48000, 2, now);
  CHECK(store.Frames() == 48000 * 11 + 480);
}

// Rift rejoins twice with no block from the call between (it stayed
// quiet): both pauses are skipped, not only the last.
void TwoPausesWithoutABlock() {
  rift::ClipStore store;
  store.Configure(30, false);
  store.SetWriting(true, 0);
  int64_t now = 0;
  for (int64_t f = 0; f < 48000; f += 480) {
    auto call = Block(48000, 1000, 1000, f);
    store.WriteCall(call.data(), 480, 48000, 2, now);
    now += 10000;
  }
  now += 2 * 1000000;
  store.SetWriting(false, now);
  now += 10 * 1000000;
  store.SetWriting(true, now);
  now += 1 * 1000000;
  store.SetWriting(false, now);
  now += 10 * 1000000;
  store.SetWriting(true, now);
  now += 3 * 1000000;
  auto call = Block(48000, 1000, 1000, 0);
  store.WriteCall(call.data(), 480, 48000, 2, now);
  // 1 s of tone, 6 s of quiet (2 + 1 + 3), the block.
  CHECK(store.Frames() == 48000 * 7 + 480);
}

// The mic goes quiet (muted), the call plays on, Rift rejoins, the call
// plays on again. The mic stays where it was said: the pause the call
// skipped is not counted between them.
void MicAcrossAPause() {
  rift::ClipStore store;
  store.Configure(30, true);
  store.SetWriting(true, 0);
  int64_t now = 0;
  for (int64_t f = 0; f < 48000 * 2; f += 480) {
    auto call = Block(48000, 0, 0, f);
    store.WriteCall(call.data(), 480, 48000, 2, now);
    if (f < 48000) {
      auto mic = Block(48000, 700, 0, f);
      store.WriteMic(mic.data(), 480, 48000, now);
    }
    now += 10000;
  }
  store.SetWriting(false, now);
  now += 3 * 1000000;
  store.SetWriting(true, now);
  for (int64_t f = 0; f < 48000; f += 480) {
    auto call = Block(48000, 0, 0, f);
    store.WriteCall(call.data(), 480, 48000, 2, now);
    now += 10000;
  }
  std::vector<int16_t> pcm(store.Frames() * 2);
  const int64_t n = store.Snapshot(pcm.data(), store.Frames());
  CHECK(n == 48000 * 3);
  CHECK(Rms(pcm, 0, 2400, 45600) > 3000);
  CHECK(Rms(pcm, 0, 50400, n) < 50);
}

// Shrinking the length keeps the newest audio.
void ShorterKeepsNewest() {
  rift::ClipStore store;
  store.Configure(60, false);
  store.SetWriting(true, 0);
  int64_t now = 0;
  for (int64_t f = 0; f < 48000 * 40; f += 480) {
    // A quiet first 10 s, then a tone: the newest 30 s are all tone.
    auto call = Block(48000, f < 480000 ? 0 : 1000, 0, f);
    store.WriteCall(call.data(), 480, 48000, 2, now);
    now += 10000;
  }
  store.Configure(30, false);
  CHECK(store.Frames() == 48000 * 30);
  std::vector<int16_t> pcm(store.Frames() * 2);
  const int64_t n = store.Snapshot(pcm.data(), store.Frames());
  CHECK(Rms(pcm, 0, 0, 48000) > 5000);
  CHECK(n == 48000 * 30);
}

// Dart reconfigures while the audio thread writes: nothing breaks (run under
// ThreadSanitizer by test.sh).
void ConfigureWhileWriting() {
  rift::ClipStore store;
  store.Configure(30, true);
  store.SetWriting(true, 0);
  std::atomic<bool> stop{false};
  std::thread audio([&] {
    int64_t now = 0;
    int64_t f = 0;
    while (!stop.load()) {
      auto call = Block(32000, 1000, 0, f);
      store.WriteCall(call.data(), 320, 32000, 2, now);
      store.WriteMic(call.data(), 320, 32000, now);
      f += 320;
      now += 10000;
    }
  });
  for (int i = 0; i < 300; ++i) {
    store.Configure(i % 3 == 0 ? 0 : (i % 3 == 1 ? 30 : 60), i % 2 == 0);
    const int64_t room = store.Frames();
    std::vector<int16_t> pcm(room * 2 + 2);
    CHECK(store.Snapshot(pcm.data(), room) <= room);
  }
  stop.store(true);
  audio.join();
}

}  // namespace

int main() {
  RingWraps();
  RingResizeKeepsNewest();
  OffWritesNothing();
  RatesKeepPitchAndSide();
  MonoGoesToBoth();
  MicLinesUpWithTheCall();
  MicLeftOutUnlessChosen();
  PauseIsNotFilled();
  QuietAroundPauseIsKept();
  QuietUntilNowIsKept();
  CatchUpSkipsThePause();
  TwoPausesWithoutABlock();
  MicAcrossAPause();
  ShorterKeepsNewest();
  ConfigureWhileWriting();
  if (g_failed == 0) std::printf("clip store: all passed\n");
  return g_failed == 0 ? 0 : 1;
}
