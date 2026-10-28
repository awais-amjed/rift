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

## Not checked

- AMF running, which needs the AMD PC.
- A phone watching a Windows share.
- How many pictures a second the watching Rift drew, counted by its presents
  rather than read from its stats.
- A share of the whole screen, a game, or below 1080p.
- The rate High saves, measured only offline (Oct 19).
