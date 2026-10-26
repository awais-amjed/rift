# Watching a stream: the Windows split, on the Intel laptop, Oct 26 2026

Steps 1 and 2 of `scripts/perf/WATCH_DRAW.md`. Step 1 ran on `watch-draw` at
`49c2e435` (no code change), against round 1's *What a call costs* and round 2's
part E. Step 2 ran on the fix, `01449ef4`.
A Claude session drove Rift itself; the user set up the call.

**After the fix (step 2):** with the picture turned off while nobody can see
Rift, minimised fell from 122% to 13%, behind a maximised window from 105% to
13%, and behind `gameloop2` from 116–118% to 19–20%. The game's frames over
1.5× fell from 1.6–1.7% to 0.22–0.28%. In front is unchanged at 121%. The
picture was back within 0.2 s every time.

**In short (step 1):** watching costs Rift 117% of a core in front, and **just as much
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

## Step 2: the picture off while nobody can see Rift

**What changed** (commit `01449ef4`, on this branch): while Rift is
minimised, hidden to the tray, or covered by another app's window, the
watched stream's video publication is disabled, so the server stops sending
it and nothing is decoded or drawn. Its sound and the watching attribute are
left alone. When Rift can be seen again the publication is handed back to
adaptive stream (`clearEnabled`, a fourth patch to `third_party/livekit_client`;
`enable()` would hold it on for good). The pause is Dart, the same on every
platform (`_PicturePauseMixin`, `AppSeenListener`). Only the Windows runner's
part is Windows-only (`SeenWatch`, `rift/window_seen`). `CALLS.md`, *Watching
while Rift cannot be seen*, has the rules.

**Dart never heard the minimise.** The first build used the app lifecycle for
minimised. Minimising sent nothing at all, and Rift went on drawing 57.6 frames
a second while receiving 8 Mbit/s. With a log on every lifecycle change, Dart
got `inactive` and `resumed` as the focus came and went, and nothing when the
window was minimised or hidden. So the runner reports minimised and hidden too.

**After** (same method as step 1, the same call; the stream was light again
for b and heavier in between, 3–15 Mbit/s by the overlay):

| | State | Total | Raster | Driver | Decoder | GPU 3D | Received | Frames drawn |
|---|---|---|---|---|---|---|---|---|
| b | Watching, stream page in front | 121.1 | 90.6 | 14.8 | 5.8 | 62.5% | 432 kbit/s | 50.6–53.3/s |
| d | Watching, minimised | 12.8 | 5.8 | 1.3 | – | 5.8% | 28 kbit/s | 5.0–5.2/s |
| e | Watching, behind a maximised window | 13.4 | 6.6 | 1.2 | – | 6.1% | 18 kbit/s | 5.1–5.3/s |
| f | Watching, behind `gameloop2` (two runs) | 18.6, 20.3 | 5.2 | 2.4 | – | – | – | 5.0/s |
| | Hidden, as the tray hides it | | | | | | 20–23 kbit/s | 5.0–5.1/s |

Against step 1: b is unchanged (117 then, 121 now), d went from 122 to 13, e
from 105 to 13, f from 116–118 to 19–20. `VideoDecoderQueue` dropped out of the
top threads in d, e and f. What is left is the call itself, not watching (a:
7.6). It draws 5 frames a second rather than a's 3. In f, `AudioEncoderQueue`
at 5.7 is the top thread.

**`gameloop2` beside it** (all CPUs, 60 s, as in step 1):

| | Slow (same core) | Over 1.5× | Over 2× | p99.9, performance cores | Rift |
|---|---|---|---|---|---|
| f after, run 1 | 1.94% | 0.275% | 0.086% | 9.2 ms | 18.6% |
| f after, run 2 | 1.69% | 0.223% | 0.057% | 8.7 ms | 20.3% |
| f before (step 1) | 5.62–6.32% | 1.57–1.70% | 0.54–0.57% | 12.0–15.3 ms | 116–118% |
| Round 3, Rift closed | | 0.069–0.090% | | 7.5–7.8 ms | – |

Over 1.5× fell to about a seventh of before, and is now about 3 times the
closed figure, not 20 times.

**The picture coming back**, timed from Rift's "can be seen" log line to the
first of 10 Present events each under 40 ms apart (`back.ps1`; one redraw of
the window comes alone, the stream does not):

| After | Back in |
|---|---|
| Restore after 13–15 s minimised (four times) | 186, 130, 140, 118 ms |
| Uncover after 14–15 s behind a maximised window (three times) | 136, 150, 97 ms |
| Shown after 30–35 s hidden (twice) | 128, 97 ms |
| Restore after 6 minutes minimised | 197 ms (a looser count: 20 frames in 500 ms) |

Within 0.2 s every time, and drawing at 37–53 frames a second 3–6 s later,
which is the stream's own rate at that moment.

**The other checks the brief asks for:**
- Alt+Tab between the maximised terminal and Rift, seven times in a row and
  then six more: each switch turned the picture off or on, and Rift in front
  drew 52.7 frames a second at the end.
- A smaller window (1000×600) in front of Rift, with the focus: the picture
  stayed on, at 30–45 frames a second.
- Two bugs were found and fixed before the commit:
  - Rift shown again without the foreground (as the tray can do) sat on top
    of the terminal while the terminal was still the foreground window. It was
    counted covered, and its picture stayed off. The runner now also checks
    that the window in front is above Rift.
  - Rift takes the foreground before it is visible, so the check run at that
    moment found it hidden, and nothing looked again. The runner now keeps
    polling once a second while Rift cannot be seen, and looks again after
    every `WM_WINDOWPOSCHANGED`.
- Once, the terminal taking the focus left the picture on for 2.5 s, until the
  next Alt+Tab. The order of windows wasn't read at that moment. In five more
  tries the terminal was above Rift and the picture went off each time.
- Two hides on builds before the last runner change counted 35 and 48 frames a
  second while hidden. The three hides on the final runner counted 5.0–5.1,
  with 20–23 kbit/s received. Not explained.

**Not checked:**
- A second monitor: this laptop has one.
- A real fullscreen game. CS2 wasn't started because the account was playing
  on the other PC. The stand-ins were a maximised window and the maximised
  terminal running `gameloop2`.
- The share stopping or the sharer leaving while Rift was hidden. That needs
  the other PC.
- What the sharer's dynacast did. With this client the only viewer, the server
  had nobody to send the picture to; the sharer's log wasn't read. It came back
  within 0.2 s, including after 6 minutes.
- Rift's own tray menu. The window was hidden and shown directly, as
  `window_manager` does.
- `flutter test`: four tests in `overlay_material_test.dart` fail, the same
  four on a clean checkout of `fe3ecdfe`. They fail on `DuckingCubit` and the
  Rust bridge, not on this change.

**For the Linux session:**
- On Linux the pause hangs on the app lifecycle alone. Minimise Rift while
  watching and see whether `[LiveKit] Rift cannot be seen` appears in the log
  and decoding stops (Linux minimised decoded at 26.7%, decoder 14%). If GTK
  says nothing, as Windows didn't, the runner needs a signal of its own
  (`window-state-event` with `GDK_WINDOW_STATE_ICONIFIED`).
- Covered isn't detected on Linux at all. Wayland doesn't tell an app.
- The Settings-page case (c) is shared and not done here. The stream there is
  still received and redrawn for, at 30% on this laptop.

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

Step 2, in the order they were taken. The first "d check" line is the
lifecycle-only build. The lines after it are the builds as they were fixed, and
"final build" is the committed code. "Not back" is a restore that didn't
happen: the test script's own focus call failed while Rift was minimised.
38,362 and 64,356 ms are the bug where Rift, shown again, was never seen
(fixed). The "11 ms" uncover is the first, looser count, which took Rift's
own redraw for the stream; by eye the stream was back at 137 ms.

```
WD2 d check minimised: frames drawn 57.6/s
WD2 d check minimised: frames drawn 5.2/s
WD2 back after restore (minimised ~4 min): picture back not back after "can be seen" | frames/s 2 s before 0.0, 3-6 s after 0.0
WD2 back after restore (minimised ~6 min): picture back 197 ms after "can be seen" | frames/s 2 s before 5.0, 3-6 s after 50.7
WD2 b watching, stream page: CPU 121.1% of a core | GPU 3d 62.5% | rx 432 kbit/s tx 764 kbit/s | working set 833 -> 833 MB, private 811 -> 811 MB, threads 98 | frames drawn 52.3/s
WD2 b watching, stream page: frames drawn 50.6/s
WD2 d watching, minimised: CPU 12.8% of a core | GPU 3d 5.8% | rx 28 kbit/s tx 128 kbit/s | working set 894 -> 894 MB, private 872 -> 872 MB, threads 98 | frames drawn 5.2/s
WD2 d watching, minimised: frames drawn 5.2/s
WD2 e watching, behind a maximised window: CPU 13.4% of a core | GPU 3d 6.1% | rx 18 kbit/s tx 30 kbit/s | working set 901 -> 901 MB, private 879 -> 879 MB, threads 97 | frames drawn 5.3/s
WD2 e watching, behind a maximised window: frames drawn 5.2/s
WD2 back after the covering window closed: picture back 11 ms after "can be seen" | frames/s 2 s before 5.0, 3-6 s after 49.7
WD2 after 7 alt-tabs, Rift in front: frames drawn 52.7/s
WD2 partly covered by a 1000x600 window: frames drawn 52.3/s
WD2 partly covered by a 1000x600 window: frames drawn 37.7/s
WD2 partly covered by a 1000x600 window in front: frames drawn 35.5/s
WD2 partly covered by a 1000x600 window in front: frames drawn 30.1/s
WD2 back after restore r1 (15 s minimised): picture back 186 ms after "can be seen" | frames/s 2 s before 4.0, 3-6 s after 37.3
WD2 back after restore r2 (15 s minimised): picture back 130 ms after "can be seen" | frames/s 2 s before 3.5, 3-6 s after 37.7
WD2 back after uncover r1 (15 s covered): picture back 136 ms after "can be seen" | frames/s 2 s before 3.5, 3-6 s after 36.7
WD2 back after uncover r2 (15 s covered): picture back 150 ms after "can be seen" | frames/s 2 s before 3.5, 3-6 s after 37.0
WD2 hidden (as to the tray): frames drawn 35.4/s
WD2 back after shown from hidden: picture back 38,362 ms after "can be seen" | frames/s 2 s before 0.0, 3-6 s after 0.0
WD2 shown again after hidden (check): frames drawn 3.9/s
WD2 final build, watching in front: frames drawn 53.0/s
WD2 final, hidden (as to the tray): frames drawn 47.8/s
WD2 final, back after shown from hidden: picture back 64,356 ms after "can be seen" | frames/s 2 s before 0.0, 3-6 s after 0.0
WD2 final, shown after hidden (check): frames drawn 5.0/s
WD2 hidden, 2-12 s: frames drawn 5.1/s
WD2 hidden, 20-30 s: frames drawn 5.0/s
WD2 back after shown from hidden: picture back 128 ms after "can be seen" | frames/s 2 s before 4.0, 3-6 s after 52.0
WD2 recheck minimised: frames drawn 5.0/s
WD2 recheck back after restore: picture back 140 ms after "can be seen" | frames/s 2 s before 5.0, 3-6 s after 52.7
WD2 recheck behind a maximised window: frames drawn 5.1/s
WD2 recheck back after uncover: picture back 97 ms after "can be seen" | frames/s 2 s before 4.5, 3-6 s after 51.0
WD2 recheck after 6 alt-tabs (terminal in front): frames drawn 5.0/s
WD2 recheck partly covered, small window in front: frames drawn 45.2/s
WD2 final build, watching in front: frames drawn 53.3/s
WD2 final build, minimised: frames drawn 5.0/s
WD2 final build, back after restore: picture back 118 ms after "can be seen" | frames/s 2 s before 4.5, 3-6 s after 50.3
WD2 final build, behind the maximised terminal: frames drawn 5.0/s
WD2 final build, hidden: frames drawn 5.0/s
WD2 final build, back after shown from hidden: picture back 97 ms after "can be seen" | frames/s 2 s before 5.0, 3-6 s after 45.3
```
