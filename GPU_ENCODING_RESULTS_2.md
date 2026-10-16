# GPU encoding results, round 2 — Rift's FFmpeg encoder on AMD (Linux)

The answer to `GPU_ENCODING_TESTS_2.md`, run Oct 9 2026 on the same AMD machine
as round 1 by an agent: steps 0–3. Step 4 (the app) was not run.

**Verdict: done on AMD.** Mesa follows a bitrate moved mid-stream, every encoder
opened cleanly, and the bench is smooth at 60 and 120 fps, with the Mbps
following the target and nothing queued. That is the first row of the brief's
table. Round 1's stalls (9 freezes and 26 PLIs in 120 s) are gone: one short dip
per run remains.

## 0. The machine and the library

| | |
|---|---|
| GPU | AMD Radeon RX 9070 XT (gfx1201) at `/dev/dri/renderD128`; a Raphael iGPU at `renderD129`. Rift picked `renderD128` by itself in the bench |
| Driver | Mesa 26.2.4 (radeonsi), libva 2.24; H264 `EncSlice` for Constrained Baseline, Main and High |
| Kernel, session | 7.2.9 (CachyOS), GNOME on Wayland; the bench captured an X11 window through XWayland |
| `librift_ffenc.so` | built by `native/ffenc/build.sh` in 12 s; exports exactly the eight `rift_ffenc_*` names |

## 1. The library alone

`check.c` from the brief, with `DEVICE=/dev/dri/renderD128`, at 2560x1440, 60 fps.

**rate:** Mesa follows a moved rate.

| Asked | Made | Off by |
|---|---|---|
| 20 Mbps (s 0) | 35.22 | +76%: the first second only |
| 20 Mbps (s 1–3) | 19.95–19.97 | 0% |
| 5 Mbps (s 4–9) | 5.55–5.77 | +11% to +15%, no spike in the second it fell |
| 12 Mbps (s 10–15) | 11.31–12.09 | −6% to +1% |

The keyframe asked for at second 7 made no visible bump. A picture took 6.4 to
7.4 ms on average, 9.5 to 14.9 ms at worst, inside the 16.7 ms of 60 fps.

Compared with Intel: the same 20 Mbps step is exact, 5 runs over by a little more
(Intel 4.8–5.2, but 6.8 in the second it fell), and 12 runs under instead of over
(Intel 13.8). The first second's 35 Mbps has no Intel figure to compare with.

**still:** 0.13 Mbps in the first second, then 0.01 for the rest, apart from 0.13
in the second the keyframe was asked. 7.3 to 7.8 ms a picture, and one picture
of 17.5 ms in 960, the only one over 16.7 ms in the library runs.

**opens:** 0 of 30 failed. Intel's first-picture fault did not appear.

## 2. Rift's real path, measured

The share bench into a dev-mode LiveKit server (1.13.9, in Docker) on the same
machine, sharing an `ffplay` window of `testsrc2` at 1920x1080 drawn at 60 fps.
The window is 1080p, so the 1440 run published 1920x1080, as in round 1. The
window draws 60 fps, so at 120 fps half the captured pictures repeat the one
before. Each run is 120 s.

The share's log, both runs:

```
encoder: VAAPI on /dev/dri/renderD128 (Mesa Gallium driver 26.2.4-arch3.1 for AMD Radeon RX 9070 XT (…)) encodes H264
screenshare: encoding on VAAPI on Mesa Gallium driver 26.2.4-arch3.1 for AMD Radeon RX 9070 XT (…)
track: publishing H264 from the GPU at 20000000 bps, 60 fps, keeping Smoothness
```

No `sharing as VP9 instead`, no `ffmpeg:` line, and no `opening the encoder again`.

| | 60 fps, 20 Mbps (`amd2-1`) | 120 fps, 30 Mbps (`amd2-2`) | Round 1, LiveKit's encoder, 60 fps, 20 Mbps |
|---|---|---|---|
| Sent | 56.5 fps | 116.0 fps | 34.5 fps |
| Mbps sent, target | 18.91, 20.00 | 27.19, 30.00 | 19.26, 20.00 |
| Queued | 0 ms throughout | 0 ms throughout | — |
| Sharer keyframes | 3 | 3 | 18 |
| Sharer CPU | 19% of one core | 36% of one core | 18% of one core |
| **Decoded** | **56.0 fps** | **115.4 fps** | 25.5 fps |
| **Freezes** | **1** | **1** | 9 |
| **Lost packets** | 0 | 0 | 0 |
| **Viewer keyframes** | 1 | 1 | 10 |
| **PLIs** | **3** | **3** | 26 |
| Mbps received | 18.93 | 27.23 | 19.33 |

The overall Mbps sits under the target because WebRTC's target climbs from
about 7 Mbps over the first 15–20 s, and the sent rate follows it there
(6.57 against 7.02, 13.89 against 16.18, 18.82 against 20.00). Once the target
holds, each 2-second sample is within about 1 Mbps of it, above or below. The
dip in the target at 20 s in the 60 fps run (18.75) was followed.

**Pictures left out.** At 60 fps and 20 Mbps, this pattern costs more than 20 Mbps,
and Rift left out 26 to 30 pictures every few seconds (`left out … to keep VAAPI …
within 20000000 bps`, 23 lines), so it sent 54–59 fps rather than 60. That is
the encoder keeping to the rate as designed. At 120 fps and 30 Mbps it left out
pictures only while the target was still climbing (5 lines, the last 5 pictures
at 30 Mbps).

**The one freeze in each run** fell near 60 s: 26 fps decoded in the 58–60 s sample
at 60 fps, 106.5 in the 60–62 s sample at 120 fps. Each was followed within 2 s by
the full rate. The sharer's keyframes fell in the same sample, and the viewer's
3 PLIs account for them. Nothing was logged on either side, and no packet was
lost, so what made the viewer ask was not found. The freeze time printed as
`0.00 s` again, so the bench's duration figure still does not count a dip like
this, and the 2-second samples are the measure.

## 3. The Rust live test

`GPU_LIVE_ONLY=gpu cargo test live_gpu_h264` passed (64 s):

```
gpu live test: gpu: Decoded { any: 179, recognisable: 179 } unencrypted,
  Decoded { any: 152, recognisable: 152 } with the key,
  Decoded { any: 8, recognisable: 0 } without it,
  Decoded { any: 0, recognisable: 0 } with the wrong one
```

Over 100 recognisable frames unencrypted and with the key, and none recognisable
without it or with the wrong one. Without the key, 8 frames still decoded, all
noise.

## Not covered

- **The picture.** Step 4 was not run. Whether the one dip per run can be seen,
  and whether the colours are right, is not yet proved on AMD.
- **Real 120 fps content.** The window drew 60 fps.
- **A slow link.** All of this ran over loopback. The library shows that Mesa
  follows a lower rate. That the picture keeps up with the sound when WebRTC
  actually asks for one was not driven.

## How it was run

- The brief's commands, except for the following:
  - The bench ran with the HTTP proxy variables unset, as in round 1. LiveKit's
    Rust client ignores `NO_PROXY` for `ws://127.0.0.1`.
  - `ffplay` was started on its own, as in round 1.
- Recordings and logs were kept on the test machine and not committed.
