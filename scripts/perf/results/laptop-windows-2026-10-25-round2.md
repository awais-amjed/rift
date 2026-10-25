# Round 2: the fixes, on the Intel laptop's Windows, Oct 25 2026

The answers to `scripts/perf/ROUND2.md`, run on `perf-testing` at `b1228c4e`,
against round 1's numbers (`laptop-windows-2026-10-25.md`). As in round 1, a
Claude session drove Rift itself (screenshots, synthetic clicks and keys), and
the user ran the elevated helper for the measurements that need admin.

**In short:** the speaking ring, the unwatched stream and the wake-ups are
fixed, each by a wide margin. Dart on its own thread broke one thing: on
Windows the noise models and the mic volume are gone (*Worth fixing* 1), so
everything below ran on this branch plus a local, uncommitted patch for it.
DPDFNet-2 back on the capture thread costs the stand-in game more than the
noise between two Rift-closed runs (F), so by the round's rule the thread
move comes back. CS2 could not be run for F (below).

## The machine

The same laptop as round 1, unchanged: Intel Core i7-12700H (performance cores
are logical CPUs 0–11, efficiency cores 12–19), 32 GB, Intel Iris Xe driving
the screen, RTX 3070 Ti Laptop, Windows 11 Home 26200, on AC.

One difference: **the user watched this laptop's screen over RustDesk** for
much of the session. RustDesk used about 2% of a core, but it uploads the screen.
That is the 2.5–3.9 Mbit/s "upload while watching" first read in D and E
(below).

**New build:** this branch, `cargo build -p rust_lib_rift --release --target
x86_64-pc-windows-msvc`, then `flutter build windows --release`. The checks in
ROUND2 passed: `rust_lib_rift.dll` has no "DPDFNet's thread stopped", and
`flutter_webrtc_plugin.dll` has "WebRTC-MediaTaskQueuePriorities". **After A,
it was rebuilt with the local patch** from *Worth fixing* 1, and B–F ran on that.

**Old build:** the installed 1.5.2-beta.4, as in round 1.

**The call:** the user's account in CS Chat on their own server, unmuted, push
to talk off, filter Off unless a part says otherwise. Gracie (the user's other
PC) shared CS2 at 1080p60 with sound, and DJ Riff played music, where a part
asks for them.

## A. At rest: the wake-ups

`threadtop riftchat 30`, Rift in front (restored, not maximised) on Settings,
the mouse still.

| | New | beta.4 today | Round 1 (beta.4) |
|---|---|---|---|
| Not in a call: total | 93 sw/s, 0.1% | 331 sw/s, 0.5% | 10,159 sw/s, 3.2% |
| Not in a call: main thread | 85 sw/s | 199 sw/s | 5,105 sw/s |
| Not in a call, after leaving a call | — | 401 sw/s; main 248 | — |
| In a call, alone: total | **957 sw/s**, 4.4% | 4,333 sw/s, 4.0% | 11,835 sw/s, 7.2% |
| In a call: main thread | **203 sw/s** | 1,909 sw/s | 5,654 sw/s |
| In a call: the Flutter thread | 118 sw/s | 1,781 sw/s | 5,556 sw/s |

**Pass.** The new build's main thread wakes about 200 times a second in a call,
against beta.4's 1,900 today. Not in a call, beta.4 was quiet today too, so
round 1's thousands at rest need something to have started the timer first.
The commit's own account, that the timer keeps firing once it has fired, fits.

## B. Dart on its own thread: what could have broken

| | Result |
|---|---|
| Noise filter and mic volume | **Broken.** Only Off and Standard were offered, and Mic volume was gone, on two launches. *Worth fixing* 1. The checks below ran with the local patch |
| Push to talk, keyboard key (F9) | Pass: `Push-to-talk: pressed (hook)` / `released (hook)` with Rift in front and with the terminal in front |
| Push to talk, mouse side button (Mouse 4) | Pass, the same two ways |
| Mute and deafen keys (Ctrl+Shift+M / D), after clicking in the window | Pass: mute, deafen, undeafen and unmute each showed in the dock and on the tile |
| Share picker | Pass: Screen and Window tabs, thumbnails. A window share started (NVENC, 1080p60) and stopped cleanly. Your own share is not drawn on your own stage (not checked whether beta.4 does) |
| Mic test | Started and stopped. The level bar stayed dark in a quiet room, and hearing yourself back was not checked |
| File dialogs | Pass: Upload files opened Windows' dialog and the picture attached (removed unsent). Edit profile → camera badge → dialog → Crop picture → Apply → "New picture ready to save" (cancelled, not saved) |
| Paste a picture | Pass (the user, by hand) |
| The window | Pass: drag by the title bar, resize from the right edge, maximise, restore, minimise, back from the taskbar |
| A notification | Pass (the user): a mention from the other PC showed a Windows notification, and clicking it opened `#general` |

Seen in passing: one `PlatformException(Internal Consistency Error, Set editing
state has been invoked, but no client is set.)` in the log after the composer
lost focus. Not compared with beta.4.

## C. Someone talking: the speaking ring

New build, in the call, DJ Riff playing (Gracie in the call, no share). Frames
drawn over 10 s, and `threadtop` over 30 s:

| | New | Round 1 (beta.4) |
|---|---|---|
| Call page in front | **4.5 frames/s, 7.5%** of a core | 66/s, 92–104% |
| Minimised | **7.5/s, 6.6%** | 68–74/s, 108–111% |
| Behind the maximised terminal | **2.4/s, 7.4%** | 147/s, 134% |

`gameloop2` on all CPUs, game in front, music playing, no stream:

| | Slow (same core) | Over 1.5× | Over 2× | p99.9, performance cores | Rift |
|---|---|---|---|---|---|
| New, run 1 | 1.99% | 0.306% | 0.092% | 8.5 ms | 9% |
| New, run 2 | 2.39% | 0.312% | 0.116% | 8.5 ms | 15% |
| Round 1 (beta.4) | 5.35% | 1.31% | — | 23.1 ms | 110% |
| Rift closed (today, F) | 1.29–2.90% | 0.095–0.099% | 0.018–0.019% | 7.9–8.0 ms | — |

**Pass.** A few frames a second, and about a quiet call's cost. With the ring
held still, the game is close to Rift closed: 0.3% of frames over 1.5×, against
about 0.1% closed and 1.3% on beta.4. The ring itself showed lit (held) on DJ
Riff's tile while the music played. Its fade in and out was not watched.

## D. Joining while someone shares

Gracie sharing first. New build: join, don't press Watch, 30 s of bytes
received and `threadtop`, leave. Five times:

| Join | Received | `VideoDecoderQueue` | Log |
|---|---|---|---|
| 1 | 38 kbit/s | not running | `Unsubscribed from screenshare video`, `Holding screenshare audio` |
| 2 | 54 kbit/s | not running | the same |
| 3 | 39 kbit/s | not running | the same |
| 4 | 33 kbit/s | not running | the same |
| 5 | 49 kbit/s | not running | the same |

Then, on a sixth join, **Watch showed the picture** (not the avatar), and
**Stop watching** took received data back to 68 kbit/s with the decoder gone.

**Pass**, on every join. Round 1 (beta.4): 15–33 Mbit/s and the decoder at
9–17%, and Watch showed only the avatar. (beta.4 showed the picture once
today, in E3, so its failure is intermittent.)

Rift's thread count rose 112, 114, 116, 118, 121 at the five joins, two or
three a join. Leaving the call did not give them back. Small, but worth a look:
*Worth fixing* 4.

## E. Watching a stream beside a game: the decoder's priority

**1. Priorities**, new build, watching:

| Thread | New | beta.4 |
|---|---|---|
| `VideoDecoderQueue` | **1** | 15 |
| `IncomingVideoStreamQueue` | **1** | 15 |
| `AudioEncoderQueue` | **2** | 0 |

Pass.

**2. The game beside it**, `gameloop2` on all CPUs, game in front, Rift behind
watching (maximised):

| | Slow (same core) | Over 1.5× | Over 2× | p99.9, performance cores | Rift |
|---|---|---|---|---|---|
| New, music, run 1 | 9.73% | 2.83% | 0.79% | 17.3 ms | 135% |
| New, music, run 2 | 9.12% | 2.59% | 0.85% | 17.2 ms | 145% |
| New, no music, run 1 | 11.65% | 3.05% | 0.91% | 15.5 ms | 132% |
| New, no music, run 2 | 14.14% | 3.41% | 1.15% | 17.8 ms | 141% |
| Round 1 (beta.4, music) | 11.91% | 2.79% | 1.23% | 18.0 ms | 144% |

**Not yet close to a quiet call.** The lower priority shows as fewer frames over
2×, but watching still costs the game about as much as on beta.4. The cost is
the drawing, not the decoding: Flutter's raster thread at 70–74% of a core, the
Intel driver at 20–22% and the decoder at 21–30%. This is the "watching draws
94–156 frames a second" item ROUND2 lists as unchanged.

**3. Does the stream suffer?** Rift in front, watching, stats overlay on, and
`gameloop2` on all CPUs behind it for 60 s. The overlay's FPS read every 9 s:

| | Before | During the load | Ping during |
|---|---|---|---|
| New | 61, 44 | 55, 55, 61, 48, 49, 51 | 20–32 ms (1 ms before) |
| beta.4 | 52, 59 | 60, 51, 56, 60, 56, 54 | 10–42 ms (1–3 ms before) |

The user watched both and **saw no stutter in either**. The new build's
overlay showed "Loss: 121 pkts" throughout. That is a running total and it did
not move during the run. The overlay has no "Dropped" line. The game behind it
(one run each): new 17.20% slow, 3.77% over 1.5×, p99.9 16.7 ms; beta.4 8.22%,
2.31%, 11.9 ms. That is one run each, with Rift in front, so it is weak
evidence. It is worth a second look if the new build's raster thread competes
more than beta.4's did.

**Pass** on the stream: the lower priority did not visibly hurt it.

**Received data while watching:** new 17.7 Mbit/s, beta.4 33.9 Mbit/s, for
the same stream (both overlays read about 15 Mbit/s). beta.4 receives about
twice the stream. This answers round 1's open question, overlay 10–15 against
adapter 22–32. Something in `dev` stopped it; not traced further.

**The upload while watching** (2.5–3.9 Mbit/s on both builds) is not Rift. A
kernel network trace (`Microsoft-Windows-Kernel-Network`, 30 s from pressing
Watch) gave RustDesk 2,546 kbit/s and Rift 9 kbit/s. RustDesk sends this
laptop's screen to the user's other PC, and a moving stream on the screen makes
that grow.

## F. DPDFNet on the capture thread: does the thread come back?

**CS2 was not run.** The user was playing CS2 on the other PC on the same
Steam account, so starting it here would have taken the session from them.
F ran on ROUND2's fallback, `gameloop2` on all CPUs. That is the case where a
model on the capture thread competes for every core, and it is
CPU-bound by construction. The CS2 run is still owed.

The call carried DJ Riff's music and Gracie's unwatched share in every in-call
run. The user was playing behind both, so they stayed on. Both are the same
in the Off and DPDFNet-2 runs, so the comparison holds, and condition 4
("DPDFNet-2 with the music") is condition 3 here. Order: closed, Off, DPDFNet-2,
DPDFNet-2, Off, closed. The log showed `DPDFNet loaded` before the DPDFNet runs.

| | Slow (same core) | Over 1.5× | Over 2× | p99.9, performance cores | Rift | Capture thread |
|---|---|---|---|---|---|---|
| Rift closed, run 1 | 1.29% | 0.099% | 0.018% | 7.90 ms | — | — |
| Off, run 1 | 1.92% | 0.314% | 0.090% | 8.23 ms | 9.3% | 2.7%, priority 18 |
| DPDFNet-2, run 1 | 3.00% | **0.830%** | 0.124% | **12.24 ms** | 39.2% | **32.4%**, priority 18 |
| DPDFNet-2, run 2 | 3.18% | **0.915%** | 0.132% | **12.27 ms** | 37.7% | **31.9%**, priority 18 |
| Off, run 2 | 2.13% | 0.164% | 0.039% | 8.30 ms | 7.8% | 1.8%, priority 18 |
| Rift closed, run 2 | 2.90% | 0.095% | 0.019% | 7.97 ms | — | — |

The second closed run's slow share is high because one CPU (6) ran a frame
unusually fast (5.33 ms), which raises its bar. Its share over 1.5× and its
p99.9 match the first closed run.

**The answer: DPDFNet-2 costs the game more than the gap between the two
Rift-closed runs.** Against the filter Off, frames over 1.5× go from 0.16–0.31%
to 0.83–0.92% (3–5 times as many), and p99.9 on the performance cores goes from
8.2–8.3 ms to 12.2–12.3 ms, about 4 ms worse. The two closed runs differ by
0.004 points and 0.07 ms on the same two measures. The model takes about 30% of
a core on a time-critical thread (priority 18), which preempts the game's
threads. This matches round 1's beta.4 DPDFNet-2 runs: 3.23% and 3.17% slow,
0.79% and 1.57% over 1.5×, 10.2 and 12.8 ms.

So by the round's rule, **the thread move comes back**. Round 1's own result
remains the other side of it. On its own thread, below the capture thread, the
model barely ran while the game held every CPU: 5,768 of 5,770 frames went out
unfiltered, about 96% of the run. A middle way might be the model at normal
priority (not below normal), so that it shares the cores with the game instead
of preempting it or starving behind it. That is not measured.

## Worth fixing

1. **Windows: no noise models and no mic volume since Dart moved to its own
   thread** (`de081299`). `AppCubit`'s constructor calls `NoiseFilter.use()`,
   which evaluates `static final _native = _NativeFilter.load()` and asks the
   runner for `rift_noise_filter_available()`. The runner only makes that true
   in `rift::InstallNoiseFilter()`, called on the window thread in
   `FlutterWindow::OnCreate` after `RegisterPlugins`. With Dart on the window's
   thread, Dart could not run before `OnCreate` returned. On its own thread it
   asks first, gets 0, and `_native` stays null for the whole run. Seen on two
   launches. The effects:
   - only Off and Standard are offered;
   - a saved RNNoise or DPDFNet choice silently runs libwebrtc's Standard;
   - Mic volume is gone;
   - push to talk loses `canSilence`;
   - the mic test cannot borrow RNNoise.

   The local patch used for this round, not committed, only to unblock the
   test: `_NativeFilter.load()` polls `available()` every 5 ms for up to 2 s
   before giving up. A real fix would not block Dart's thread. It could have the
   runner tell Dart once the filter is installed, through the channel push to
   talk already uses, and `NoiseFilter` load (and apply the wanted mode) then.
   Or `_native` could be retried on use rather than cached as null. Also,
   `g_processing` is written on one thread and read on another without a
   barrier.
2. **DPDFNet-2 on the capture thread costs a CPU-bound game** about 0.6 points
   of frames over 1.5× and 4 ms of p99.9 (F). By the round's rule the own-thread
   version comes back, with its unfiltered-voice trade-off. Confirm on
   CPU-bound CS2 first.
3. **Watching a stream still costs a game about as much as on beta.4** (E2):
   Flutter drawing every frame of the video, minimised or covered too, at
   1.3–1.45 cores.
4. **Rift kept two or three threads after each join and leave** (D: 112 → 121
   over five). Not a leak of note yet, but it adds up in a long session.

## Left as found

Push to talk was turned on, used and turned off again, and its key cleared. The
mute and deafen shortcuts (Ctrl+Shift+M and D) that B set were cleared
afterwards. The filter was left
Off. CS2's `cs2_video.txt` was briefly set to the lowest settings for F, then
restored byte for byte before CS2 was ever started (it never was). Nothing was
sent in a chat and the profile was not saved.

## Appendix: raw lines

`gameloop2` (the second line of each pair is the per-CPU measure used above):

```
R2 new off music all-cpus r1: threads 20 frames 170095 | median 6.267 p99 13.669 p99.9 21.405 max 36.20 ms | >1.2x 34.33% >1.5x 9.092% >2x 1.978% | fastest 5.716
R2 new off music all-cpus r1: same-core 126011 >1.2x 1.99% >1.5x 0.306% >2x 0.092% | moved 44084 (25.92%) | pcores[0..11] 94523 >1.2x 1.50% >1.5x 0.086% >2x 0.029% p99 7.135 p99.9 8.465
R2 new off music all-cpus r2: threads 20 frames 167066 | median 6.341 p99 14.126 p99.9 22.120 max 37.28 ms | >1.2x 35.03% >1.5x 10.779% >2x 2.131% | fastest 5.715
R2 new off music all-cpus r2: same-core 123780 >1.2x 2.39% >1.5x 0.312% >2x 0.116% | moved 43286 (25.91%) | pcores[0..11] 93131 >1.2x 1.90% >1.5x 0.082% >2x 0.025% p99 7.297 p99.9 8.459
R2 new off watching no-music all-cpus r1: threads 20 frames 148330 | median 6.844 p99 20.625 p99.9 28.784 max 40.97 ms | >1.2x 49.57% >1.5x 26.684% >2x 8.931% | fastest 5.716
R2 new off watching no-music all-cpus r1: same-core 91280 >1.2x 11.65% >1.5x 3.052% >2x 0.913% | moved 57050 (38.46%) | pcores[0..11] 72231 >1.2x 11.22% >1.5x 2.342% >2x 0.494% p99 10.181 p99.9 15.520
R2 new off watching no-music all-cpus r2: threads 20 frames 142616 | median 7.117 p99 21.326 p99.9 30.123 max 47.37 ms | >1.2x 58.40% >1.5x 34.439% >2x 10.270% | fastest 5.725
R2 new off watching no-music all-cpus r2: same-core 85596 >1.2x 14.14% >1.5x 3.408% >2x 1.151% | moved 57020 (39.98%) | pcores[0..11] 67707 >1.2x 14.97% >1.5x 2.703% >2x 0.730% p99 11.179 p99.9 17.770
R2 E3 new Rift in front watching all-cpus: threads 20 frames 143186 | median 7.056 p99 21.070 p99.9 28.189 max 47.41 ms | >1.2x 56.85% >1.5x 32.890% >2x 10.869% | fastest 5.715
R2 E3 new Rift in front watching all-cpus: same-core 86219 >1.2x 17.20% >1.5x 3.771% >2x 1.307% | moved 56967 (39.79%) | pcores[0..11] 68862 >1.2x 15.90% >1.5x 2.912% >2x 0.831% p99 11.116 p99.9 16.660
R2 E3 old Rift in front watching all-cpus: threads 20 frames 149285 | median 6.612 p99 22.107 p99.9 29.170 max 49.32 ms | >1.2x 43.63% >1.5x 23.363% >2x 9.136% | fastest 5.720
R2 E3 old Rift in front watching all-cpus: same-core 96617 >1.2x 8.22% >1.5x 2.307% >2x 0.749% | moved 52668 (35.28%) | pcores[0..11] 79091 >1.2x 7.31% >1.5x 1.254% >2x 0.100% p99 9.178 p99.9 11.865
R2 new off watching music all-cpus r1: threads 20 frames 148268 | median 6.861 p99 20.159 p99.9 29.276 max 47.50 ms | >1.2x 49.94% >1.5x 26.628% >2x 8.940% | fastest 5.720
R2 new off watching music all-cpus r1: same-core 90557 >1.2x 9.73% >1.5x 2.827% >2x 0.794% | moved 57711 (38.92%) | pcores[0..11] 71061 >1.2x 9.57% >1.5x 2.111% >2x 0.431% p99 9.959 p99.9 17.265
R2 new off watching music all-cpus r2: threads 20 frames 145638 | median 6.955 p99 20.501 p99.9 28.561 max 44.26 ms | >1.2x 51.84% >1.5x 32.848% >2x 9.408% | fastest 5.721
R2 new off watching music all-cpus r2: same-core 88166 >1.2x 9.12% >1.5x 2.593% >2x 0.848% | moved 57472 (39.46%) | pcores[0..11] 69489 >1.2x 8.51% >1.5x 1.717% >2x 0.406% p99 10.100 p99.9 17.151
R2 F closed all-cpus r1: threads 20 frames 177553 | median 6.164 p99 9.694 p99.9 13.531 max 80.49 ms | >1.2x 34.11% >1.5x 4.198% >2x 0.232% | fastest 5.642
R2 F closed all-cpus r1: same-core 146695 >1.2x 1.29% >1.5x 0.099% >2x 0.018% | moved 30858 (17.38%) | pcores[0..11] 107029 >1.2x 0.76% >1.5x 0.065% >2x 0.021% p99 6.698 p99.9 7.899
R2 F new off music+share all-cpus r1: threads 20 frames 169831 | median 6.294 p99 13.683 p99.9 21.710 max 36.61 ms | >1.2x 33.64% >1.5x 9.891% >2x 2.017% | fastest 5.714
R2 F new off music+share all-cpus r1: same-core 129509 >1.2x 1.92% >1.5x 0.314% >2x 0.090% | moved 40322 (23.74%) | pcores[0..11] 98650 >1.2x 1.34% >1.5x 0.068% >2x 0.019% p99 6.992 p99.9 8.228
R2 F new dpdf2 music+share all-cpus r1: threads 20 frames 166000 | median 6.389 p99 11.886 p99.9 20.665 max 41.62 ms | >1.2x 39.62% >1.5x 13.498% >2x 1.254% | fastest 5.715
R2 F new dpdf2 music+share all-cpus r1: same-core 120103 >1.2x 3.00% >1.5x 0.830% >2x 0.124% | moved 45897 (27.65%) | pcores[0..11] 87100 >1.2x 2.80% >1.5x 0.927% >2x 0.119% p99 8.382 p99.9 12.235
R2 F new dpdf2 music+share all-cpus r2: threads 20 frames 164470 | median 6.441 p99 12.022 p99.9 20.179 max 38.75 ms | >1.2x 40.18% >1.5x 15.101% >2x 1.310% | fastest 5.714
R2 F new dpdf2 music+share all-cpus r2: same-core 118685 >1.2x 3.18% >1.5x 0.915% >2x 0.132% | moved 45785 (27.84%) | pcores[0..11] 85747 >1.2x 3.24% >1.5x 1.068% >2x 0.132% p99 8.964 p99.9 12.267
R2 F new off music+share all-cpus r2: threads 20 frames 168635 | median 6.389 p99 10.992 p99.9 18.376 max 34.91 ms | >1.2x 35.34% >1.5x 10.739% >2x 0.738% | fastest 5.716
R2 F new off music+share all-cpus r2: same-core 129956 >1.2x 2.13% >1.5x 0.164% >2x 0.039% | moved 38679 (22.94%) | pcores[0..11] 96816 >1.2x 1.91% >1.5x 0.083% >2x 0.021% p99 7.172 p99.9 8.300
R2 F closed all-cpus r2: threads 20 frames 174087 | median 6.242 p99 9.932 p99.9 14.348 max 104.20 ms | >1.2x 38.08% >1.5x 29.584% >2x 0.488% | fastest 5.330
R2 F closed all-cpus r2: same-core 144290 >1.2x 2.90% >1.5x 0.095% >2x 0.019% | moved 29797 (17.12%) | pcores[0..11] 105313 >1.2x 1.98% >1.5x 0.059% >2x 0.015% p99 6.811 p99.9 7.970
```

Rift's state measurements (threads, GPU engine, adapters, memory, frames drawn
over 10 s):

```
R2 C1 music, call page in front (new): CPU 7.5% of a core | GPU 3d 1.1% | rx 413 kbit/s tx 154 kbit/s | working set 833 -> 824 MB | frames drawn 4.5/s
R2 C2 music, minimised (new): CPU 6.6% of a core | GPU 3d 1.2% | rx 407 kbit/s tx 153 kbit/s | working set 851 -> 844 MB | frames drawn 7.5/s
R2 C3 music, behind the maximised terminal (new): CPU 7.4% of a core | GPU 3d 1.1% | rx 412 kbit/s tx 169 kbit/s | working set 825 -> 831 MB | frames drawn 2.4/s
R2 E1 watching, maximised in front (new): CPU 118.9% of a core | GPU 3d 63.3% | rx 17,753 kbit/s tx 3,814 kbit/s | working set 1,216 -> 1,221 MB | frames drawn 51.9/s
R2 D stopped watching, maximised in front (new): CPU 8.3% of a core | GPU 3d 4.6% | rx 68 kbit/s tx 47 kbit/s | working set 1,238 -> 1,199 MB
R2 E1 watching, maximised in front (beta.4): CPU 96.2% of a core | GPU 3d 62.9% | rx 33,902 kbit/s tx 3,898 kbit/s | working set 900 -> 882 MB | frames drawn 51.3/s
```

(tx in both E1 lines is mostly RustDesk; see E.)
