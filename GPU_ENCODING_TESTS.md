# GPU encoding tests — AMD on Linux

A brief for whoever runs these on the AMD machine, person or agent. It lives on
the `gpu-encoding` branch only and goes when the question is answered.

## The problem

Sharing a screen in H264 from a Linux PC with an AMD GPU, the viewer's picture
sometimes **freezes**, **pixelates**, or takes on a **wrong hue**.

On that machine Rift's own encoders are not involved. H264 there is made by
**LiveKit's VAAPI encoder**, inside `third_party/webrtc-sys/src/vaapi/` (see
`rust/src/screenshare/encoder/mod.rs`: Rift's own encoders are NVENC on Linux
and Media Foundation on Windows; Intel and AMD on Linux go to LiveKit's
VAAPI). That encoder has never been driven live by us. Reading it:

- It is adapted from libva's `h264encode` sample: it writes the SPS, PPS and
  slice headers itself (a comment in it says the VUI "isn't correct"), always
  runs CBR, and puts an IDR every 5 s.
- Each frame is converted to I420 on the CPU, copied into a VA surface with
  `upload_surface_yuv`, and encoded synchronously on WebRTC's encoder thread.
- `upload_surface_yuv` ignores the source's row strides, and when
  `vaDeriveImage` fails it fills a separate `VAImage` and **never calls
  `vaPutImage`**, so the surface is encoded with whatever it held before.
  Mesa's AMD driver refused `vaDeriveImage` on encode surfaces until late 2023
  (Mesa MR 26008, commit c638e61, tagged for stable).
- AMD's VAAPI encoder itself has a known fault: whole frames coming out a solid
  red, green or blue, reproduced with plain FFmpeg (Mesa issue 6734).

The question to answer: **is it the driver, LiveKit's encoder, or the network?**
That decides the fix: encode with FFmpeg's `h264_vaapi` ourselves and hand the
frames to LiveKit pre-encoded (as `gpu_feed.rs` already does for NVENC), a newer
Mesa, or VP9 on AMD.

## Rules for the run

- Ask before installing anything, and before anything that needs `sudo`.
- Recordings and logs stay on this machine, in one folder (e.g. `~/rift-gpu-test/`).
  Upload nothing.
- Do not change system settings, drivers or Mesa.
- When done, write the results into `GPU_ENCODING_RESULTS.md` next to this file,
  commit it on `gpu-encoding` and push. **No `Co-Authored-By` or other
  attribution lines in the commit message.** Recordings are not committed.

## 1. The machine

```sh
lspci -nnk | grep -A3 -Ei 'vga|display'
vainfo 2>&1 | head -40            # libva-utils; driver name, Mesa version, H264 encode entrypoints
uname -r; echo "$XDG_SESSION_TYPE"
ffmpeg -hide_banner -encoders 2>/dev/null | grep -i vaapi
```

Also note the Mesa package version (`pacman -Q mesa libva-mesa-driver`, or
`dpkg -l | grep -E 'mesa-va|libgl1-mesa'`). **Mesa older than 23.3 without the
backport makes the missing `vaPutImage` the prime suspect.**

## 2. The driver alone, with FFmpeg

No Rift, no network: does AMD's VAAPI encoder make clean H264 by itself?
`testsrc2` moves and is full of colour, and since it is generated, every
encoded frame can be compared with the exact original.

```sh
mkdir -p ~/rift-gpu-test && cd ~/rift-gpu-test
SRC='testsrc2=size=2560x1440:rate=60'
VA='-vaapi_device /dev/dri/renderD128'

# A: NV12 upload, VBR — how FFmpeg would be used
ffmpeg -hide_banner $VA -f lavfi -i $SRC -t 120 -vf 'format=nv12,hwupload' \
  -c:v h264_vaapi -rc_mode VBR -b:v 20M -maxrate 20M -bf 0 -g 300 a_nv12_vbr.mp4
# B: CBR, IDR every 5 s — close to LiveKit's settings
ffmpeg -hide_banner $VA -f lavfi -i $SRC -t 120 -vf 'format=nv12,hwupload' \
  -c:v h264_vaapi -rc_mode CBR -b:v 20M -bf 0 -g 300 b_nv12_cbr.mp4
# C: I420 upload — the format LiveKit's encoder hands over
ffmpeg -hide_banner $VA -f lavfi -i $SRC -t 120 -vf 'format=yuv420p,hwupload' \
  -c:v h264_vaapi -rc_mode CBR -b:v 20M -bf 0 -g 300 c_i420_cbr.mp4
```

If the user has a gameplay recording, repeat A and B on it as well
(`-i clip.mp4 -vf 'scale=2560:1440,format=nv12,hwupload'`); real motion
stresses the encoder more than the pattern does.

Check each file:

```sh
# Decoder errors (should print nothing)
ffmpeg -v error -i a_nv12_vbr.mp4 -f null - 2>&1 | head

# Per-frame quality against the original; a corrupt or solid-colour frame is a
# sharp drop
ffmpeg -hide_banner -i a_nv12_vbr.mp4 -f lavfi -i "$SRC" -t 120 \
  -lavfi '[0:v][1:v]psnr=stats_file=a.psnr' -f null -
python3 - a.psnr <<'EOF'
import sys, statistics
v = [float(l.split('psnr_avg:')[1].split()[0]) for l in open(sys.argv[1]) if 'psnr_avg:' in l]
m = statistics.median(v)
bad = [(i, x) for i, x in enumerate(v) if x < m - 8]
print(f'{len(v)} frames, median {m:.1f} dB, {len(bad)} outliers')
for i, x in bad[:30]: print(f'  frame {i}: {x:.1f} dB')
EOF
```

Pull out a few outlier frames and look at them, next to a normal one:

```sh
ffmpeg -v error -i a_nv12_vbr.mp4 -vf "select='eq(n\,FRAME)'" -vframes 1 a_frame_FRAME.png
```

Say for each file: decoder errors, outlier count, and what the bad frames look
like (solid colour, smeared blocks, shifted hue, torn rows).

## 3. Rift's real path, measured

The share bench (`rust/src/screenshare/bench_test.rs`) runs Rift's actual share
code (capture, LiveKit's encoder, encryption) into a LiveKit server, with a
viewer in another process reporting fps, freezes, lost packets, keyframes and
PLIs. It needs Rust and Docker; no Rift server and no app.

```sh
# A throwaway LiveKit server in dev mode (keys devkey / secret)
docker run --rm -d --name lk-bench -p 7880:7880 -p 7881:7881 -p 7882:7882/udp \
  livekit/livekit-server --dev --bind 0.0.0.0

# Something moving, in an X11 window the capturer can see
SDL_VIDEODRIVER=x11 ffplay -window_title benchsrc -f lavfi -i 'testsrc2=size=1920x1080:rate=60' &
```

Then, in `rust/`, the viewer first, then the share, each in its own terminal:

```sh
export LIVEKIT_URL=ws://127.0.0.1:7880 LIVEKIT_API_KEY=devkey LIVEKIT_API_SECRET=secret
BENCH_ROOM=amd-1 BENCH_SECS=120 RUST_LOG=info \
  cargo test bench_view -- --ignored --nocapture 2>&1 | tee ~/rift-gpu-test/view_h264.log

XDG_SESSION_TYPE=x11 BENCH_ROOM=amd-1 BENCH_SECS=120 BENCH_WINDOW=benchsrc \
  BENCH_CODEC=h264 BENCH_HEIGHT=1440 BENCH_FPS=60 BENCH_MBPS=20 RUST_LOG=info \
  cargo test bench_share -- --ignored --nocapture 2>&1 | tee ~/rift-gpu-test/share_h264.log
```

- The share's `bench share: layer … encoder …` line must name a VAAPI encoder.
  If it says OpenH264, H264 is not coming from the GPU and the rest of the run
  is not about AMD; say so.
- Repeat with `BENCH_CODEC=vp9` (room `amd-2`) as the control: same capture
  and network, CPU encoder.
- Repeat H264 at `BENCH_HEIGHT=1080 BENCH_FPS=30 BENCH_MBPS=8` (room
  `amd-3`), to see whether the trouble depends on load.
- From the share's log, keep any lines about VAAPI:
  `grep -iE 'vaapi|entrypoint|ratecontrol|rate control|failed to encode|vacreateimage|fourcc' share_h264.log`

From the viewer's log, report per run: fps decoded, freezes (count and
seconds), lost packets, keyframes, PLIs, Mbps, and the decoder named.

## 4. In the app (optional, but the only way to see the picture)

The bench reports numbers, not the picture. If a Rift server is at hand (the
one the problem was seen on), build the app from this branch
(`flutter build linux --release`; README and `LOCAL_DEV.md`), run two profiles
(`RIFT_PROFILE=a` and `RIFT_PROFILE=b`, `GDK_BACKEND=x11`), share a window
with something moving from one in H264, watch from the other for a few
minutes, and screenshot anything wrong. Keep both logs; the sharer's should say
`encoder: LiveKit lists [...]` with `Vaapi` in it, and must not say
`H264 came from …, not the GPU`.

## Reading the results

| FFmpeg (2) | Bench / app (3, 4) | Means |
|---|---|---|
| clean | H264 bad, VP9 fine | LiveKit's VAAPI encoder → encode with FFmpeg `h264_vaapi` ourselves |
| C bad, A/B clean | H264 bad | the I420 upload path (driver or LiveKit's copy) → NV12, our own upload |
| A/B bad too | H264 bad | AMD's driver → newer Mesa, or VP9 on AMD |
| clean | H264 and VP9 both bad | not the encoder: network or capture |
| clean | clean | not reproduced here: note the settings and content used when it was seen |
