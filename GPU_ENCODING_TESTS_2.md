# GPU encoding tests, round 2 — Rift's FFmpeg encoder on AMD (Linux)

A brief for whoever runs these on the AMD machine, person or agent. It lives on
the `gpu-encoding` branch only and goes when the question is answered. Round 1
(`GPU_ENCODING_TESTS.md`, results in `GPU_ENCODING_RESULTS.md`) found that
FFmpeg's `h264_vaapi` is clean on this GPU and LiveKit's VAAPI encoder is not.

## What changed since round 1

Rift now encodes H264 on Intel and AMD GPUs itself, with **FFmpeg's
`h264_vaapi`**, and hands LiveKit the finished frames (`ARCHITECTURE.md`,
"Encoding a share on the GPU"). LiveKit's VAAPI encoder is no longer used.

- FFmpeg is built into a library of its own, `librift_ffenc.so`
  (`native/ffenc/`), because LiveKit's libwebrtc already carries Chromium's
  FFmpeg under the same names. The app's Linux build makes it; the Rust tests
  are pointed at it with `RIFT_FFENC_LIB`.
- FFmpeg's encoder normally sends the bitrate to the GPU only with a keyframe.
  Rift patches it to send every change WebRTC asks for with the next picture
  (`third_party/ffmpeg/RIFT_PATCHES.md`). **On Intel that works. Whether
  AMD's driver (Mesa) also follows a bitrate changed mid-stream is the main
  question here.** If it does not, the picture falls behind the sound on a
  slow link, which is what a friend saw on Windows.
- Variable bitrate, capped at the target. Constant bitrate made Intel pad a
  still screen out to the full rate.
- On Intel, the driver sometimes failed an encoder's very first picture; Rift
  then opens it again once and logs
  `the first picture failed (...); opening the encoder again`.

## Rules for the run

- Ask before installing anything, and before anything that needs `sudo`.
- Recordings and logs stay on this machine, in one folder (e.g.
  `~/rift-gpu-test/round2/`). Upload nothing.
- Do not change system settings, drivers or Mesa.
- When done, write the results into `GPU_ENCODING_RESULTS_2.md` next to this
  file, commit it on `gpu-encoding` and push. **No `Co-Authored-By` or other
  attribution lines in the commit message.** Recordings are not committed.

## 0. Build the encoder library

Needs a C compiler, `make`, `patch`, `curl` and libva's headers (on Arch and
CachyOS they come with `libva`). It downloads FFmpeg 9.0.2 once and checks its
sha256; about 15 s.

```sh
mkdir -p ~/rift-gpu-test/round2 && cd ~/rift-gpu-test/round2
~/path/to/rift-app/native/ffenc/build.sh "$PWD/ffenc"
nm -D --defined-only ffenc/librift_ffenc.so     # eight rift_ffenc_* names, nothing else
export RIFT_FFENC_LIB="$PWD/ffenc/librift_ffenc.so"
vainfo 2>&1 | grep -E 'Driver version|H264.*Enc'
```

If the GPU has more than one render node (`ls /dev/dri`), say which is the
RX 9070 XT; Rift uses the first one that opens an H264 encoder.

## 1. The library alone

Save this as `check.c` in the same folder. It drives the library the way Rift
does: NV12 pictures in, the bitrate moved between pictures, a keyframe asked
for now and then.

```c
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "ffenc.h"

static double now(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec + t.tv_nsec / 1e9;
}

static RiftFfenc* (*open_)(const RiftFfencConfig*, char*, size_t);
static int32_t (*send_)(RiftFfenc*, const uint8_t*, int64_t, int32_t);
static int32_t (*recv_)(RiftFfenc*, RiftFfencPacket*);
static void (*rate_)(RiftFfenc*, int64_t);
static void (*close_)(RiftFfenc*);

// A picture that moves and costs bits: a sliding gradient with noise on top.
static void fill(uint8_t* p, int w, int h, int n, int still) {
  size_t len = (size_t)w * h * 3 / 2;
  for (size_t i = 0; i < len; i++) {
    p[i] = (uint8_t)((i % w) / 4 + (still ? 0 : n * 3));
    if (!still && (i & 7) == 0) p[i] ^= rand() & 0x3f;
  }
}

static RiftFfenc* start(int w, int h, int fps, long bps) {
  char err[256];
  RiftFfencConfig c = {"h264_vaapi", getenv("DEVICE"), w, h, fps, bps, 100, fps * 60};
  RiftFfenc* e = open_(&c, err, sizeof err);
  if (!e) printf("open failed: %s\n", err);
  return e;
}

// 0 if the picture went through, else the step that failed.
static int encode(RiftFfenc* e, uint8_t* pic, int64_t pts, int key, long* bytes) {
  if (send_(e, pic, pts, key) < 0) return 1;
  RiftFfencPacket p;
  int got;
  while ((got = recv_(e, &p)) == 1) *bytes += p.len;
  return got < 0 ? 2 : 0;
}

int main(int argc, char** argv) {
  void* lib = dlopen(getenv("RIFT_FFENC_LIB"), RTLD_NOW | RTLD_LOCAL);
  if (!lib) { printf("%s\n", dlerror()); return 1; }
  open_ = dlsym(lib, "rift_ffenc_open"); send_ = dlsym(lib, "rift_ffenc_send");
  recv_ = dlsym(lib, "rift_ffenc_receive"); rate_ = dlsym(lib, "rift_ffenc_set_bitrate");
  close_ = dlsym(lib, "rift_ffenc_close");
  const char* mode = argc > 1 ? argv[1] : "rate";
  int w = 2560, h = 1440, fps = 60;
  uint8_t* pic = malloc((size_t)w * h * 3 / 2);

  if (!strcmp(mode, "rate") || !strcmp(mode, "still")) {
    int still = !strcmp(mode, "still");
    // The rate WebRTC asks for, each second: 20, then 5, then 12 Mbps, with a
    // keyframe asked for in the middle of the 5 Mbps stretch.
    long plan[] = {20, 20, 20, 20, 5, 5, 5, 5, 5, 5, 12, 12, 12, 12, 12, 12};
    int secs = sizeof plan / sizeof *plan;
    RiftFfenc* e = start(w, h, fps, plan[0] * 1000000);
    if (!e) return 1;
    for (int s = 0; s < secs; s++) {
      long bytes = 0;
      double busy = 0, worst = 0;
      if (s > 0 && plan[s] != plan[s - 1]) rate_(e, plan[s] * 1000000);
      for (int f = 0; f < fps; f++) {
        int n = s * fps + f;
        fill(pic, w, h, n, still);
        double t = now();
        int r = encode(e, pic, (int64_t)n * 1000000 / fps, n == 7 * fps, &bytes);
        t = now() - t;
        busy += t;
        if (t > worst) worst = t;
        if (r) { printf("second %d picture %d failed (%d)\n", s, f, r); return 1; }
      }
      printf("second %2d: asked %2ld Mbps, made %6.2f | %.1f ms a picture, worst %.1f%s\n",
             s, plan[s], bytes * 8 / 1e6, busy / fps * 1000, worst * 1000,
             s == 7 ? " | keyframe asked" : "");
    }
    close_(e);
  } else if (!strcmp(mode, "opens")) {
    // Many encoders, one after another, each fed 30 pictures: how often does
    // the first picture fail?
    int fails = 0, runs = 30;
    for (int c = 0; c < runs; c++) {
      RiftFfenc* e = start(1920, 1080, 30, 1000000);
      if (!e) { fails++; continue; }
      long bytes = 0;
      for (int n = 0; n < 30; n++) {
        fill(pic, 1920, 1080, n, 0);
        int r = encode(e, pic, (int64_t)n * 33333, n == 0, &bytes);
        if (r) { printf("run %d: picture %d failed (%d)\n", c, n, r); fails++; break; }
      }
      close_(e);
    }
    printf("%d of %d runs failed\n", fails, runs);
  }
  return 0;
}
```

```sh
cc -O2 -I ~/path/to/rift-app/native/ffenc check.c -o check -ldl
./check rate  | tee rate.txt
./check still | tee still.txt
./check opens | tee opens.txt
```

Report:

- **rate:** each second's Mbps against what was asked. On Intel (Iris Xe):
  20 → 20.3, 5 → 4.8 to 5.2 (6.8 in the second the rate fell), 12 → 13.8,
  6 to 8 ms a picture. The 12 overshoots because of the quantiser floor Rift
  sets for still pictures (`native/ffenc/ffenc.c`); say how far AMD's runs
  over at each step. **If the 5 and 12 Mbps stretches stay near 20, Mesa does not follow
  a bitrate changed mid-stream.** That is the most important line in the run.
  Also the ms a picture and the worst: at 60 fps there are 16.7 ms.
- **still:** Mbps for a picture that does not move. Intel: 0.01 after the
  first second.
- **opens:** how many of 30 failed, and at which picture.

## 2. Rift's real path, measured

The same bench as round 1, section 3, with the same server and the same
`ffplay` window. Only the environment differs: `RIFT_FFENC_LIB` set as above,
from `rust/` on this branch.

```sh
export LIVEKIT_URL=ws://127.0.0.1:7880 LIVEKIT_API_KEY=devkey LIVEKIT_API_SECRET=secret
export RIFT_FFENC_LIB=~/rift-gpu-test/round2/ffenc/librift_ffenc.so

BENCH_ROOM=amd2-1 BENCH_SECS=120 RUST_LOG=info \
  cargo test bench_view -- --ignored --nocapture 2>&1 | tee ~/rift-gpu-test/round2/view_h264.log

XDG_SESSION_TYPE=x11 BENCH_ROOM=amd2-1 BENCH_SECS=120 BENCH_WINDOW=benchsrc \
  BENCH_CODEC=h264 BENCH_HEIGHT=1440 BENCH_FPS=60 BENCH_MBPS=20 RUST_LOG=info \
  cargo test bench_share -- --ignored --nocapture 2>&1 | tee ~/rift-gpu-test/round2/share_h264.log
```

- The share's log must say `screenshare: encoding on VAAPI on …` with AMD's
  driver named, and `publishing H264 from the GPU`. If it says
  `sharing as VP9 instead`, keep the lines before it and stop there.
- The `bench share:` line every 2 s gives fps sent, Mbps sent against
  WebRTC's target, and how long packets queued: the Mbps should follow the
  target as it moves, and the queue stay near 0.
- Then the same at `BENCH_FPS=120 BENCH_HEIGHT=1080 BENCH_MBPS=30` (room
  `amd2-2`): 120 fps is where a friend's Windows share went wrong.
- Keep any lines from FFmpeg or about the encoder:
  `grep -E 'ffmpeg:|encoder:|left out' share_h264.log`

From the viewer's log, per run: fps decoded, freezes (count and seconds), lost
packets, keyframes, PLIs, Mbps. Round 1's H264 through LiveKit's encoder, for
comparison: 34.5 fps encoded of 60, the viewer stalling 2 to 6 s every 8 to
25 s.

## 3. The Rust live tests (optional)

```sh
GPU_LIVE_ONLY=gpu cargo test live_gpu_h264 -- --ignored --nocapture --test-threads=1 \
  2>&1 | tee ~/rift-gpu-test/round2/live_h264.log
```

It needs the same server and `RIFT_FFENC_LIB`. The last `gpu live test:` line
must show over 100 recognisable frames unencrypted and with the key, and 0
without it or with the wrong one.

## 4. In the app (optional, but the only way to see the picture)

As round 1, section 4, but build the app from this branch with
`flutter build linux --release`. The bundle carries `lib/librift_ffenc.so`
itself, so `RIFT_FFENC_LIB` is not needed. The sharer's log should say
`encoder: VAAPI on /dev/dri/renderD… (…) encodes H264` at startup, and
`encoding on VAAPI on …` when the share starts. Watch for a few minutes with
something moving, and screenshot anything wrong.

## Reading the results

| Library (1) | Bench (2) | Means |
|---|---|---|
| rate follows, opens clean | smooth, Mbps follows the target | done on AMD: ship it in a beta |
| rate stays at 20 | Mbps above the target, queue growing | Mesa ignores a moved rate: reopen the encoder on a big change instead |
| some opens fail | — | the same driver fault as Intel's; say how often and whether reopening covered it |
| clean | stalls like round 1 | not the encoder: compare with VP9 (room `amd2-3`) |
