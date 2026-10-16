# GPU encoding results: the AMD PC

The answer to `GPU_ENCODING_AMD_PC.md`. One section per part: Part A (Linux)
and its round 2, then Part B (Windows).

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

## Part B: Windows (AMF, and Media Foundation behind it), Oct 16 2026 (evening)

Run by an agent on `gpu-encoding-amd` at `39d5b7b5`, the merged code, with
round 2's stop rule: the probe reads the encoder's raw output, so a `FAIL`
there is expected, and the share rewrites the keyframe. Steps 1 to 4 were run;
step 5 (the app) was not.

**Verdict: the shipped rewrite holds on Windows too, for AMF and for Media
Foundation.** Both encoders write slice type 7 in every IDR, as Mesa does. No
share logged `could not be rewritten`, both live tests passed with no
unreadable keyframes, and in every churn run the viewer already watching
asked for no keyframes while 15 others joined and left. Two things are left
open. AMF reaches only about 94 fps at 1080p120. And Media Foundation's test
failed twice on its second encoder, then passed four times.

### The machine

| | |
|---|---|
| GPU | AMD Radeon RX 9070 XT, driver 32.0.31041.1004, beside the CPU's own Radeon graphics (32.0.21045.5002), as on Oct 11 |
| OS | Windows 11 Pro 26200.9457 |
| Screen | one 5120x1440 at 240 Hz, captured whole: 4096x1152 published at 60 fps (`encoder::MAX_SIZE`), 3840x1080 at 120 |
| Server | livekit-server 1.13.7 on 127.0.0.1, `--dev`, a fresh one per run |
| Toolchain | MSYS2 UCRT64 for the library and the probe, plus its Python 3.14.8 for `check_h264.py` (installed for this run); Rust 1.97.1 |
| Build | **every Rust step in release** (`--release`). It builds on Windows, so the old "never `--release` on Windows" no longer applies here |

### 1. The library and the tests

`native/ffenc/build.sh` built `rift_ffenc.dll` at ABI 3 (4.3 MB), and it
loads. `cargo test --release`: 146 passed, 0 failed, 15 ignored.

### 2. AMF

**The probe**, `h264_amf`, the RX 9070 XT:

| Size, pictures | IDR slice type | Other slices | `check_h264.py` |
|---|---|---|---|
| 1920x1080, 120 | 7 (6 of 6) | 5 | FAIL: 6 of 6, expected |
| 2560x1440, 600 | 7 (30 of 30) | 5 | FAIL: 30 of 30, expected |

So AMF writes its IDR slice headers like Mesa does. Nobody knew this before.
**Colour tags**: `color_range=tv`, and `smpte170m` for the colour space,
transfer and primaries.

**The live test** (`GPU_LIVE_ONLY=gpu`, `live_gpu_h264`) passed with AMF opened
as the default (NVENC tried first and failed: "Cannot load nvcuda.dll"). Decoded
and recognisable: 233 unencrypted, 215 with the key, 12 decoded without it (0
recognisable), 0 with the wrong one.

**The churn bench.** `bench_view`, `bench_share` and `bench_churn`, encrypted,
60 s each, from one release test binary. The moving picture was `ffplay -fs`
drawing `testsrc2=size=2560x1440:rate=120,noise=alls=10:allf=t` over the whole
screen, since no Counter-Strike clip was left on the machine. The still
picture was this repository's `ARCHITECTURE.md` maximised in Notepad. Lows are
2-second samples.

| | Moving, 1440p60 / 20 Mbps | Moving, 1080p120 / 30 Mbps | Still text, 1440p60 / 20 Mbps |
|---|---|---|---|
| Viewer decoded | 53.4 fps | **94.0 fps** | 59.1 fps |
| Lowest sample; samples under 90% of best | 48.0; 5 of 30 | 88.0; 1 of 30 | 50.0; 8 of 30 |
| Freezes, PLIs | **0, 0** | **0, 0** | 7, **0** |
| Packets lost | 0 | 1 | 0 |
| Joiners' first picture, median and slowest | 160, 192 ms | 138, 158 ms | 266, 411 ms |
| Keyframes made by the sharer | 29 | 29 | 28 |
| Encoder's `send` per picture, longest | 9.6 to 11.1 ms, 17.8 | 9.5 to 10.1 ms, 27.9 | 5.1 to 5.2 ms, 17.9 |

- **At 1440p60 the rate gate kept the rate, nothing stalled.** The gate runs
  before the encoder. Encoded pictures plus those left out came to about 60 a
  second, so capture kept up. Full-screen noise at 4096x1152 costs more than
  20 Mbps, so the gate left out about 6 pictures a second. Part A's window was
  2560 wide, which is why it held 60.
- **At 1080p120 AMF itself is the limit.** Its `send` took about 9.8 ms a
  picture, which caps it near 100 fps. The encoder took 447 to 484 pictures per
  5 s. On Oct 11 the same GPU sent 117.4 fps at 120, but that was a 1080p60 clip
  at double speed in the debug bench, and the harness then timed 3.1 ms a
  picture.
- **About two keyframes per join** (29 in 60 s for 15 joins), against 14 on
  Linux. The watching viewer asked for none of them.

### 3. Media Foundation

Reached by pointing `RIFT_FFENC_LIB` at a file that does not exist. The log
said `no FFmpeg here: FFmpeg's library did not load from …: LoadLibraryExW
failed`, then `opened AMDh264Encoder (VEN_1002)`.

**`each_hardware_encoder_makes_decodable_h264`** lists two encoders, both
`AMDh264Encoder` with vendor VEN_1002: one per AMD adapter, most likely.

| Run | Encoder 0 | Encoder 1 | Result |
|---|---|---|---|
| 1 and 2, just after the AMF bench | 173 pictures, keyframes at 0 and 90 | **103** pictures, keyframes at 0 and 52 | failed: `AMDh264Encoder: 103 frames` (the test wants 150 of 180) |
| 3 to 6, about ten minutes later | 180, at 0 and 90 | 180, at 0 and 90 | passed |

- Encoder 0 passed every check in every run, including the readable PPS id
  after `h264::for_encryption`.
- In the failing runs encoder 1 managed about 31 pictures a second at 1080p60.
  It failed the picture count, so its keyframes were never checked.
- In the passing runs both encoders wrote byte-identical streams (21,366,853
  bytes), so both may have been encoding on the same adapter.
- Which adapter each index is was not found. The test logs only the name and
  vendor, and sampling Windows' per-adapter video-encode counters during a run
  caught nothing.
- The test was left as it is. A share falls back to Media Foundation only when
  AMF fails, and then takes the first encoder that opens: encoder 0, which
  passed. The bench share's log opened the first one listed, with no `would
  not open` before it.

Every dumped stream (`gpu-*.h264`) went through `check_h264.py`: slice type 7
in every IDR (2 of 2 each), 5 elsewhere. The encoder writes this raw, and the
share rewrites it.

**The live test** passed: 216 decoded unencrypted, 216 with the key, 12 decoded
without it (0 recognisable), 0 with the wrong one.

**The churn bench**, the same moving picture:

| | Moving, 1440p60 / 20 Mbps | Moving, 1080p120 / 30 Mbps |
|---|---|---|
| Viewer decoded | 46.7 fps | 69.4 fps |
| Lowest sample; samples under 90% of best | 38.0; 19 of 30 | 47.5; 11 of 30 |
| Freezes, PLIs | **0, 0** | **0, 0** |
| Joiners' first picture, median and slowest | 154, 223 ms | 135, 193 ms |
| Left out by the gate | 36 to 99 per 5 s once the target settled | 0 once at 30 Mbps, yet 68 fps sent |

AMF beat Media Foundation at both sizes, as on Oct 11.

### 4. The rate gate's keyframe lines (AMF)

| Picture, setting | Keyframe size | Left out per 5 s, once settled (within 1 s of a keyframe) | WebRTC's target |
|---|---|---|---|
| Moving, 1440p60 / 20 Mbps | 140 to 210 KB | 7 to 39 (5 to 29) | 20 Mbps |
| Moving, 1080p120 / 30 Mbps | 110 to 175 KB | 0 to 21 (0 to 16) | 30 Mbps |
| Still text, 1440p60 / 20 Mbps | 220 to 238 KB | 0 to 5, all within 1 s of a keyframe | 5.8, climbing to 12.4 Mbps |

On the still screen AMF's keyframes are a little larger than Mesa's (207 KB).
The 7 freezes are fewer than Linux's 14, and no keyframe was asked for.
Nothing was changed.

### An experiment: AMF's `async_depth` above 60 fps (not kept)

`ffenc.c` sets `async_depth` to 1 for every encoder. In FFmpeg 9.0.2's
`amfenc.c` that makes `receive_packet` wait for each picture's output once
`hwsurfaces_in_queue >= hwsurfaces_in_queue_max`, and `avcodec_send_frame`
runs that wait. That looked like the wait NVENC had at idle clocks. So AMF was
tried with `async_depth` 2 when `delay_frames >= 2` (above 60 fps), with the
DLL rebuilt:

| AMF | `async_depth` 1 | `async_depth` 2 |
|---|---|---|
| 1080p120 / 30 Mbps: `send` per picture | 9.5 to 10.1 ms | 8.4 to 9.0 ms |
| 1080p120: viewer, lowest sample | 94.0 fps, 88.0 | 92.3 fps, 77.0 |
| 1080p120: freezes, PLIs; joiners median | 0, 0; 138 ms | 0, 0; 115 ms |
| 1440p60 / 20 Mbps: `send`; viewer | 9.6 to 11.1 ms; 53.4 fps | 10.0 to 10.5 ms; 54.5 fps |

It did not help, so it was not committed, and `ffenc.c` is as it was. The
time per picture is therefore mostly not AMF's own queue. **Not explained:**
where the ~9 ms goes at these sizes, for example the copy into AMF's surface
or the GPU's clocks. Nothing here isolates it.

**Capture's rate at 120 fps, for the throttling fix.** No log line counts
capture, and the encoder is still the limit, so only a floor can be read. With
`async_depth` 2, pictures encoded plus pictures left out came to about 101 to
103 a second. Pictures replaced in the waiting slot before the encoder took
them are counted nowhere. So capture ran at least that fast, against the
92-a-second ceiling the laptop had under throttling. Nothing logged `power
throttling left to Windows`. Whether capture reaches 120 here is not shown.

### Not covered

- The app (step 5): an encrypted share with someone joining and leaving, at
  60 and 120 fps, and the app's `encoder: AMF (…) encodes H264` line.
- Real game content. The moving picture was full-screen noise, which costs
  more than the cap at 4096x1152.
- A slow link. Everything ran over loopback.
- Which AMD adapter each Media Foundation index is, and why encoder 1 slowed
  down twice.

### How it was run

- No proxy variables were set. The bench scripts started a fresh LiveKit per
  run and the three bench processes from one copy of the release test binary,
  3 s and then 8 s apart.
- `ffplay` and Notepad covered the screen during the runs, and were closed
  after.
- Logs, the probe's output, the dumps and the scripts stay on the machine in
  the test folder (`oct16`), and none are committed.
