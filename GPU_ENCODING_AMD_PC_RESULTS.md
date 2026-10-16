# GPU encoding results: the AMD PC

The answer to `GPU_ENCODING_AMD_PC.md`. One section per part; Part B (Windows)
adds its own when it runs.

## Part A: Linux (VAAPI on Mesa), Oct 16 2026

Run by an agent on `gpu-encoding-amd`, steps 1 to 6. Step 7 (the app) was not
run.

**Verdict: the FFmpeg patch does not fix AMD, so Rift now rewrites the slice
header itself, and that works.** Mesa's encoder for the RX 9070 XT writes the
H264 slice header on its own, always slice type 7, whatever FFmpeg hands it. So
the patched library's keyframes stayed unreadable to encrypted viewers, exactly
like the unpatched one's. With the user's go-ahead, the fix went into Rust
(`h264::with_short_idr_slice_types`, below). With it, the viewer already
watching holds its rate while others join, asks for no keyframes, and joiners
see a picture in about 0.2 s.

### The machine

| | |
|---|---|
| GPU | AMD Radeon RX 9070 XT (gfx1201) at `/dev/dri/renderD128`; the CPU's Raphael graphics at `renderD129`. Rift picked `renderD128` by itself |
| Driver | Mesa 26.2.4 (radeonsi), libva 2.24.1; H264 `EncSlice` for Constrained Baseline, Main and High. The driver lists packed slice headers among those it takes |
| OS | CachyOS, kernel 7.2.9-2, GNOME on Wayland; the bench captured X11 windows through Xwayland |
| Screen | 5120x1440 at 240 Hz; every window captured was 2560 wide, on the left half |
| Build | all Rust tests in release (`--release`); the probe at `-O1` |

### 1. Two libraries

`native/ffenc/build.sh` built both in about 11 s: the fixed one from this branch,
and the one from before the fix from a worktree at `289df856`, since removed.
Both export the eight `rift_ffenc_*` names, and they differ.

### 2. The probe: unreadable on both

| Library | IDR slice type | Other slices | `check_h264.py` |
|---|---|---|---|
| before the fix (`289df856`) | 7 (6 of 6) | 5 | FAIL: 6 of 6 |
| fixed (`c26b84ca`) | 7 (6 of 6) | 5 | FAIL: 6 of 6 |

The two libraries wrote the same slice headers byte for byte: `65 88 80 42`,
that is first_mb 0, slice type 7, PPS id 0 ending at the ninth bit, frame_num
0, and `idr_pic_id` 0 in every IDR, not the counting id FFmpeg asks for. The
SPS and PPS are FFmpeg's (they carry its colour tags), but the slice header is
the driver's. No FFmpeg option or patch reaches it, so of the brief's three
fixes only the last was left: rewriting the header in Rust.

### The fix

`h264::with_short_idr_slice_types`, called from `ParameterSets::complete`, so it
covers every encoder that goes through FFmpeg or Media Foundation. It acts only
on an IDR whose PPS id encryption would hide, and does the following:

- It writes each IDR slice's type in the short form (7 as 2).
- It gives `idr_pic_id` the bits the shorter type saves: v becomes
  v + (2^z − 1)·2^k. That keeps different ids different, which is all a decoder
  asks of two IDRs in a row.
- So the header stays the same length, and every bit after it is untouched,
  CABAC's byte alignment included.
- It reads the SPS for frame_num's width and the like. It leaves the access
  unit alone if anything is unexpected: scaling lists, slices that disagree, or
  an id it cannot lengthen.

Mesa's IDR becomes `65 b8 01 02`: type 2, the PPS id ending at the fifth bit,
and `idr_pic_id` 3.

Checked offline, using the same code over a whole file. All IDRs were made
readable, the decoder reported no errors, and every decoded picture was
identical to the original's (FFmpeg `framemd5`):

| Probe | Pictures | IDRs | File size |
|---|---|---|---|
| 1920x1080 | 120 | 6 | — |
| 2560x1440 | 600 | 86 | 73,211,984 bytes, the same before and after |

There are also seven new unit tests. One of them uses the driver's real SPS
(with emulation prevention bytes), PPS and IDR.

### 3. The colour tag

`color_range=tv`, and `smpte170m` for the colour space, transfer and primaries.
The pre-fix library's file says the same, so this tag predates `289df856`.

### 4. The live test

`GPU_LIVE_ONLY=gpu`, `live_gpu_h264` in release:

| Code, library | Result | Unreadable keyframes | Decoded (recognisable) unencrypted / with key / without / wrong key |
|---|---|---|---|
| before the fix (`c26b84ca`), pre-fix library | **failed** | 49 | 216 / 216 / 8 (0) / 0 |
| before the fix (`c26b84ca`), fixed library | **failed** | 49 | 219 / 216 / 8 (0) / 0 |
| with the rewrite, fixed library | passed | 0 | 217 / 217 / 19 (0) / 0 |
| with the rewrite, pre-fix library | passed | 0 | 217 / 216 / 19 (0) / 0 |

The frames decoded without the key are noise, and none of them were
recognisable.

### 5. The churn bench

The bench ran `bench_view`, then `bench_share`, then `bench_churn`, all
encrypted, 60 s each, with a fresh LiveKit 1.13.9 (Docker, dev mode) for each
run.

The picture was `ffplay` drawing
`testsrc2=size=2560x1440:rate=120,noise=alls=10:allf=t`, captured at 2560x1403;
no Counter-Strike clip was on the machine. "Before" is the code at `c26b84ca`;
"after" is the rewrite. Lows are 2-second samples.

| | Before, pre-fix library | Before, fixed library | After, fixed library |
|---|---|---|---|
| **1440p60, 20 Mbps** | | | |
| Viewer decoded | 42.0 fps | 50.1 fps | **59.8 fps** |
| Lowest sample; samples under 90% of best | 0.0 fps; 15 of 30 | 0.0 fps; 10 of 30 | **58.0 fps; 0** |
| Freezes, PLIs | 10, 46 | 6, 24 | **0, 0** |
| Joiners' first picture, median and slowest | 1308 ms, 4311 ms | 221 ms, 3715 ms | **201 ms, 236 ms** |
| Keyframes made by the sharer | 45 | 33 | 15 |
| Unreadable-keyframe warning | once | once | never |
| **1080p120, 30 Mbps** | | | |
| Viewer decoded | 87.1 fps | — | **109.0 fps** |
| Lowest sample; samples under 90% of best | 0.0 fps; 14 of 30 | — | **105.0 fps; 0** |
| Freezes, PLIs | 9, 29 | — | **0, 0** |
| Joiners' first picture, median and slowest | 683 ms, 3717 ms | — | **175 ms, 217 ms** |
| Keyframes made by the sharer | 36 | — | 14 |

Neither run lost a packet. At 1080p120 this noise costs more than 30 Mbps, so
the rate gate left out about 11 pictures a second both before and after
(596 and 657 in total), and the share sent 108 to 109 fps. That is the encoder
keeping to the rate, not a stall.

The encoder's time per picture (`send`, which is where VAAPI encodes) was
6.0 to 8.1 ms in the before runs and 3.8 to 5.0 ms in the after runs, the
longest 17.4 to 34.2 ms. The rewrite runs after the encoder, so the difference
is the GPU's, not the fix's.

### 6. The rate gate's keyframe lines (fixed library, with the rewrite)

| Picture, setting | Keyframe size | Left out after each | WebRTC's target | Viewer |
|---|---|---|---|---|
| Moving, 1440p60 / 20 Mbps | 117 KB average | 23 in 60 s, 17 within 1 s of a keyframe | 19.3 to 20 Mbps | 59.8 fps |
| Moving, 1080p120 / 30 Mbps | 90 KB | 185 of 657 within 1 s of one | 30 Mbps | 109.0 fps |
| Still text, 1440p60 / 20 Mbps | 207 KB | 4 to 7 | 6.0 to 6.4 Mbps | 59.1 fps, 14 freezes, 0 PLIs |
| Still text, 1440p60 / 8 Mbps | 207 KB | 6 to 8 | 5.3 Mbps | 58.6 fps, 14 freezes, 0 PLIs |
| Still text, 1080p120 / 30 Mbps | 124 KB | 0 once settled | 5.5 to 5.8 Mbps | 119.5 fps, 0 freezes |

The still text was this repository's `ARCHITECTURE.md` in gedit, in a
2560x1440 window.

On Intel the same still screen made keyframes of about 300 KB, with about 12
pictures left out after each. AMD's are about two thirds the size, with about
half as many left out.

A still screen sends so little that WebRTC's estimate never climbs past 5 to 6
Mbps, whatever is asked. At 1440p a 207 KB keyframe then takes about a quarter
of a second to send, and the viewer counts that as a freeze, one per join. It
asks for no keyframe and loses nothing. This is the cost the one-second buffer
was kept for, and it is recorded here with nothing changed.

### 7. The app

Not run. Whether the rewrite holds in the app with three real devices, and
whether a person sees the brief freeze at each join on a still screen, is not
yet proved.

### Not covered

- The app (step 7), and Firefox or browser viewers of a rewritten keyframe.
  libwebrtc's FFmpeg decoder took them, and so did FFmpeg offline.
- A slow link. Everything ran over loopback.
- Real game content. The moving picture was the noise pattern.

### How it was run

- The HTTP proxy variables were unset for every LiveKit process, as in rounds 1
  and 2. LiveKit's Rust client ignores `NO_PROXY`.
- The LiveKit image was pulled again (`livekit/livekit-server:v1.13.9`), since
  the one from round 2 was gone.
- The "before" test binary was built from `c26b84ca` and kept aside, so the
  before and after runs differ only in the rewrite.
- `ffplay` and gedit were started on their own, not as background jobs of the
  bench script.
- Logs, probe outputs and both test binaries stay on the machine in the test
  folder, and none are committed.

## Part A, round 2: the merged code on Linux, Oct 16 2026 (evening)

This round ran the code at `f805aaa9`. It is the same machine, windows and
settings as Part A, run in release, with the library rebuilt at ABI 3. The
keyframe rewrite measured here is the one that ships:
`h264::with_readable_pps_id`, run in `gpu_feed.rs` through
`h264::for_encryption`. Part A's `with_short_idr_slice_types` is gone.

**Verdict: the shipped rewrite works on AMD, and it matches Part A's "after"
numbers.** No run logged `could not be rewritten`.

| Check | Result |
|---|---|
| Library | `native/ffenc/build.sh`, ABI 3, loads |
| `cargo test --release` | 150 passed, 0 failed, 13 ignored |
| Probe | `FAIL`, 6 of 6 IDRs with slice type 7, as expected: it reads the encoder's own output, before the share rewrites it. Colour tags unchanged (`tv`, `smpte170m`) |
| Live test | passed; decoded and recognisable: 216 unencrypted, 217 with the key, 24 without it (0 recognisable), 0 with the wrong one |

The churn bench was set up as in Part A: `bench_view`, `bench_share` and
`bench_churn`, encrypted, 60 s, a fresh LiveKit for each run. The moving
pattern was captured at 2560x1403, and the still text in gedit at 2560x1440.

| | Moving, 1440p60 / 20 Mbps | Part A after | Moving, 1080p120 / 30 Mbps | Part A after | Still text, 1440p60 / 20 Mbps | Part A |
|---|---|---|---|---|---|---|
| Viewer decoded | **59.9 fps** | 59.8 | **108.8 fps** | 109.0 | **58.9 fps** | 59.1 |
| Lowest 2 s sample | 58.5 | 58.0 | 104.5 | 105.0 | 57.5 | 58.0 |
| Freezes, PLIs | **0, 0** | 0, 0 | **0, 0** | 0, 0 | 14, **0** | 14, 0 |
| Joiners' first picture, median and slowest | 183, 206 ms | 201, 236 | 174, 196 ms | 175, 217 | 400, 420 ms | 336, 403 |
| Keyframes made by the sharer | 14 | 15 | 14 | 14 | 14 | 14 |
| Keyframe size | 116 KB | 117 | 78 KB | 90 | 189 to 207 KB | 207 |
| Left out by the gate (within 1 s of a keyframe) | 21 (13) | 23 (17) | 627 (179) | 657 (185) | 114 (114) | 4 to 7 per keyframe |
| Encoder's `send` per picture, longest | 8.0 to 8.4 ms, 18.4 | 3.8 to 4.6, 17.4 | 5.3 to 5.8 ms, 17.7 | 4.5 to 5.0, 18.9 | 10.8 to 11.6 ms, 30.8 | 4.1 to 5.7, 6.2 |

No packet was lost in any run. The 1080p120 rate is the rate gate's, as in
Part A: this noise needs more than 30 Mbps at 120 fps.

On the still screen, the 14 freezes are again one per join, each from sending
a 207 KB keyframe at WebRTC's 5.5 to 5.9 Mbps, with no keyframe asked for.

**Not explained:** the encoder's time per picture was about twice Part A's at
1440p, on both the moving and the still picture. The rewrite runs after the
encoder, and the viewers' numbers did not change, so this was only recorded.
Whether it is the GPU's clocks or something in the merged code was not
isolated.

Not run, as before: the app (step 7), a slow link, and real game content.
Logs are kept on the machine and are not committed.
