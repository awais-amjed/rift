# Round 3: DPDFNet on its own thread, on the Intel laptop's Windows, Oct 25 2026

The answers to `scripts/perf/ROUND3.md`, run on `perf-testing` at `a1826c2e`,
against round 2's numbers (`laptop-windows-2026-10-25-round2.md`). As before, a
Claude session drove Rift itself, and the user set up the call.

**In short:** the noise models are back on Windows, ready before Settings can
be opened (A). On its own thread, DPDFNet-2 does not get the stand-in game back
to where it is with the filter Off, at either priority (B). On the game the two
priorities are within each other's noise, and mostly worse than the model on
the capture thread in round 2, with p99.9 about 4 ms worse. On the voice they
differ: at normal about 2% goes out unfiltered, at above normal none. In CS2
(C), at normal, DPDFNet-2 costs nothing measurable against Off and no frame is
late. But this laptop's CS2 is only close to CPU-bound, not fully: its GPU
still paces the frames at the lowest settings.

## The machine

The same laptop as rounds 1 and 2, unchanged: Intel Core i7-12700H
(performance cores are logical CPUs 0–11, efficiency cores 12–19), 32 GB, on
AC, Windows 11 Home 26200.

**Build:** this branch, `cargo build -p rust_lib_rift --release --target
x86_64-pc-windows-msvc`, then `flutter build windows --release`. Both of
ROUND3's checks are true: `rust_lib_rift.dll` has "DPDFNet's thread stopped"
and "RIFT_DPDFNET_PRIORITY". No local patch this time.

**The call:** the user's account in CS Chat on their own server, unmuted, push
to talk off. DJ Riff played music and Gracie (the user's other PC) shared at
1080p60, unwatched, in every in-call run, as in round 2's part F.

## A. The noise models are back

- [x] Noise suppression offers Off, Standard, RNNoise and DPDFNet, and Mic
  volume shows (Settings opened 4.5 s after launch, 1.9 s after the window
  appeared).
- [x] Picked DPDFNet (DPDFNet-2), quit Rift, started it again. Settings opened
  on DPDFNet and DPDFNet-2. The log has `DPDFNet's thread at normal priority`
  and `DPDFNet loaded` 1.2 s after launch, before the window was up. No
  `Noise filter: the runner has none` on any launch this round (six).
- [x] "Starting noise suppression…" never showed. The filter was ready before
  the window appeared, so Settings cannot be reached in time to see it.
  Screenshots at 4.3–5.5 s after launch, on two launches.

## B. Beside the stand-in game: is the voice still filtered?

`gameloop2` on all CPUs, the terminal in front, 60 s per run, 15 s apart.
DPDFNet-2 throughout. Rift was left and rejoined around each DPDFNet run, so
each late-frame count covers one run (join to leave, about 100 s).

threadtop's `prio` column is the thread's priority minus the process's base
(8). So normal reads 0 and above normal 1, the 8 and 10 that ROUND3 names. The
capture thread's 18 is MMCSS's 26.

| | Slow (same core) | Over 1.5× | Over 2× | p99.9, performance cores | Rift | Model thread | Capture thread | Unfiltered |
|---|---|---|---|---|---|---|---|---|
| Rift closed, run 1 | 0.76% | 0.069% | 0.019% | 7.52 ms | — | — | — | — |
| Off, run 1 | 1.93% | 0.279% | 0.083% | 8.34 ms | 8.6% | — | 2.7%, 18 | — |
| DPDFNet-2, normal, run 1 | 4.94% | **1.661%** | 0.412% | **15.92 ms** | 39.9% | 28.9%, 0 | 3.1%, 18 | **237 of 10,031 (2.4%)** |
| DPDFNet-2, above normal, run 1 | 3.18% | **0.932%** | 0.333% | **16.17 ms** | 54.1% | 39.4%, 1 | 3.7%, 18 | **0 of 10,609** |
| DPDFNet-2, above normal, run 2 | 3.95% | **0.920%** | 0.382% | **15.90 ms** | 56.7% | 41.7%, 1 | 2.3%, 18 | **0 of 9,670** |
| DPDFNet-2, normal, run 2 | 4.24% | **1.268%** | 0.328% | **12.84 ms** | 38.1% | 27.0%, 0 | 2.9%, 18 | **172 of 9,640 (1.8%)** |
| Off, run 2 | 1.96% | 0.314% | 0.097% | 8.25 ms | 9.1% | — | 2.4%, 18 | — |
| Rift closed, run 2 | 4.15% | 0.090% | 0.016% | 7.79 ms | — | — | — | — |
| *Rerun:* DPDFNet-2, normal, run 3 | 5.80% | **1.781%** | 0.496% | **16.27 ms** | 41.3% | 28.4%, 0 | 3.2%, 18 | **248 of 9,791 (2.5%)** |
| *Rerun:* DPDFNet-2, above normal, run 3 | 5.01% | **1.614%** | 0.463% | **16.32 ms** | 38.2% | 28.8%, 1 | 2.2%, 18 | **0 of 10,412** |

**The reruns.** Afterwards the user thought DJ Riff might have stopped playing
during the first runs, so normal and above normal ran once more with the queue
filled. DJ Riff's speaking ring was on at each join. Normal came out as before.
Above normal did not: its share of slow frames rose to normal's (1.61% against
0.92–0.93%), and its model thread used 29% of a core, like normal's, instead of
39–42%. Whether the music was playing in the first above-normal runs is not
known. The other difference is the model's CPU, which may mean the thread ran
on efficiency cores in runs 4 and 5, slower but away from the game's
performance cores. So the gap between the two priorities on the game is within
the noise. The gap on the voice is not: above normal had no late frame in
three runs, normal 1.8–2.5% in three.

Round 2's part F beside it, the same call and the same tool:

| Round 2 | Over 1.5× | p99.9, performance cores | Model's CPU | Unfiltered |
|---|---|---|---|---|
| Rift closed | 0.099%, 0.095% | 7.90, 7.97 ms | — | — |
| Off | 0.314%, 0.164% | 8.23, 8.30 ms | — | — |
| DPDFNet-2 on the capture thread (18) | 0.830%, 0.915% | 12.24, 12.27 ms | 32.4%, 31.9% | none |

The baselines held. Rift closed and Off land where round 2's did: 0.07–0.09%
and 0.28–0.31% over 1.5×, 7.5–7.8 ms and 8.3 ms p99.9. The second closed run's
slow share is high for the same reason as round 2's: some CPUs ran a frame
unusually fast (5.32 ms), which raises their bar.

Late frames, worst times and frames over 5 ms, from the log at each leave:

| Run | Frames | Late, sent unfiltered | Worst | Over 5 ms |
|---|---|---|---|---|
| Normal, run 1 | 10,031 | 237 | 8.0 ms | 443 |
| Above normal, run 1 | 10,609 | 0 | 5.7 ms | 4 |
| Above normal, run 2 | 9,670 | 0 | 5.8 ms | 9 |
| Normal, run 2 | 9,640 | 172 | 8.4 ms | 282 |
| Normal, run 3 (rerun) | 9,791 | 248 | 8.1 ms | 438 |
| Above normal, run 3 (rerun) | 10,412 | 0 | 4.3 ms | 0 |

In runs 4 and 5 the model's thread used more CPU at above normal (39–42% of a
core) than at normal (27–29%) for about the same number of frames. In the
above-normal rerun it used 29%. That is not explained here. It may be where
the scheduler puts it: an efficiency core does the same work in more time.

## C. CS2, as CPU-bound as this laptop allows

The user stopped playing on the other PC for this. CS2 ran offline on
de_dust2 with the bots kicked, `fps_max 0`, the round held open
(`mp_ignore_round_win_conditions 1`, `mp_roundtime_defuse 60`), and F8 bound
to the same `setpos`/`setang` as round 1. Each capture is 90 s of PresentMon
2.6.0 from 10 s after F8, with threadtop alongside. The call was the same as in
B: DJ Riff's music and Gracie's unwatched share. Normal priority only: B showed
normal not starving the model, so by ROUND3's rule above normal was not added.

**It is not fully CPU-bound.** At the lowest settings and full screen, the RTX
3070 Ti Laptop GPU sat at 99% (power-limited at about 99 W, 1,170 MHz): GPU
busy 3.74 ms a frame, CPU busy 0.96 ms. A 960×540 window in `cs2_video.txt`
renders at that size, stretched to full screen; CS2 has no
`mat_setvideomode`. At that size, CPU busy is 2.0–2.5 ms of a 3.5 ms frame and
GPU busy 2.6–3.1 ms. Both are close to the limit, the GPU still a little more.
The settings file goes no lower. The CPU busy figures are below, so the model's
cost can be read there.

| | Avg fps | 1% low | p99 | p99.9 | Max | CPU busy | GPU busy | Rift | Model thread | Unfiltered |
|---|---|---|---|---|---|---|---|---|---|---|
| Rift closed, run 1 | 288.8 | 106.0 | 8.99 | 10.03 | 11.7 | 2.03 | 2.93 | — | — | — |
| Off, run 1 | 279.4 | 99.6 | 9.37 | 10.80 | 22.6 | 2.23 | 2.86 | 10.2% | — | — |
| Off, run 1 again | 295.7 | 106.5 | 8.90 | 10.05 | 11.3 | 2.30 | 2.61 | 10.7% | — | — |
| DPDFNet-2, normal, run 1 | 281.8 | 100.0 | 9.38 | 10.74 | 12.0 | 2.46 | 2.64 | 51.4% | 33.1%, 0 | 0 of 21,233 |
| DPDFNet-2, normal, run 2 | 277.7 | 100.3 | 9.32 | 10.52 | 22.2 | 2.44 | 2.76 | 46.9% | 34.6%, 0 | 0 of 12,792 |
| Off, run 2 | 281.7 | 98.9 | 9.41 | 10.85 | 21.3 | 2.22 | 2.80 | 8.7% | — | — |
| Rift closed, run 2 | 276.9 | *48.8* | 9.45 | *25.19* | 33.1 | 2.20 | 2.94 | — | — | — |
| Rift closed, run 3 | 283.8 | 105.7 | 9.05 | 9.94 | 18.9 | 1.98 | 3.06 | — | — | — |

Times in ms, averages over the run. Some notes on the runs:

- **Off, run 1 again.** At the join for the first Off run, DJ Riff showed no
  ring. It was rerun once the ring was seen. The ring and the bot's presence
  lag a few seconds behind a join, so the music was probably on in both. Both
  are given.
- **Rift closed, run 2** had a burst of 183 frames over 20 ms that no other
  run has. Rift had just been closed. A third closed run was clean and stands
  in for it.
- **Over 1.5× is left out.** It is 28–33% in every run, Rift closed too,
  because CS2's frame times here are bimodal around a 2.7 ms median. The 1%
  low and p99.9 carry the stutter instead.

**The answer for CS2: DPDFNet-2 at normal costs this game nothing measurable.**
Against Off, average fps is 278–282 against 280–296. The 1% low is 100
against 99–107, and p99.9 is 10.5–10.7 ms against 10.1–10.9. All of it is
inside the spread of the Off runs themselves. CPU busy goes up about 0.2 ms a
frame (2.45 against 2.22–2.30), which is the model's share of the cores, but
here the GPU paces the frames. The voice was fully filtered: no late frame in
34,025, and 1 in 50,447 over eight minutes in the call beside CS2 while the
test was held.

The model's thread switches about 600 times a second beside CS2, against about
108 beside the stand-in game, at the same CPU (33–35% of a core). Each 10 ms
frame is cut into several slices: CS2's threads preempt it at the same
priority. It still finishes in time.

## The answer

1. **Does the game suffer?** Yes, at both priorities, by more than the gap
   between the two Rift-closed runs (0.02 points over 1.5×, 0.27 ms p99.9).
   - **Normal:** frames over 1.5× go from 0.28–0.31% (Off) to 1.27–1.78%,
     worse than round 2's capture thread (0.83–0.92%). p99.9 is 12.8–16.3 ms,
     against 8.3 Off and 12.2 on the capture thread.
   - **Above normal:** 0.92–0.93% over 1.5× in runs 4 and 5, the same as round
     2's capture thread, but 1.61% in the rerun, normal's level. p99.9 is
     15.9–16.3 ms in all three, about 4 ms worse than the capture thread and
     8 ms worse than Off.
2. **Is the voice still filtered?**
   - **Normal:** mostly. 1.8–2.5% of frames went out unfiltered, against round
     1's 96% below normal.
   - **Above normal:** fully, with no late frames in three runs.

By ROUND3's rule, **neither works**. Both keep the voice filtered, but neither
keeps the game near Off, and on the game the two are within each other's
noise. Above normal is the better of the two, since it filters every frame
for the same cost. Both have a worse tail than the capture thread had. On this machine the model needs about 30–40% of a core, and
whichever thread does it, a game that holds every CPU loses that time. The
stand-in game is the worst case by construction.

**In CS2, normal works** (C): the game is unchanged against Off, and every
frame of the voice was filtered. Above normal was not run there.

So for the decision: **normal priority** keeps a real game whole and the voice
filtered on this machine. The stand-in game shows the limit. A game that holds
every core loses the model's 30–40% of a core whatever its priority, and at
normal about 2% of the voice goes unfiltered. Above normal would close that
2% at no cost seen in B, but it was not measured in CS2.

## Worth fixing

1. **DPDFNet-2 beside a game that holds every core** has no priority here
   that leaves the game near Off (B). CS2 here was not that game (C). Should
   a real game turn out to be one, the choice between "the voice filtered"
   and "the game untouched" is the user's to make. For example, DPDFNet could fall back
   to RNNoise while a game holds every CPU, or Settings could say what DPDFNet
   costs beside a game.
2. **The model's thread costs more CPU at above normal** (B), for the same
   work. Worth a look at where its frames run.

## Left as found

The filter was left Off; Rift is closed. Nothing was sent in a chat. The
`RIFT_DPDFNET_PRIORITY` variable was set only for the Rift started for the
above-normal runs.

CS2: `cs2_video.txt` was backed up, set to the lowest settings at 960×540 for
C, and restored byte for byte afterwards (its hash checked). F8 was unbound and
`fps_max` set back to 400 before quitting. CS2's other config files were
compared with a copy taken before the quit and are unchanged. CS2 is closed.

## Appendix: raw lines

`gameloop2` (the second line of each pair is the per-CPU measure used above):

```
R3 B closed all-cpus r1: threads 20 frames 182566 | median 5.910 p99 9.305 p99.9 13.137 max 109.50 ms | >1.2x 33.55% >1.5x 2.350% >2x 0.178% | fastest 5.639
R3 B closed all-cpus r1: same-core 152728 >1.2x 0.76% >1.5x 0.069% >2x 0.019% | moved 29838 (16.34%) | pcores[0..11] 113293 >1.2x 0.44% >1.5x 0.037% >2x 0.018% p99 6.486 p99.9 7.521
R3 B off music+share all-cpus r1: threads 20 frames 171958 | median 6.197 p99 13.336 p99.9 21.551 max 38.31 ms | >1.2x 33.58% >1.5x 9.012% >2x 1.924% | fastest 5.715
R3 B off music+share all-cpus r1: same-core 132006 >1.2x 1.93% >1.5x 0.279% >2x 0.083% | moved 39952 (23.23%) | pcores[0..11] 101399 >1.2x 1.46% >1.5x 0.078% >2x 0.027% p99 7.045 p99.9 8.340
R3 B dpdf2 normal music+share all-cpus r1: threads 20 frames 161759 | median 6.600 p99 12.966 p99.9 19.595 max 39.60 ms | >1.2x 44.93% >1.5x 17.608% >2x 2.049% | fastest 5.717
R3 B dpdf2 normal music+share all-cpus r1: same-core 105314 >1.2x 4.94% >1.5x 1.661% >2x 0.412% | moved 56445 (34.89%) | pcores[0..11] 74442 >1.2x 5.55% >1.5x 2.174% >2x 0.552% p99 10.380 p99.9 15.923
R3 B dpdf2 above music+share all-cpus r1: threads 20 frames 163284 | median 6.468 p99 15.022 p99.9 20.302 max 37.46 ms | >1.2x 38.04% >1.5x 14.722% >2x 4.049% | fastest 5.716
R3 B dpdf2 above music+share all-cpus r1: same-core 116678 >1.2x 3.18% >1.5x 0.932% >2x 0.333% | moved 46606 (28.54%) | pcores[0..11] 86375 >1.2x 2.74% >1.5x 0.587% >2x 0.330% p99 7.801 p99.9 16.165
R3 B dpdf2 above music+share all-cpus r2: threads 20 frames 162658 | median 6.520 p99 15.119 p99.9 20.581 max 39.41 ms | >1.2x 38.60% >1.5x 16.297% >2x 4.205% | fastest 5.716
R3 B dpdf2 above music+share all-cpus r2: same-core 112906 >1.2x 3.95% >1.5x 0.920% >2x 0.382% | moved 49752 (30.59%) | pcores[0..11] 84888 >1.2x 3.55% >1.5x 0.585% >2x 0.358% p99 7.735 p99.9 15.897
R3 B dpdf2 normal music+share all-cpus r2: threads 20 frames 164518 | median 6.372 p99 14.041 p99.9 22.068 max 39.21 ms | >1.2x 39.56% >1.5x 13.980% >2x 2.575% | fastest 5.714
R3 B dpdf2 normal music+share all-cpus r2: same-core 122697 >1.2x 4.24% >1.5x 1.268% >2x 0.328% | moved 41821 (25.42%) | pcores[0..11] 91220 >1.2x 4.13% >1.5x 1.373% >2x 0.340% p99 9.042 p99.9 12.835
R3 B off music+share all-cpus r2: threads 20 frames 169104 | median 6.313 p99 13.645 p99.9 21.844 max 36.90 ms | >1.2x 33.75% >1.5x 10.599% >2x 2.002% | fastest 5.716
R3 B off music+share all-cpus r2: same-core 127881 >1.2x 1.96% >1.5x 0.314% >2x 0.097% | moved 41223 (24.38%) | pcores[0..11] 97880 >1.2x 1.34% >1.5x 0.075% >2x 0.020% p99 6.966 p99.9 8.247
R3 B closed all-cpus r2: threads 20 frames 172751 | median 6.274 p99 9.938 p99.9 13.981 max 103.82 ms | >1.2x 38.81% >1.5x 31.713% >2x 0.487% | fastest 5.325
R3 B closed all-cpus r2: same-core 143697 >1.2x 4.15% >1.5x 0.090% >2x 0.016% | moved 29054 (16.82%) | pcores[0..11] 106443 >1.2x 2.87% >1.5x 0.048% >2x 0.016% p99 6.849 p99.9 7.789
R3 B dpdf2 normal music+share all-cpus r3: threads 20 frames 162154 | median 6.621 p99 12.880 p99.9 17.901 max 39.20 ms | >1.2x 44.13% >1.5x 19.160% >2x 1.980% | fastest 5.716
R3 B dpdf2 normal music+share all-cpus r3: same-core 119246 >1.2x 5.80% >1.5x 1.781% >2x 0.496% | moved 42908 (26.46%) | pcores[0..11] 85931 >1.2x 6.15% >1.5x 2.269% >2x 0.659% p99 9.714 p99.9 16.272
R3 B dpdf2 above music+share all-cpus r3: threads 20 frames 162821 | median 6.603 p99 12.606 p99.9 17.980 max 40.68 ms | >1.2x 45.02% >1.5x 16.638% >2x 1.735% | fastest 5.716
R3 B dpdf2 above music+share all-cpus r3: same-core 114927 >1.2x 5.01% >1.5x 1.614% >2x 0.463% | moved 47894 (29.42%) | pcores[0..11] 78589 >1.2x 5.51% >1.5x 2.157% >2x 0.651% p99 9.655 p99.9 16.315
```

PresentMon on CS2 (C):

```
r3-test (lowest, full screen, before 960x540): frames 2669 | avg 267.3 fps, 1% low 150.1 fps | median 3.60 p99 6.39 p99.9 6.92 max 7.1 ms | cpuBusy 0.96 gpuBusy 3.74 ms
r3-closed-r1: frames 25988 | avg 288.8 fps, 1% low 106.0 fps | median 2.71 p99 8.99 p99.9 10.03 max 11.7 ms | >1.5x median 30.09% >2x 9.820%
r3-off-r1: frames 25145 | avg 279.4 fps, 1% low 99.6 fps | median 2.75 p99 9.37 p99.9 10.80 max 22.6 ms | >1.5x median 31.91% >2x 10.161%
r3-off-r1b: frames 26605 | avg 295.7 fps, 1% low 106.5 fps | median 2.63 p99 8.90 p99.9 10.05 max 11.3 ms | >1.5x median 30.60% >2x 9.198%
r3-dpdf2-r1: frames 25357 | avg 281.8 fps, 1% low 100.0 fps | median 2.76 p99 9.38 p99.9 10.74 max 12.0 ms | >1.5x median 31.83% >2x 9.240%
r3-dpdf2-r2: frames 24990 | avg 277.7 fps, 1% low 100.3 fps | median 2.78 p99 9.32 p99.9 10.52 max 22.2 ms | >1.5x median 31.56% >2x 10.116%
r3-off-r2: frames 25354 | avg 281.7 fps, 1% low 98.9 fps | median 2.70 p99 9.41 p99.9 10.85 max 21.3 ms | >1.5x median 32.57% >2x 10.117%
r3-closed-r2: frames 24919 | avg 276.9 fps, 1% low 48.8 fps | median 2.72 p99 9.45 p99.9 25.19 max 33.1 ms | >1.5x median 30.19% >2x 10.454%
r3-closed-r3: frames 25536 | avg 283.8 fps, 1% low 105.7 fps | median 2.81 p99 9.05 p99.9 9.94 max 18.9 ms | >1.5x median 28.11% >2x 9.575%
```

Rift's log, filtered to the noise filter:

```
16:07:36.910Z rust_lib_rift::dpdfnet::handoff: DPDFNet's thread at normal priority (RIFT_DPDFNET_PRIORITY)
16:07:36.936Z rust_lib_rift::dpdfnet: DPDFNet loaded
16:17:11.942Z dart: Noise filter: 750 frames, worst 3.7 ms, 0 over 5 ms, 0 over 10 ms
16:19:17.453Z dart: DPDFNet: 237 frames late, sent unfiltered
16:19:17.453Z dart: Noise filter: 10031 frames, worst 8.0 ms, 443 over 5 ms, 0 over 10 ms
16:19:38.005Z rust_lib_rift::dpdfnet::handoff: DPDFNet's thread at above normal priority (RIFT_DPDFNET_PRIORITY)
16:21:39.082Z dart: Noise filter: 10609 frames, worst 5.7 ms, 4 over 5 ms, 0 over 10 ms
16:23:40.122Z dart: Noise filter: 9670 frames, worst 5.8 ms, 9 over 5 ms, 0 over 10 ms
16:23:57.852Z rust_lib_rift::dpdfnet::handoff: DPDFNet's thread at normal priority (RIFT_DPDFNET_PRIORITY)
16:25:49.190Z dart: DPDFNet: 172 frames late, sent unfiltered
16:25:49.191Z dart: Noise filter: 9640 frames, worst 8.4 ms, 282 over 5 ms, 0 over 10 ms
16:27:49.255Z dart: Noise filter: 778 frames, worst 3.7 ms, 0 over 5 ms, 0 over 10 ms
16:37:34.003Z rust_lib_rift::dpdfnet::handoff: DPDFNet's thread at normal priority (RIFT_DPDFNET_PRIORITY)
16:39:11.944Z dart: DPDFNet: 248 frames late, sent unfiltered
16:39:11.944Z dart: Noise filter: 9791 frames, worst 8.1 ms, 438 over 5 ms, 0 over 10 ms
16:39:28.780Z rust_lib_rift::dpdfnet::handoff: DPDFNet's thread at above normal priority (RIFT_DPDFNET_PRIORITY)
16:41:27.696Z dart: Noise filter: 10412 frames, worst 4.3 ms, 0 over 5 ms, 0 over 10 ms
16:58:23.982Z dart: Noise filter: 731 frames, worst 3.7 ms, 0 over 5 ms, 0 over 10 ms
17:07:13.781Z dart: DPDFNet: 1 frames late, sent unfiltered
17:07:13.781Z dart: Noise filter: 50447 frames, worst 7.1 ms, 461 over 5 ms, 0 over 10 ms
17:09:48.190Z dart: Noise filter: 771 frames, worst 4.2 ms, 0 over 5 ms, 0 over 10 ms
17:16:53.056Z dart: Noise filter: 21233 frames, worst 6.7 ms, 179 over 5 ms, 0 over 10 ms
17:19:27.387Z dart: Noise filter: 12792 frames, worst 6.5 ms, 117 over 5 ms, 0 over 10 ms
17:22:04.058Z dart: Noise filter: 767 frames, worst 4.3 ms, 0 over 5 ms, 0 over 10 ms
```

From 17:07:13 on, C's (the 50,447 is the held call beside CS2; 21,233 and
12,792 are the two DPDFNet-2 captures; the short counts are the Off joins
before the filter was switched).

The two short counts (750, 778) are from the Off runs. Rift joined on the
saved DPDFNet choice and ran it for about 8 s before the filter was set Off,
all before the 15 s settle, so the Off measurements did not include it.
