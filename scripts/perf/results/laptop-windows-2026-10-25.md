# Rift's cost beside a game: the Intel laptop, on Windows, Oct 25 2026

The answers to `scripts/perf/README.md`, run on the `perf-testing` branch
(`2df5c11c`). A Claude session drove Rift and CS2 itself (screenshots and
synthetic clicks and keys), with the user's go-ahead; the user ran one elevated
PowerShell for the two measurements that need admin.

## The machine

| | |
|---|---|
| CPU | Intel Core i7-12700H: 6 performance cores (logical CPUs 0–11) and 8 efficiency cores (12–19), 14 cores, 20 threads |
| RAM | 32 GB |
| GPUs | Intel Iris Xe (driver 31.0.101.4502), drives the 1920x1080 165 Hz screen; NVIDIA GeForce RTX 3070 Ti Laptop (32.0.16.1074), CS2 ran on it |
| OS | Windows 11 Home 25H2, build 26200.9711 |
| Power | On AC, power plan "Atlas Power Scheme" throughout |
| Running beside | Steam, RustDesk (draws 1 frame a second), Windows Terminal. No browser, Discord or Docker running |

**The old build** was the released **1.5.2-beta.4** installer from GitHub,
installed over 1.5.0 (Settings → About read "Rift 1.5.2-beta.4"). It has the
model on libwebrtc's capture thread, and that thread kept on the performance
cores. "Open Rift when your computer starts" was turned off for the session.

**The new build** was this branch, `flutter build windows --release`, after
`cargo build -p rust_lib_rift --release --target x86_64-pc-windows-msvc` (see
*Worth fixing* 1 for why that step was needed).

**The call:** the user's account alone in a voice channel on their own server
(production), unmuted, with the microphone open throughout (Windows' mic-in-use
icon on, and the model ran continuously). Nobody else was in the call.

## How it was measured, and two traps

- **Each in-call run was its own call** for the new build's DPDFNet runs. Rift
  logs the late-frame count when a call ends, so each count covers one run.
- **The stand-in game's own measure does not work on this CPU.** `gameloop`
  calls a frame slow when it takes 1.2× the fastest frame. The efficiency cores
  run a frame in 7.1–7.5 ms against the performance cores' 5.7, so with Rift
  closed 34–35% of frames are "slow", and two closed runs gave 4.1% and 12.5%
  over 1.5×. A variant (`gameloop2`, below) does the same work and also notes
  the CPU each frame started and ended on. It judges a frame against **the
  fastest frame on its own CPU**, for frames that stayed on one CPU (75–85% of
  them). "Slow frames" below is that measure. Every run also printed the kit's
  line, kept in the appendix.
- **A game behind another window is throttled.** The first in-call run had
  Rift maximised over the terminal running the game. Windows treated the game as
  a background process and confined it to the efficiency cores: median frame
  19.0 ms against 6.0, 79% of frames moved between CPUs (discarded; in the
  appendix). A real game is in front. So the game was put in front for every
  run, with Rift behind it, and `gameloop2` opts out of power throttling
  (`SetProcessInformation(ProcessPowerThrottling)`), as a foreground game is.
- The free-CPU runs (18 game threads) leave some efficiency cores idle, which
  makes the busy ones in their cluster faster at times. That breaks the
  per-CPU measure there, so for those runs compare the share over 1.5×, the
  p99.9 and the max.

## Test 1: Rift's own cost

`threadtop riftchat 30`, Rift maximised on Settings → Voice & audio, the mouse
still. % of one core; "sw/s" is context switches a second; priority as
threadtop reads it (a normal thread, such as a game's, is 8).

**Old build (1.5.2-beta.4)**

| State | Total | Top threads |
|---|---|---|
| Not in a call | 0.0% | nothing measurable |
| Call, filter Off | 5.9% | main 1.7% (6,482 sw/s), AudioEncoderQueue 1.5%, `webrtc_core_audio_capture_thread` 1.1% at priority 18, Flutter thread 1.0% (6,388 sw/s), render thread 0.3% at 18 |
| Call, RNNoise | 6.4% | main 1.8% (5,526 sw/s), **capture 1.8% at 18**, AudioEncoderQueue 1.4%, Flutter 0.9% |
| Call, DPDFNet-2 | 22.0% | **capture 18.7% at priority 18** (162 sw/s), AudioEncoderQueue 1.6%, main 1.1% |

**New build (`perf-testing`)**

| State | Total | Top threads |
|---|---|---|
| Not in a call | 0.3% | main 0.3% |
| Call, filter Off | 7.2% | main 2.4% (5,654 sw/s), capture 1.5% at 18, AudioEncoderQueue 1.3%, Flutter 0.9% (5,556 sw/s) |
| Call, RNNoise | 6.5% | main 2.0% (6,398 sw/s), capture 1.8% at 18, AudioEncoderQueue 1.0%, Flutter 0.9% |
| Call, DPDFNet-2 | 26.1% | **`rift-dpdfnet` 20.1% at priority −1** (176 sw/s), main 1.5%, AudioEncoderQueue 1.4%, **capture 1.2%** at 18 |
| Call, DPDFNet-8 | 23.0%, 24.2% | `rift-dpdfnet` 17.3%, 19.6%: it **fell back to DPDFNet-2 in both calls** ("too slow here for DPDFNet-8, ran DPDFNet-2"), with nothing else running |

The model moved as intended: the capture thread went from 18.7% to 1.2%, and
the model runs on `rift-dpdfnet` at −1.

The main and Flutter threads' 5,000–6,000 switches a second showed in the
readings with the filter Off and on RNNoise only. A later reading in front, in
a call, gave 873, and Rift draws about 1 frame a second (below). Not explained;
it is 1–2% of a core.

**Frames drawn** (DXGI Presents, 10 s each, in a call):

| | On Settings, in front | Minimised | Behind another window |
|---|---|---|---|
| Old build | 1.3/s | 1.2/s | 1.1/s |
| New build | 1.1/s | 1.2/s | 1.2/s |

`presents.ps1` itself reported nothing here (*Worth fixing* 3); these are
counted from the trace it leaves.

## Test 2: the stand-in game

`gameloop2 run 60 3892656` (calibrated: 5 ms on a performance core), game in
front, Rift's threads read for 30 s from 15 s in. Order: closed, old DPDFNet-2,
old Off, new Off, new DPDFNet-2 ×2, new Off, old Off, old DPDFNet-2, closed.

**All 20 logical CPUs:**

| Condition | Run | Slow frames | Over 1.5× | Performance cores: slow, p99.9 | Rift's model thread | Unfiltered |
|---|---|---|---|---|---|---|
| Rift closed | 1 | 1.35% | 0.095% | 0.87%, 8.04 ms | | |
| Rift closed | 2 | 1.41% | 0.069% | 1.21%, 7.56 ms | | |
| Old, Off | 1 | 1.94% | 0.144% | 1.44%, 8.51 ms | | |
| Old, Off | 2 | 2.47% | 0.130% | 2.73%, 8.64 ms | | |
| **Old, DPDFNet-2** | 1 | **3.23%** | **0.792%** | 2.32%, 10.20 ms | capture 29.9% at 18 | none (filters every frame) |
| **Old, DPDFNet-2** | 2 | **3.17%** | **1.574%** | 3.08%, 12.75 ms | capture 30.4% at 18 | none |
| New, Off | 1 | 1.24% | 0.091% | 0.93%, 7.97 ms | | |
| New, Off | 2 | 1.51% | 0.107% | 0.97%, 8.16 ms | | |
| **New, DPDFNet-2** | 1 | **1.91%** | **0.243%** | 1.32%, 9.35 ms | `rift-dpdfnet` 1.2% | **5,768** |
| **New, DPDFNet-2** | 2 | **1.30%** | **0.132%** | 1.15%, 8.97 ms | `rift-dpdfnet` 1.2% | **5,770** |
| New, DPDFNet-8 (fell back) | 1 | 1.71% | 0.179% | 1.29%, 9.10 ms | `rift-dpdfnet` 1.2% | 5,774 |

The new build's unfiltered counts are per call. In run 2 the call lasted about
84 s and the game 60 s (6,000 voice frames), so **about 96% of the voice went
out unfiltered while the game held every CPU**, and almost none before or after
it. `rift-dpdfnet` got 1.2% of a core with 5 switches a second: it barely ran.
The old build's capture thread took 30% of a core at priority 18 instead, and
AudioEncoderQueue (Opus) rose to 6–7% in its runs against 2–6% in the others.

**Two logical CPUs left free (18 game threads):**

| Condition | Run | Over 1.5× (all frames) | p99.9 | max | Model thread | Unfiltered |
|---|---|---|---|---|---|---|
| Rift closed | 1 | 0.245% | 8.92 ms | 106.3 ms | | |
| Old, DPDFNet-2 | 1 | 14.850% | 10.46 ms | 65.5 ms | capture 29.3% at 18 | none |
| Old, DPDFNet-2 | 2 | 1.225% | 10.44 ms | 40.5 ms | capture 30.3% at 18 | none |
| New, DPDFNet-2 | 1 | 2.351% | 9.88 ms | 35.4 ms | `rift-dpdfnet` 31.1% | **114** |
| New, DPDFNet-2 | 2 | 0.626% | 9.50 ms | 37.2 ms | `rift-dpdfnet` 31.1% | **83** |

With a CPU spare, the new build's model gets its 31% and sends 1–2% of the
game's voice frames unfiltered. The old build's p99.9 stays about 1 ms above.
The kit's over-1.5× measure swings between runs (14.9% and 1.2% for the same
condition) because of the efficiency cores, so it says little here.

## Test 3: CS2

PresentMon 2.6.0 (`--process_name cs2.exe --timed 90`), `MsBetweenPresents`.
de_dust2, offline, bots kicked, `mp_ignore_round_win_conditions 1`, the camera
put at the same spot and angle before each run (`setpos`/`setang`, bound to a
key for the session and unbound after). 1920x1080, the user's own graphics
settings, frame rate uncapped. CS2 ran at about 300 fps and was GPU-bound: in a
test capture its CPU was busy about 1.0 ms a frame and the GPU about 3.3 ms.
"1% low" is the frame rate over the slowest 1% of frames.

| Condition | Run | Avg fps | 1% low | p99 | p99.9 | max | Over 1.5× median | Rift's model thread | Unfiltered |
|---|---|---|---|---|---|---|---|---|---|
| Rift closed | 1 | 312.0 | 168.6 | 5.69 ms | 6.08 | 20.2 | 13.94% | | |
| Old, DPDFNet-2 | 1 | 315.9 | 186.3 | 5.18 ms | 5.60 | 6.3 | 11.15% | capture 30.5% at 18 | none |
| Old, Off | 1 | 317.2 | 190.4 | 5.06 ms | 5.47 | 6.4 | 9.41% | | |
| New, Off | 1 | 301.7 | 178.5 | 5.44 ms | 5.82 | 6.3 | 13.97% | | |
| New, DPDFNet-2 | 1 | 305.9 | 181.0 | 5.34 ms | 5.76 | 6.4 | 14.24% | `rift-dpdfnet` 27.1% | 8 |
| New, DPDFNet-2 | 2 | 307.4 | 181.8 | 5.30 ms | 5.73 | 7.2 | 10.42% | `rift-dpdfnet` 30.5% | 0 |
| New, Off | 2 | 303.2 | 176.5 | 5.51 ms | 5.85 | 6.1 | 15.82% | | |
| Old, Off | 2 | 297.6 | 176.7 | 5.48 ms | 5.87 | 7.2 | 14.62% | | |
| Old, DPDFNet-2 | 2 | 303.3 | 178.7 | 5.40 ms | 5.88 | 6.5 | 12.66% | capture 31.1% at 18 | none |
| Rift closed | 2 | 301.8 | 191.2 | 5.06 ms | 5.43 | 7.0 | 2.62% | | |

**No condition stands out.** The spread between the two Rift-closed runs
(312.0 and 301.8 fps; 168.6 and 191.2 at the 1% low) covers every other run,
and the frame rate drifted down about 10 fps over the session, the same for
every condition. CS2 here leaves CPU free, so the old build's time-critical
model finds a core without taking one from the game, and the new build's model
gets enough to filter every frame but 8.

## Test 4: DPDFNet-8 beside the game

It never ran: on this laptop the new build fell back to DPDFNet-2 in every call,
idle too. Beside the game, the same as DPDFNet-2 (5,774 frames unfiltered).

## Conclusion

- **The fix does what it says here.** Beside a game that takes every CPU, the
  old build on DPDFNet-2 about doubles the stand-in game's slow frames (3.2%
  against 1.4% closed) and makes long ones 10–20 times more common (over 1.5×:
  0.8–1.6% against 0.07–0.1%; p99.9 on the performance cores 10–13 ms against
  8). The new build on DPDFNet-2 is at the filter-Off level (1.3–1.9%, 0.13–0.24%,
  9.0–9.4 ms).
- **The cost is the filter.** With every CPU taken, about 96% of the voice
  went out unfiltered while the game ran. With two CPUs free it was 1–2%, and
  in CS2, which is GPU-bound here, 0–8 frames in 90 s.
- **On this laptop the old build's damage is modest, and CS2 shows none.** The
  six performance cores and the free time CS2 leaves absorb the time-critical
  model. The reports came from AMD PCs, which have no efficiency cores (so the
  pinning kept nothing off them), and nothing here says how CPU-bound their CS2
  was. A CPU-bound CS2 on that hardware is the test that would settle it.
- **Rift with the filter Off** costs 6–7% of a core in a call: Opus encoding
  1–3%, the main thread 2%, the capture thread 1–2%. Rift draws 1.1–1.3 frames
  a second in a call, in front, minimised or hidden; it is not drawing behind a
  game.

## Worth fixing

1. **The README's Windows build can carry a stale Rust library.**
   `rust/cargokit.yaml` sets `local_cache_dir: target`, and cargokit then
   copies whatever `rust/target/x86_64-pc-windows-msvc/release/rust_lib_rift.dll`
   exists, whatever its age, instead of building. Here that was an Oct 5 DLL, so
   `flutter build windows --release` produced an "app with the fix" running Oct
   5 Rust code. Building the crate first (`cargo build -p rust_lib_rift --release
   --target x86_64-pc-windows-msvc`) fixed it; whether the DLL has the fix
   shows in its strings ("DPDFNet's thread stopped"). The README should say so,
   or cargokit should check the crate's hash against the cached file.
2. **DPDFNet-8 never holds on this laptop.** Below normal priority, Windows
   runs `rift-dpdfnet` on the efficiency cores, where DPDFNet-8 is too slow,
   even with the computer idle. The DPDFNet-8 choice is offered but does
   nothing here. A possible change (not tried): keep the priority below normal,
   but mark the thread high QoS (`SetThreadInformation(ThreadPowerThrottling)`
   with EXECUTION_SPEED in the mask and not held), so it may use a performance
   core that is free without taking one from a game.
3. **`presents.ps1` finds no Presents on this Windows.** `tracerpt` names every
   event after the provider ("Microsoft-Windows-DXGI"), not "Present", and gives
   PIDs in hex, so the script's filter matches nothing. Counting event IDs 42
   and 55 (Present_Start, PresentMultiplaneOverlay_Start) by PID, parsed as hex,
   works.
4. **`gameloop` on a hybrid CPU, and the window in front.** The kit's 1.2×
   measure is a third efficiency cores on Intel's hybrid CPUs; a per-CPU
   measure (below) fixes it. And the README should say to keep the game's
   window in front, or have `gameloop` opt out of power throttling, or a run
   beside Rift's window measures Windows' throttling of the game.

`gameloop2`, the variant used above: the same `work()` and spin count, plus
`GetCurrentProcessorNumber()` before and after each frame. Frames that stay on
one CPU are judged against that CPU's fastest frame; it reports frames that
moved, the fast class (CPUs within 15% of the fastest) separately, and each
CPU's fastest frame. It opts out of power throttling at start. Its source was
kept outside the repository; it can go into the kit if wanted.

## Not done

- A CPU-bound CS2 (low settings, or a CPU-heavy map or benchmark): this one
  was GPU-bound.
- An AMD desktop, where the reports came from.
- Another person in the call.
- The mic test on DPDFNet, push to talk.

## Part 2: Rift with the filter Off, beside a call with a stream and music

Asked by the user after part 1: with the noise filter left Off, does Rift
cost anything else? The released **1.5.2-beta.4**, filter Off, on this laptop.
The user joined CS Chat from another PC as Gracie, sharing CS2 at 1080p60 with
its sound, with the DJ Riff music bot playing music in the call (each varied
on request below). Every state was measured the same way over 30 s
(`measure.ps1`, kept outside the repository):
- Rift's threads (`threadtop`);
- Rift's GPU use per engine (Windows' "GPU Engine" counters for its PID; all
  on the Iris Xe);
- bytes received on every adapter. Out of the call this read 9–41 kbit/s, so
  in a call it is Rift's;
- memory;
- frames drawn over 10 s (DXGI Presents).

### What a call costs, by what is happening in it

| State | Rift's CPU | Iris Xe 3D | Received | Frames drawn |
|---|---|---|---|---|
| Not in a call | 1.5–3.2% of a core | under 1% | — | 1.0/s |
| In the call, nobody speaking, no stream | 6.4–7.9% | 3% | 140 kbit/s | 3.0/s |
| Your share on, not watched (share started after joining) | 8.6–9.9% | 2–3% | 30–41 kbit/s | 2.1–2.5/s |
| **Music playing (someone "speaking"), call page in front** | **92–104%** | **62–69%** | 0.4 Mbit/s | **66/s** |
| **Music playing, minimised** | **108–111%** | **71–75%** | 0.4 Mbit/s | **68–74/s** |
| **Music playing, behind another window** | **134%** | **73%** | 0.4 Mbit/s | **147/s** |
| Watching the share, in front | 87% (no music), 146% (music) | 62–72% | 30–32 Mbit/s | 53/s, 89/s |
| **Watching, minimised** (music) | **140%** | **73%** | 22 Mbit/s | **94/s** |
| **Watching, behind another window** | 83% (no music), 123% (music) | 34–62% | 31 Mbit/s | **156/s** (music) |
| Stopped watching (share started after joining) | 9.7–9.8% | 3% | 27–39 kbit/s | 3/s |
| **Joined while the share was already running, never watched** | **21–29%** | 3% | **15–33 Mbit/s** | 2/s (no music) |

Memory: 450–700 MB private out of a call, 780–990 MB in one, falling back
when the call ends; no steady growth over the hour of tests.

### What was found

1. **While anyone in the call is "speaking", Rift redraws flat out, even
   minimised or hidden.** With the music bot playing (a person talking does the
   same while they talk), Rift drew 66 frames a second in front, 68–74
   minimised, and 147 behind another window. That cost 1–1.3 cores, mostly the
   Flutter thread (60–75%) and the Intel driver (20–46%), plus 62–75% of the
   Iris Xe. With the music stopped it was 3 frames a second and 6–8% of a core.
   Faster behind a window than in front suggests nothing paces the frames once
   the window is covered. Present returns at once for a covered window, so an
   animation that never stops runs as fast as it can. Probably `SpeakingRing`'s
   pulse; the call page has nothing else that animates with sound.
   Twice, early on, minimised and covered readings with the music on drew 2
   frames a second. Not explained (perhaps between songs); every later reading,
   on a fresh start too, drew 68–147.
2. **Joining a call while someone is already sharing downloads and decodes
   their stream, unwatched, until you leave.** Rift logs "Unsubscribed from
   screenshare video", yet it received 15–33 Mbit/s, and `VideoDecoderQueue`
   ran at 9–17% of a core. Pressing Watch then showed only the sharer's avatar,
   never the picture (the user saw it fine on their own client), and Stop
   watching did not end it either. Leaving the call did. When the share
   started *after* joining, everything worked: nothing received until Watch,
   the picture shown, and Stop watching back to 30 kbit/s. Reproduced twice
   (09:08 and 09:55 in Rift's log). So the user's guess ("after the move from
   unsubscribe to disable, a stream keeps going after Stop watching") is not
   quite it: Stop watching works, but the join-while-sharing path never
   unsubscribes.
3. **Watching keeps drawing when minimised or hidden,** at 94 and 156 frames a
   second for a stream of about 50–60. Rift's stats overlay read 9.6–15 Mbit/s
   while the adapter counted 22–32 Mbit/s received; not explained (two layers
   at once?).
4. **Rift's video decoder runs at priority 15**, the time-critical level, as
   the old DPDFNet capture thread did. So decoding a stream takes cores from a
   game first (below).
5. **Not in a call, Rift's main thread and a Flutter thread wake 2,500–5,500
   times a second each** while drawing 1 frame a second: 1.5–3% of a core, in
   front or behind. Sampled: the main thread is in its message loop
   (`RiftChat.exe+0x7eb9` in `win32u`) and the Flutter thread in the engine.
   Not explained; seen in part 1 too, on and off.

### Beside the stand-in game

`gameloop2`, all 20 CPUs, game in front and Rift behind it, filter Off:

| Condition | Slow frames | Over 1.5× | Over 2× | Performance cores: slow, p99.9 | Rift during the run |
|---|---|---|---|---|---|
| Rift closed (part 1) | 1.35–1.41% | 0.07–0.10% | 0.02% | 0.9–1.2%, 7.6–8.0 ms | |
| In a call, alone, no stream (part 1) | 1.94–2.47% | 0.13–0.14% | 0.02–0.03% | 1.4–2.7%, 8.5–8.6 ms | 6–10% |
| **Unwatched stream decoding** (joined while sharing) | **3.96%** | **0.76%** | **0.33%** | 3.9%, **14.1 ms** | 48%, decoder 25% at priority 15 |
| **Music playing, no stream** | **5.35%** | **1.31%** | **0.48%** | 4.4%, **23.1 ms** | 110%, Flutter 64%, Intel driver 35% |
| **Watching the stream** | **11.91%** | **2.79%** | **1.23%** | 10.5%, **18.0 ms** | 144% |

During the music run even the efficiency cores' fastest frames slowed (7.8–8.3
ms against 7.5). The Iris Xe shares the chip's power budget, so Rift's drawing
also costs the CPU clock.

### Answer

With the filter Off, a quiet call costs a game nothing measurable. **But a call
where someone talks or plays music costs a game more than DPDFNet ever did**,
because Rift redraws at full speed behind the game. Joining while someone shares
adds a hidden 1080p60 download and decode until you leave. Worth fixing, in
order:

1. Stop drawing when the window is minimised or covered, and cap animation at
   the display rate, or make the speaking indicator not animate continuously
   (redraw on a change in who speaks, not every frame).
2. The join-while-sharing path: actually unsubscribe (or never subscribe)
   until Watch, and make Watch show the picture there.
3. Video decoding at time-critical priority: lower it, as the DPDFNet move did
   for the model.
4. The 2,500–5,500 wake-ups a second when idle.

Not measured: Rift on the RTX instead of the Iris Xe, a second monitor, several
people talking at once, and the new build (`perf-testing`) in part 2.

## Appendix: raw lines

`results.txt` (`gameloop2`'s two lines per run; the first of each pair is the
kit's own measure; lines marked DISCARDED say why):

```
DISCARDED (installed Rift was running) closed all-cpus r1: threads 20 frames 182056 | median 5.911 p99 9.386 p99.9 12.014 max 70.11 ms | >1.2x 33.83% >1.5x 4.138% >2x 0.177% | fastest 5.564
closed all-cpus r0 (kit gameloop): threads 20 frames 182245 | median 5.914 p99 9.397 p99.9 13.675 max 103.50 ms | >1.2x 35.07% >1.5x 12.489% >2x 0.285% | fastest 5.324
closed all-cpus r1: threads 20 frames 178923 | median 6.034 p99 9.656 p99.9 15.153 max 57.30 ms | >1.2x 34.22% >1.5x 5.675% >2x 0.293% | fastest 5.541
closed all-cpus r1: same-core 150789 >1.2x 1.35% >1.5x 0.095% >2x 0.021% | moved 28134 (15.72%) | pcores[0,1,2,3,4,5,6,7,8,9,10,11] 110746 >1.2x 0.87% >1.5x 0.059% >2x 0.016% p99 6.632 p99.9 8.042 | cpu fastest ms 5.72 5.72 5.72 5.72 5.74 5.68 5.54 5.72 5.72 5.72 5.72 5.72 7.06 7.06 7.06 7.48 7.06 7.48 7.48 7.48
DISCARDED (game behind maximised Rift, throttled) old dpdf2 all-cpus r1: threads 20 frames 68290 | median 19.023 p99 22.731 p99.9 26.563 max 48.94 ms | >1.2x 92.00% >1.5x 88.001% >2x 87.361% | fastest 5.716
DISCARDED (game behind maximised Rift, throttled) old dpdf2 all-cpus r1: same-core 14125 >1.2x 51.70% >1.5x 51.264% >2x 49.650% | moved 54165 (79.32%) | pcores[0,1,2,3,4,5,6,7,8,9,10,11] 4988 >1.2x 1.52% >1.5x 0.722% >2x 0.261% p99 8.413 p99.9 16.005 | cpu fastest ms 5.73 5.72 5.72 5.72 5.80 5.72 5.72 5.72 5.72 5.72 5.72 5.72 7.54 7.49 7.49 7.49 7.49 7.49 7.49 7.49
old dpdf2 all-cpus r1: threads 20 frames 170655 | median 6.271 p99 10.763 p99.9 16.818 max 91.58 ms | >1.2x 38.82% >1.5x 9.788% >2x 0.622% | fastest 5.714
old dpdf2 all-cpus r1: same-core 128920 >1.2x 3.23% >1.5x 0.792% >2x 0.045% | moved 41735 (24.46%) | pcores[0,1,2,3,4,5,6,7,8,9,10,11] 95245 >1.2x 2.32% >1.5x 0.927% >2x 0.052% p99 8.386 p99.9 10.201 | cpu fastest ms 5.72 5.72 5.72 5.72 5.78 5.72 5.72 5.72 5.72 5.72 5.71 5.72 7.67 7.07 7.06 7.49 7.06 7.49 7.48 7.49
old off all-cpus r1: threads 20 frames 171301 | median 6.317 p99 10.631 p99.9 15.418 max 38.70 ms | >1.2x 34.78% >1.5x 8.097% >2x 0.545% | fastest 5.716
old off all-cpus r1: same-core 136125 >1.2x 1.94% >1.5x 0.144% >2x 0.016% | moved 35176 (20.53%) | pcores[0,1,2,3,4,5,6,7,8,9,10,11] 102356 >1.2x 1.44% >1.5x 0.092% >2x 0.018% p99 7.096 p99.9 8.514 | cpu fastest ms 5.72 5.72 5.72 5.72 5.72 5.72 5.73 5.81 5.72 5.72 5.72 5.72 7.62 7.49 7.49 7.49 7.48 7.49 7.49 7.48
new off all-cpus r1: threads 20 frames 175856 | median 6.172 p99 10.228 p99.9 15.348 max 70.39 ms | >1.2x 34.21% >1.5x 5.694% >2x 0.380% | fastest 5.715
new off all-cpus r1: same-core 136687 >1.2x 1.24% >1.5x 0.091% >2x 0.018% | moved 39169 (22.27%) | pcores[0,1,2,3,4,5,6,7,8,9,10,11] 101974 >1.2x 0.93% >1.5x 0.051% >2x 0.013% p99 6.820 p99.9 7.972 | cpu fastest ms 5.72 5.72 5.72 5.72 5.78 5.72 5.72 5.72 5.72 5.72 5.72 5.72 7.52 7.49 7.49 7.48 7.49 7.49 7.49 7.49
new dpdf2 all-cpus r1: threads 20 frames 172348 | median 6.245 p99 11.155 p99.9 18.951 max 37.31 ms | >1.2x 34.26% >1.5x 8.734% >2x 0.837% | fastest 5.716
new dpdf2 all-cpus r1: same-core 134869 >1.2x 1.91% >1.5x 0.243% >2x 0.039% | moved 37479 (21.75%) | pcores[0,1,2,3,4,5,6,7,8,9,10,11] 102925 >1.2x 1.32% >1.5x 0.186% >2x 0.038% p99 7.011 p99.9 9.348 | cpu fastest ms 5.72 5.72 5.72 5.72 5.75 5.72 5.73 5.72 5.72 5.72 5.72 5.72 7.58 7.49 7.49 7.49 7.49 7.49 7.49 7.49
new dpdf2 all-cpus r2: threads 20 frames 173095 | median 6.271 p99 10.274 p99.9 16.011 max 39.17 ms | >1.2x 34.89% >1.5x 5.236% >2x 0.400% | fastest 5.715
new dpdf2 all-cpus r2: same-core 127485 >1.2x 1.30% >1.5x 0.132% >2x 0.024% | moved 45610 (26.35%) | pcores[0,1,2,3,4,5,6,7,8,9,10,11] 89420 >1.2x 1.15% >1.5x 0.123% >2x 0.023% p99 6.937 p99.9 8.970 | cpu fastest ms 5.72 5.72 5.72 5.72 5.72 5.72 5.79 5.72 5.72 5.72 5.71 5.72 7.60 7.48 7.49 7.49 7.49 7.49 7.49 7.49
new off all-cpus r2: threads 20 frames 174485 | median 6.181 p99 10.518 p99.9 15.840 max 55.69 ms | >1.2x 33.82% >1.5x 6.530% >2x 0.503% | fastest 5.715
new off all-cpus r2: same-core 141868 >1.2x 1.51% >1.5x 0.107% >2x 0.022% | moved 32617 (18.69%) | pcores[0,1,2,3,4,5,6,7,8,9,10,11] 106274 >1.2x 0.97% >1.5x 0.047% >2x 0.014% p99 6.902 p99.9 8.162 | cpu fastest ms 5.72 5.72 5.72 5.72 5.72 5.72 5.80 5.72 5.72 5.72 5.71 5.72 7.58 7.49 7.49 7.49 7.49 7.49 7.49 7.49
new dpdf2 free2 r1: threads 18 frames 158726 | median 6.273 p99 8.529 p99.9 9.876 max 35.41 ms | >1.2x 35.26% >1.5x 2.351% >2x 0.066% | fastest 5.628
new dpdf2 free2 r1: same-core 110663 >1.2x 21.30% >1.5x 0.042% >2x 0.005% | moved 48063 (30.28%) | pcores[0,1,2,3,4,5,6,7,8,9,10,11,12,13,16,17] 90241 >1.2x 15.43% >1.5x 0.044% >2x 0.003% p99 8.446 p99.9 8.643 | cpu fastest ms 5.72 5.72 5.72 5.72 5.72 5.72 5.77 5.72 5.72 5.63 5.64 5.72 5.97 6.30 6.92 6.70 6.24 6.11 6.74 7.39
old off all-cpus r2: threads 20 frames 172191 | median 6.312 p99 10.249 p99.9 14.970 max 39.82 ms | >1.2x 39.75% >1.5x 28.200% >2x 0.602% | fastest 5.419
old off all-cpus r2: same-core 138732 >1.2x 2.47% >1.5x 0.130% >2x 0.027% | moved 33459 (19.43%) | pcores[0,1,2,3,4,5,6,7,8,9,10,11] 101598 >1.2x 2.73% >1.5x 0.112% >2x 0.029% p99 7.046 p99.9 8.640 | cpu fastest ms 5.42 5.72 5.67 5.72 5.64 5.72 5.83 5.72 5.72 5.72 5.72 5.72 7.53 7.49 7.49 7.49 7.49 7.49 7.49 7.49
old dpdf2 all-cpus r2: threads 20 frames 166854 | median 6.364 p99 11.091 p99.9 16.554 max 40.53 ms | >1.2x 39.39% >1.5x 11.882% >2x 0.810% | fastest 5.716
old dpdf2 all-cpus r2: same-core 129195 >1.2x 3.17% >1.5x 1.574% >2x 0.163% | moved 37659 (22.57%) | pcores[0,1,2,3,4,5,6,7,8,9,10,11] 93340 >1.2x 3.08% >1.5x 2.054% >2x 0.219% p99 9.590 p99.9 12.753 | cpu fastest ms 5.73 5.72 5.72 5.72 5.72 5.72 5.91 5.73 5.72 5.72 5.72 5.72 7.61 7.49 7.49 7.49 7.49 7.49 7.49 7.49
old dpdf2 free2 r1: threads 18 frames 156048 | median 6.340 p99 8.618 p99.9 10.462 max 65.47 ms | >1.2x 37.17% >1.5x 14.850% >2x 0.078% | fastest 5.529
old dpdf2 free2 r1: same-core 113916 >1.2x 15.04% >1.5x 0.053% >2x 0.010% | moved 42132 (27.00%) | pcores[0,1,2,3,4,5,6,7,8,9,10,11] 80385 >1.2x 0.55% >1.5x 0.051% >2x 0.006% p99 6.621 p99.9 7.770 | cpu fastest ms 5.76 5.72 5.72 5.72 5.72 5.72 5.53 5.73 5.71 5.72 5.72 5.72 6.40 6.72 6.91 7.47 6.74 7.49 6.98 6.76
old dpdf2 free2 r2: threads 18 frames 156273 | median 6.338 p99 8.596 p99.9 10.444 max 40.48 ms | >1.2x 35.28% >1.5x 1.225% >2x 0.067% | fastest 5.715
old dpdf2 free2 r2: same-core 112514 >1.2x 20.13% >1.5x 0.068% >2x 0.008% | moved 43759 (28.00%) | pcores[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15] 89555 >1.2x 12.26% >1.5x 0.075% >2x 0.006% p99 8.526 p99.9 8.879 | cpu fastest ms 5.75 5.73 5.72 5.72 5.71 5.72 5.88 5.73 5.72 5.72 5.72 5.72 6.23 6.29 6.53 6.35 7.17 6.81 7.00 6.87
new dpdf2 free2 r2: threads 18 frames 158232 | median 6.286 p99 8.533 p99.9 9.503 max 37.21 ms | >1.2x 34.55% >1.5x 0.626% >2x 0.042% | fastest 5.715
new dpdf2 free2 r2: same-core 110101 >1.2x 18.29% >1.5x 0.030% >2x 0.005% | moved 48131 (30.42%) | pcores[0,1,2,3,4,5,6,7,8,9,10,11,12,13,15,18] 89259 >1.2x 14.14% >1.5x 0.031% >2x 0.004% p99 8.455 p99.9 8.631 | cpu fastest ms 5.72 5.72 5.72 5.72 5.71 5.72 5.80 5.72 5.71 5.72 5.72 5.71 6.10 6.34 6.99 6.54 6.73 6.92 6.53 6.98
new dpdf8 all-cpus r1: threads 20 frames 172668 | median 6.268 p99 10.393 p99.9 16.365 max 44.59 ms | >1.2x 34.57% >1.5x 6.345% >2x 0.479% | fastest 5.714
new dpdf8 all-cpus r1: same-core 135610 >1.2x 1.71% >1.5x 0.179% >2x 0.036% | moved 37058 (21.46%) | pcores[0,1,2,3,4,5,6,7,8,9,10,11] 99858 >1.2x 1.29% >1.5x 0.147% >2x 0.033% p99 7.075 p99.9 9.100 | cpu fastest ms 5.72 5.72 5.72 5.72 5.72 5.72 5.80 5.72 5.72 5.72 5.71 5.72 7.58 7.49 7.49 7.48 7.49 7.49 7.49 7.49
closed all-cpus r2: threads 20 frames 177063 | median 6.110 p99 9.718 p99.9 14.918 max 70.88 ms | >1.2x 34.95% >1.5x 26.908% >2x 0.388% | fastest 5.329
closed all-cpus r2: same-core 149504 >1.2x 1.41% >1.5x 0.069% >2x 0.018% | moved 27559 (15.56%) | pcores[0,1,2,3,4,5,6,7,8,9,10,11] 110744 >1.2x 1.21% >1.5x 0.054% >2x 0.016% p99 6.630 p99.9 7.557 | cpu fastest ms 5.72 5.72 5.71 5.72 5.72 5.72 5.33 5.72 5.72 5.72 5.72 5.72 7.49 7.06 7.06 7.06 7.06 7.48 7.48 7.48
closed free2 r1: threads 18 frames 160130 | median 6.115 p99 8.360 p99.9 8.920 max 106.27 ms | >1.2x 36.26% >1.5x 0.245% >2x 0.044% | fastest 5.714
closed free2 r1: same-core 109219 >1.2x 24.53% >1.5x 0.018% >2x 0.010% | moved 50911 (31.79%) | pcores[0,1,2,3,4,5,6,7,8,9,10,11,12,13,15,17,18] 93309 >1.2x 22.18% >1.5x 0.018% >2x 0.011% p99 8.290 p99.9 8.524 | cpu fastest ms 5.72 5.72 5.72 5.71 5.71 5.72 5.72 5.75 5.71 5.72 5.71 5.72 6.25 6.24 6.83 6.38 7.06 6.50 5.93 6.70
```

CS2 (PresentMon, `MsBetweenPresents`):

```
closed-r1: frames 28072 | avg 312.0 fps, 1% low 168.6 fps | median 2.98 p99 5.69 p99.9 6.08 max 20.2 ms | >1.5x median 13.94% >2x 0.256%
old-dpdf2-r1: frames 28430 | avg 315.9 fps, 1% low 186.3 fps | median 2.98 p99 5.18 p99.9 5.60 max 6.3 ms | >1.5x median 11.15% >2x 0.007%
old-off-r1: frames 28544 | avg 317.2 fps, 1% low 190.4 fps | median 2.98 p99 5.06 p99.9 5.47 max 6.4 ms | >1.5x median 9.41% >2x 0.007%
new-off-r1: frames 27148 | avg 301.7 fps, 1% low 178.5 fps | median 3.13 p99 5.44 p99.9 5.82 max 6.3 ms | >1.5x median 13.97% >2x 0.000%
new-dpdf2-r1: frames 27526 | avg 305.9 fps, 1% low 181.0 fps | median 3.05 p99 5.34 p99.9 5.76 max 6.4 ms | >1.5x median 14.24% >2x 0.015%
new-dpdf2-r2: frames 27660 | avg 307.4 fps, 1% low 181.8 fps | median 3.08 p99 5.30 p99.9 5.73 max 7.2 ms | >1.5x median 10.42% >2x 0.007%
new-off-r2: frames 27288 | avg 303.2 fps, 1% low 176.5 fps | median 3.09 p99 5.51 p99.9 5.85 max 6.1 ms | >1.5x median 15.82% >2x 0.000%
old-off-r2: frames 26779 | avg 297.6 fps, 1% low 176.7 fps | median 3.17 p99 5.48 p99.9 5.87 max 7.2 ms | >1.5x median 14.62% >2x 0.007%
old-dpdf2-r2: frames 27292 | avg 303.3 fps, 1% low 178.7 fps | median 3.10 p99 5.40 p99.9 5.88 max 6.5 ms | >1.5x median 12.66% >2x 0.011%
closed-r2: frames 27159 | avg 301.8 fps, 1% low 191.2 fps | median 3.23 p99 5.06 p99.9 5.43 max 7.0 ms | >1.5x median 2.62% >2x 0.004%
```

Rift's log, DPDFNet lines (new build, one call per run):

```
too slow here for DPDFNet-8, ran DPDFNet-2 / 1 frames late      (test 1 call, idle)
5768 frames late, sent unfiltered                                (game, all CPUs, run 1)
5770 frames late, sent unfiltered                                (game, all CPUs, run 2)
114 frames late, sent unfiltered                                 (game, 2 CPUs free, run 1)
83 frames late, sent unfiltered                                  (game, 2 CPUs free, run 2)
too slow here for DPDFNet-8, ran DPDFNet-2 / 3 frames late       (DPDFNet-8, idle)
too slow here for DPDFNet-8, ran DPDFNet-2 / 5774 frames late    (DPDFNet-8, game, all CPUs)
8 frames late, sent unfiltered                                   (CS2, run 1)
(no line: none late)                                             (CS2, run 2)
```

Part 2, each state (`measure.ps1`):

```
1 not in a call, Settings in front: CPU 3.2% of a core | GPU 3d 0.4% | rx 9 kbit/s tx 14 kbit/s | working set 703 -> 666 MB, private 662 -> 625 MB, threads 90 | frames drawn 1.0/s
1b not in a call, behind the terminal: CPU 1.5% of a core | GPU 3d 0.2% | rx 15 kbit/s tx 116 kbit/s | working set 728 -> 512 MB, private 673 -> 453 MB, threads 86 | frames drawn 1.0/s
2 in call, not watching, call page in front: CPU 108.6% of a core | GPU 3d 61.9% | rx 30,165 kbit/s tx 299 kbit/s | working set 951 -> 954 MB, private 897 -> 901 MB, threads 106 | frames drawn 49.6/s
2b in call, not watching, minimised: CPU 26.6% of a core | GPU 3d 2.5% | rx 27,713 kbit/s tx 152 kbit/s | working set 908 -> 894 MB, private 852 -> 839 MB, threads 101 | frames drawn 2.0/s
2c in call, not watching, behind the terminal: CPU 20.7% of a core | GPU 3d 4.0% | rx 14,503 kbit/s tx 170 kbit/s | working set 901 -> 954 MB, private 846 -> 902 MB, threads 100 | frames drawn 2.0/s
2d in call, not watching, call page in front again: CPU 91.8% of a core | GPU 3d 53.3% | rx 32,894 kbit/s tx 255 kbit/s | working set 942 -> 976 MB, private 888 -> 922 MB, threads 98 | frames drawn 49.6/s
3 watching, call page in front: CPU 145.6% of a core | GPU 3d 72.1% | rx 31,995 kbit/s tx 109 kbit/s | working set 1,008 -> 959 MB, private 954 -> 903 MB, threads 97 | frames drawn 89.2/s
3b watching, minimised: CPU 140.3% of a core | GPU 3d 73.3% | rx 21,572 kbit/s tx 170 kbit/s | working set 949 -> 960 MB, private 895 -> 905 MB, threads 96 | frames drawn 93.8/s
3c watching, behind the terminal: CPU 123.0% of a core | GPU 3d 61.7% | rx 31,505 kbit/s tx 265 kbit/s | working set 843 -> 710 MB, private 778 -> 645 MB, threads 99 | frames drawn 156.1/s
6 stopped watching, call page in front: CPU 123.4% of a core | GPU 3d 68.7% | rx 33,408 kbit/s tx 250 kbit/s | working set 1,042 -> 953 MB, private 988 -> 898 MB, threads 96 | frames drawn 60.9/s
7 (MISLABELLED: the Leave click missed, still in the call, stopped watching, music on) CPU 127.0% of a core | GPU 3d 68.6% | rx 33,213 kbit/s tx 251 kbit/s | working set 979 -> 951 MB, private 924 -> 897 MB, threads 97 | frames drawn 60.6/s
7 left the call, home in front: CPU 2.7% of a core | GPU 3d 0.5% | rx 9 kbit/s tx 20 kbit/s | working set 937 -> 719 MB, private 881 -> 662 MB, threads 86 | frames drawn 1.0/s
8 in call, no share, music playing, call page in front: CPU 91.9% of a core | GPU 3d 62.1% | rx 407 kbit/s tx 245 kbit/s | working set 1,018 -> 1,024 MB, private 968 -> 975 MB, threads 99 | frames drawn 65.9/s
8b in call, no share, music playing, minimised: CPU 111.0% of a core | GPU 3d 74.9% | rx 406 kbit/s tx 167 kbit/s | working set 1,033 -> 1,037 MB, private 984 -> 987 MB, threads 97 | frames drawn 74.2/s
9 in call, no share, no music, call page in front: CPU 7.9% of a core | GPU 3d 2.8% | rx 137 kbit/s tx 41 kbit/s | working set 959 -> 912 MB, private 912 -> 864 MB, threads 99 | frames drawn 3.0/s
9b in call, no share, no music, minimised: CPU 6.4% of a core | GPU 3d 2.8% | rx 140 kbit/s tx 161 kbit/s | working set 943 -> 970 MB, private 894 -> 919 MB, threads 96 | frames drawn 3.0/s
10 music on again, minimised (same session, watched once): CPU 109.9% of a core | GPU 3d 70.8% | rx 424 kbit/s tx 269 kbit/s | working set 1,012 -> 1,038 MB, private 963 -> 989 MB, threads 96 | frames drawn 67.5/s
11 fresh start, music, call page in front: CPU 98.4% of a core | GPU 3d 67.7% | rx 489 kbit/s tx 272 kbit/s | working set 802 -> 824 MB, private 784 -> 803 MB, threads 108 | frames drawn 65.9/s
11b fresh start, music, minimised: CPU 107.9% of a core | GPU 3d 70.5% | rx 401 kbit/s tx 173 kbit/s | working set 825 -> 824 MB, private 802 -> 801 MB, threads 103 | frames drawn 70.5/s
12 fresh, share on, no music, not watching, in front: CPU 9.9% of a core | GPU 3d 2.5% | rx 30 kbit/s tx 35 kbit/s | working set 802 -> 802 MB, private 779 -> 780 MB, threads 97 | frames drawn 2.5/s
12b fresh, share on, no music, not watching, minimised: CPU 8.6% of a core | GPU 3d 2.3% | rx 41 kbit/s tx 133 kbit/s | working set 801 -> 812 MB, private 776 -> 786 MB, threads 95 | frames drawn 2.1/s
13 fresh, watching, in front: CPU 86.8% of a core | GPU 3d 61.6% | rx 29,550 kbit/s tx 3,957 kbit/s | working set 914 -> 862 MB, private 889 -> 834 MB, threads 97 | frames drawn 52.7/s
14 fresh, stopped watching, in front: CPU 9.8% of a core | GPU 3d 3.3% | rx 27 kbit/s tx 34 kbit/s | working set 926 -> 817 MB, private 899 -> 790 MB, threads 95 | frames drawn 3.2/s
14b fresh, stopped watching, minimised: CPU 9.7% of a core | GPU 3d 3.1% | rx 39 kbit/s tx 147 kbit/s | working set 837 -> 807 MB, private 811 -> 785 MB, threads 95 | frames drawn 3.0/s
15 rejoined with share already running, not watching, in front: CPU 29.2% of a core | GPU 3d 2.6% | rx 31,251 kbit/s tx 43 kbit/s | working set 853 -> 877 MB, private 833 -> 857 MB, threads 103 | frames drawn 2.3/s
15b rejoined with share running, not watching, minimised: CPU 22.5% of a core | GPU 3d 2.5% | rx 22,524 kbit/s tx 161 kbit/s | working set 868 -> 809 MB, private 846 -> 788 MB, threads 98 | frames drawn 2.3/s
16 rejoined case, watching, in front: CPU 16.0% of a core | GPU 3d 3.2% | rx 9,510 kbit/s tx 53 kbit/s | working set 917 -> 909 MB, private 896 -> 888 MB, threads 97
17 rejoined case, stopped watching, in front: CPU 19.8% of a core | GPU 3d 3.9% | rx 14,909 kbit/s tx 44 kbit/s | working set 945 -> 827 MB, private 924 -> 806 MB, threads 97
19 rejoined case, stopped watching (tile view), in front: CPU 26.8% of a core | GPU 3d 3.3% | rx 28,625 kbit/s tx 45 kbit/s | working set 934 -> 868 MB, private 912 -> 848 MB, threads 98
20 clean rejoin, music, no share, in front: CPU 104.3% of a core | GPU 3d 68.5% | rx 413 kbit/s tx 261 kbit/s | working set 934 -> 979 MB, private 916 -> 962 MB, threads 103 | frames drawn 65.5/s
20b clean rejoin, music, no share, behind the terminal: CPU 134.1% of a core | GPU 3d 72.6% | rx 406 kbit/s tx 147 kbit/s | working set 668 -> 643 MB, private 640 -> 616 MB, threads 103 | frames drawn 147.0/s
21 watching (shows), behind the terminal: CPU 83.5% of a core | GPU 3d 33.6% | rx 31,031 kbit/s tx 180 kbit/s | working set 848 -> 685 MB, private 816 -> 653 MB, threads 99
```

Part 2, the stand-in game:

```
old off, unwatched stream decoding (rejoined case) all-cpus r1: threads 20 frames 166510 | median 6.437 p99 12.662 p99.9 19.336 max 39.20 ms | >1.2x 40.36% >1.5x 12.331% >2x 1.920% | fastest 5.716
old off, unwatched stream decoding (rejoined case) all-cpus r1: same-core 113624 >1.2x 3.96% >1.5x 0.755% >2x 0.332% | moved 52886 (31.76%) | pcores[0,1,2,3,4,5,6,7,8,9,10,11] 78885 >1.2x 3.92% >1.5x 0.839% >2x 0.420% p99 8.223 p99.9 14.121 | cpu fastest ms 5.73 5.72 5.72 5.72 5.72 5.76 5.72 5.72 5.72 5.72 5.72 5.72 7.66 7.49 7.49 7.49 7.49 7.49 7.49 7.48
old off, music bot speaking, no share all-cpus r1: threads 20 frames 155815 | median 6.571 p99 18.630 p99.9 31.252 max 40.40 ms | >1.2x 40.50% >1.5x 20.548% >2x 6.569% | fastest 5.716
old off, music bot speaking, no share all-cpus r1: same-core 99526 >1.2x 5.35% >1.5x 1.305% >2x 0.478% | moved 56289 (36.13%) | pcores[0,1,2,3,4,5,6,7,8,9,10,11] 76070 >1.2x 4.42% >1.5x 0.789% >2x 0.514% p99 8.121 p99.9 23.057 | cpu fastest ms 5.84 5.73 5.72 5.72 5.83 5.73 5.79 5.72 5.72 5.72 5.72 5.72 8.30 8.24 8.03 7.80 7.49 7.49 7.49 7.49
old off, watching stream, Rift behind all-cpus r1: threads 20 frames 147895 | median 6.813 p99 20.858 p99.9 28.765 max 71.31 ms | >1.2x 48.52% >1.5x 26.921% >2x 10.024% | fastest 5.716
old off, watching stream, Rift behind all-cpus r1: same-core 87280 >1.2x 11.91% >1.5x 2.786% >2x 1.232% | moved 60615 (40.99%) | pcores[0,1,2,3,4,5,6,7,8,9,10,11] 67237 >1.2x 10.53% >1.5x 1.746% >2x 0.910% p99 11.005 p99.9 17.968 | cpu fastest ms 5.77 5.80 5.72 5.72 5.83 5.72 5.73 5.72 5.72 5.72 5.72 5.72 7.87 7.83 7.62 7.49 7.49 7.49 7.49 7.49
```

