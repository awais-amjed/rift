# Watching a stream: the Windows split, on the Intel laptop, Oct 26 2026

Step 1 of `scripts/perf/WATCH_DRAW.md`, run on `watch-draw` at `49c2e435`
(no code change), against round 1's *What a call costs* and round 2's part E.
A Claude session drove Rift itself; the user set up the call.

**In short:** watching costs Rift 117% of a core in front, and **just as much
minimised (122%) or covered (105–118%)**: nothing stops it on Windows. It
redraws at the stream's rate, 47–64 frames a second, in every state, and
about 3 a second when not watching. Most of the cost is the picture itself:
with Settings in front the stream is still received and redrawn for, and
costs 30%. That leaves **about 87% of a core for converting, uploading and
drawing the video**, against about 19% on Linux. Behind `gameloop2`, the game
had 1.6–1.7% of frames over 1.5×, against about 0.08% with Rift closed.

## The machine

The same laptop as rounds 1–3: Intel Core i7-12700H (performance cores are
logical CPUs 0–11, efficiency cores 12–19), Iris Xe drawing Rift, 32 GB, on
AC, Windows 11 Home 26200.

**Build:** this branch, `cargo build -p rust_lib_rift --release --target
x86_64-pc-windows-msvc`, then `flutter build windows --release`.

**The call:** the user's account (Garcie) in the "Fuck San" voice channel on
their own server, the filter Off. Gracie (the user's other PC) shared CS2 at
1080p60, H264. Rift maximised, the mouse still on the members list, so the
stream's overlays had faded. The stats overlay was on (Settings, *Detailed
stream stats*).

**The stream was light for most of it.** Received data was 0.4–0.6 Mbit/s in
b, c and d (Gracie standing still), about 5 Mbit/s in e and f, against
17.7 Mbit/s in round 2. The decoder's share follows that; the drawing does not.

## Step 1: the split

Each state: 30 s of `threadtop` (`measure.ps1`), CPU in % of one core. Raster
is Flutter's raster thread (`flutter_windows.dll+0xfbe2f8`, tid 4816), Driver
the Intel driver's thread (`igd10um64xe.DLL`), Decoder `VideoDecoderQueue`.

| | State | Total | Raster | Driver | Decoder | GPU 3D | Received | Frames drawn |
|---|---|---|---|---|---|---|---|---|
| a | In the call, not watching | 7.6 | 2.9 | 0.6 | – | 2.0% | 17 kbit/s | 3.0/s |
| b | Watching, stream page in front | 116.7 | 85.2 | 14.5 | 6.7 | 62.3% | 433 kbit/s | 51.6/s |
| c | Watching, Settings in front | 29.7 | 11.5 | 4.3 | 4.9 | 23.2% | 609 kbit/s | 63.8/s |
| d | Watching, minimised | 122.3 | 89.9 | 14.8 | 6.5 | 68.1% | 445 kbit/s | 58.6/s |
| e | Watching, behind a maximised window | 104.6 | 72.1 | 11.6 | 9.3 | 56.3% | 4,961 kbit/s | 47.0/s |
| f | Watching, behind `gameloop2` (two runs) | 116.0, 117.6 | 69.8, 70.1 | 18.5, 18.8 | 11.1, 11.1 | – | – | 46.8/s |

In e the covering window was a plain maximised WinForms window started for
the test. In f the terminal running `gameloop2` was maximised in front. Frames
drawn are 10 s of `presents.ps1` (Present events 42 and 55 for Rift's PID),
taken after the CPU readings, in the same states; f's count is with the
terminal in front but `gameloop2` not running. The stream itself ran at
59–60 fps by the stats overlay, so 47–64 is the stream's rate, give or take
the 10 s window.

How it reads, as the brief splits it:
- **b − c, converting, uploading and drawing the video: about 87% of a
  core**, nearly all of it on the raster thread (85 against 11.5). Linux:
  about 19%. The Settings page still redraws 64 times a second but draws no
  video, so the engine never asks for the frame (`CopyPixelBuffer`) and never
  uploads it. This is the part ANGLE and the CPU I420-to-RGBA conversion
  cost on Windows (*Why*, points 2 and 3, in the brief).
- **c − a, redrawing the window at the video's rate: about 17%**, plus the
  decoder's 5 (Linux: about 21 without its decoder).
- **d and e: all of it still runs** when nobody can see Rift. Minimised draws
  the stream page exactly as in front (122% against 117%, 59 frames a second
  against 52). Covered costs 105% by a plain window and 116–118% by the
  terminal running `gameloop2`.
- **Nothing else redraws.** Not watching, Rift draws 3 frames a second, and
  watching it follows the stream. Round 1's 94 (minimised) and 156 (behind a
  window) were the old speaking ring on top.

**`gameloop2` beside it** (all CPUs, 60 s, Rift read for 30 s from 15 s in):

| | Slow (same core) | Over 1.5× | Over 2× | p99.9, performance cores | Rift |
|---|---|---|---|---|---|
| f, run 1 (terminal in front) | 6.32% | 1.70% | 0.57% | 12.0 ms | 116% |
| f, run 2 (terminal in front) | 5.62% | 1.57% | 0.54% | 15.3 ms | 118% |
| Rift in front by mistake | 7.06% | 1.28% | 0.36% | 17.6 ms | 123% |
| Round 2 E2 (new build, two music and two no-music runs) | 9.1–14.1% | 2.59–3.41% | 0.79–1.15% | 15.5–17.8 ms | 132–145% |
| Round 3, Rift closed | | 0.069–0.090% | | 7.5–7.8 ms | – |

The game is better off than in round 2 (fewer slow frames, Rift at 116–118%
against 132–145%), but the stream was about a third of round 2's bitrate, so
the decoder did less. It is still about 20 times the closed figure over 1.5×.

## Appendix: raw lines

```
WD a in call, not watching: frames drawn 3.0/s
WD b watching, stream page: frames drawn 51.6/s
WD c watching, settings page: frames drawn 63.8/s
WD d watching, minimised: frames drawn 58.6/s
WD e watching, behind a maximised window: frames drawn 47.0/s
WD f behind the maximised terminal (no gameloop2): frames drawn 46.8/s
```

```
WD a in call, not watching: CPU 7.6% of a core | GPU 3d 2.0% | rx 17 kbit/s tx 44 kbit/s | working set 753 -> 753 MB, private 734 -> 734 MB, threads 96
WD b watching, stream page: CPU 116.7% of a core | GPU 3d 62.3% | rx 433 kbit/s tx 1,007 kbit/s | working set 834 -> 834 MB, private 813 -> 813 MB, threads 100
WD c watching, settings page: CPU 29.7% of a core | GPU 3d 23.2% | rx 609 kbit/s tx 166 kbit/s | working set 684 -> 684 MB, private 661 -> 661 MB, threads 98
WD d watching, minimised: CPU 122.3% of a core | GPU 3d 68.1% | rx 445 kbit/s tx 136 kbit/s | working set 834 -> 834 MB, private 811 -> 811 MB, threads 96
WD e watching, behind a maximised window: CPU 104.6% of a core | GPU 3d 56.3% | rx 4,961 kbit/s tx 77 kbit/s | working set 836 -> 834 MB, private 815 -> 812 MB, threads 97
WD f watching behind gameloop2 r1: threads 20 frames 153661 | median 6.538 p99 18.563 p99.9 26.045 max 44.91 ms | >1.2x 41.29% >1.5x 23.308% >2x 7.954% | fastest 5.720
WD f watching behind gameloop2 r1: same-core 101389 >1.2x 7.06% >1.5x 1.281% >2x 0.358% | moved 52272 (34.02%) | pcores[0..11] 84371 >1.2x 5.73% >1.5x 0.731% >2x 0.292% p99 8.584 p99.9 17.607
WD f watching behind gameloop2 r2: threads 20 frames 151525 | median 6.597 p99 20.860 p99.9 29.106 max 43.30 ms | >1.2x 40.50% >1.5x 24.165% >2x 7.966% | fastest 5.719
WD f watching behind gameloop2 r2: same-core 103199 >1.2x 6.32% >1.5x 1.702% >2x 0.571% | moved 48326 (31.89%) | pcores[0..11] 85803 >1.2x 4.86% >1.5x 0.784% >2x 0.104% p99 8.805 p99.9 12.019
WD f watching behind gameloop2 r3: threads 20 frames 149571 | median 6.689 p99 20.603 p99.9 27.827 max 42.42 ms | >1.2x 43.28% >1.5x 29.074% >2x 8.365% | fastest 5.725
WD f watching behind gameloop2 r3: same-core 100368 >1.2x 5.62% >1.5x 1.571% >2x 0.540% | moved 49203 (32.90%) | pcores[0..11] 82989 >1.2x 4.14% >1.5x 0.718% >2x 0.187% p99 9.017 p99.9 15.317
```

The "r1" lines are the run with Rift in front by mistake.
