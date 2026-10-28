# H264 High on Windows: results

Oct 28 2026, the user's laptop booted into Windows 11 (26200): NVIDIA RTX 3070
Ti Laptop GPU (driver 610.74) and Intel Iris Xe (driver 31.0.101.4502). This
branch at 5ea180b6, release builds. Everything passed and nothing needed a fix.

## 1. Build

- `cargo build --release` in `rust/` fetched the LiveKit fork at b73b6f02 and
  built.
- `scripts/build_windows.ps1` built `RiftChat.exe` and `rift_ffenc.dll` (ABI 4)
  through MSYS2.
- `cargo test --release`: 148 passed, 14 ignored.

**One snag, not in the code.** The first `build_windows.ps1` left the Oct 25
`rust_lib_rift.dll` in place: cargokit did not rebuild the crate in its own
target folder (`rust/target/x86_64-pc-windows-msvc`), though the sources had
changed. The app then refused the new encoder library and offered no H264:

```
encoder: no FFmpeg here: FFmpeg's library is version 4, not 3
```

`cargo build --release --target x86_64-pc-windows-msvc` in `rust/` and the
build script again put the new library in. A Windows machine that built the
app before this branch should check the log's `encoder:` line before testing.
CI builds from clean and is not affected.

## 2. The Rust live tests

`cargo test --release live_gpu_ -- --ignored --test-threads=1` against a local
`livekit-server --dev` 1.13.7, with `GPU_LIVE_ONLY` unset, so the baseline and
libwebrtc controls ran too. Both tests passed on each GPU.

| | NVENC (RTX 3070 Ti) | Quick Sync (Iris Xe, `RIFT_FFENC_ENCODER=h264_qsv`) |
|---|---|---|
| SPS `profile_idc` | 100 | 100 |
| Sharer's SDP | `profile-level-id=640032` | `profile-level-id=640032` |
| Pictures recognised: unencrypted / with the key | 215 / 214 | 232 / 231 |
| Without the key / with the wrong one | 0 of 11 / none arrived | 0 of 10 / none arrived |
| Baseline and libwebrtc controls | passed, `42e01f` | passed, `42e01f` |
| Resize 1080p → 720p on the same track | 92 frames | 92 frames |
| A late viewer's first picture | 244 ms after joining | 248 ms after joining |
| GPU fails, then no GPU | VP9, 93 then 62 frames | VP9, 92 then 62 frames |

So Quick Sync took its `profile` option; no reading of `qsvenc_h264.c` was
needed.

**AMF, by reading only.** `ffenc.c` sets `AVCodecContext::profile` to
`AV_PROFILE_H264_HIGH` for every encoder. FFmpeg 9.0.2's `amfenc_h264.c`
maps it to `AMF_VIDEO_ENCODER_PROFILE_HIGH` and passes it to
`AMF_VIDEO_ENCODER_PROFILE`; its own `profile` option is consulted only when
the context's is unset. None of Rift's FFmpeg patches touch the profile. The
AMD PC still has to run it.

Each run logged `failed to negotiate the publisher: … Called in wrong state:
closed` once or twice as a room closed. The tests passed regardless; it is a
renegotiation left queued as a share's connection closes.

## 3. The app

The user's own server, Garcie's Server, in its "Fuck San" call. The source was
`ffplay` looping the bench clip in a borderless 1920x1080 window, shared as a
window at 1080p60, 15 Mbps, H264 (chosen by Auto), with sound on.

**Windows sharing, Gracie watching.** Gracie is the user's other Windows PC,
on 1.5.2-beta.9, without this branch.

| Encoder | Sharer's log | Gracie |
|---|---|---|
| NVENC | `track: publishing H264 from the GPU, High profile at 15000000 bps, 60 fps, keeping Smoothness` | picture in about a second, smooth, no artefacts |
| Quick Sync | the same line | smooth, no artefacts |

Pictures left out to keep within the rate, from the sharer's log:

- NVENC: 1 to 6 every 5 s in the first half-minute, 11 as Gracie joined (2
  keyframes), then 0. NVENC took 4 ms a picture at first and 11 ms later in
  the share, within a 60 fps picture's 16.7 ms.
- Quick Sync: 9 in the first 5 s, all within a second of a keyframe, then 0,
  at about 300 pictures every 5 s. It took 7 to 8 ms a picture.

So High from the GPU plays on a Rift without the change too: watching needs
nothing new.

**Windows watching.** A second Rift on the laptop with `RIFT_PROFILE=b`, a
privacy-mode identity joined to the server as "Gracie Test", in the same call.

- Rift B watched Rift A's Quick Sync High share. The picture played and kept
  moving across screenshots 20 s apart, with no decode errors in B's log.
- Rift A watched Rift B's NVENC High share. Rift's stream stats read 1920x1080,
  58 to 59 fps, 12.9 to 14.2 Mbps, codec H264. It kept moving, with no decode
  errors in A's log.

Stopping Rift A's share logged the same `failed to negotiate the publisher …
closed` as the live tests, and nothing else.

## 4. What High costs, against Baseline

The Oct 16 bench (`bench_test.rs`): `bench_share` and `bench_view` in two
processes, so the viewer's decoding is not billed to the share. A whole
1920x1080 screen at 60 fps, 20 Mbps, against a local `livekit-server --dev`.
A local-only switch, not committed, opened the encoder and published the
track in Baseline for the comparison. Each run was 60 s after warming up.
"clip" is the bench clip and "noise" `testsrc2` with noise, which fills the
rate. A sampler read each process's CPU time and the GPU engines' load from
Windows' counters about every 2 s. CPU is a share of one core; this laptop
has 20.

Every run went out in the profile asked for, and every viewer decoded 59 to
60 fps with nothing dropped and no freezes.

**Encoding.** High costs the GPU next to nothing, and the sharer's CPU does
not change; it is mostly the capture.

| | Baseline | High |
|---|---|---|
| NVENC's engine | 41.9%, 42.1% | 43.6%, 43.6% |
| NVENC, ms a picture | 11.2 | 11.5 |
| Quick Sync's engine (Windows names it "VideoDecode") | 12.1% | 12.5% |
| Intel's 3D engine, Quick Sync runs | 50.5%, 52.5% | 52.8%, 52.2% |
| Quick Sync, ms a picture | 6.9 to 7.3 | 7.3 |
| The sharer's CPU | 24 to 31% | 23 to 30% |

The Intel figures include `ffplay` showing the source on the same GPU (about
35% 3D and 3.6% "VideoDecode" in the NVENC runs).

**Decoding.** The bench viewer decodes in software (`FFmpeg`, as libwebrtc
reports it), and High costs it about a third more CPU, half as much again
when the rate is full. CABAC, which High uses and Baseline does not, takes
more work a bit to unpack.

| Run | Baseline | High | Sent, Baseline / High |
|---|---|---|---|
| NVENC, clip | 23.1%, 23.0% | 30.7%, 32.4% | 14.0, 14.5 / 14.6, 14.8 Mbps |
| Quick Sync, clip | 23.7%, 27.3% | 31.7%, 36.3% | 16.9, 16.9 / 15.2, 15.2 Mbps |
| NVENC, noise | 31.6% | 47.9% | 18.3 / 18.3 Mbps |
| Quick Sync, noise | 30.8% | 43.9% | 18.1 / 18.3 Mbps |

**The rate.** Quick Sync in High sent 10% less on the clip. NVENC sent the
same in both, likely because it reaches the QP floor (18) on this clip
before the rate; the picture's quality was not measured.

So High is free to send and costs a watcher's CPU. On this machine it
played smoothly either way. Not measured: the app's viewer, which decodes
through Flutter's libwebrtc, not the Rust SDK's, and a slower viewer. Scripts
and logs: `%USERPROFILE%\rift-gpu-test\high\perf\`.

## Not checked

- AMF running, which needs the AMD PC.
- A phone watching a Windows share.
- How many pictures a second the watching Rift drew, counted by its presents
  rather than read from its stats.
- A share of the whole screen, a game, or below 1080p, in the app.
- The rate High saves at the same quality, measured only offline (Oct 19).
- High's decoding cost in the app's viewer, or on a slower machine.
