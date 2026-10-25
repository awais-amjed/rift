# Round 3: DPDFNet on its own thread, at normal priority

For the Claude session on the Intel laptop's own Windows. Read `README.md` for
the tools and ground rules, then `ROUND2.md` for how round 2 measured, and
`results/laptop-windows-2026-10-25-round2.md` for its numbers: this round
measures against them. The ground rules still hold (never print a secret, read
Rift's log only through a filter, ask before installing anything, one Rift at
a time, kill only your own processes by PID, commit and push only when the
user says so). You may drive Rift and the game yourself once the user says so.

## What changed since round 2

This branch is `dev` merged in again, with the kit on top.

| Round 2 found | The change | Commit |
|---|---|---|
| DPDFNet-2 on the capture thread (time-critical, priority 18, about 32% of a core) took the game's frames over 1.5× from 0.16–0.31% to 0.83–0.92%, p99.9 from 8.2 to 12.2 ms | The model runs on its own thread, `rift-dpdfnet`, at **normal** priority. Round 1 had it below normal, where it starved beside the game and sent 96% of the voice unfiltered. A frame not back within 7 ms still goes out unfiltered | `545c546d` |
| On Windows the noise models and Mic volume were gone (Dart now starts before the window puts the filter on) | Rift waits for the filter, and Settings says "Starting noise suppression…" meanwhile | `ab8d48ad` |

**This branch only** (not on `dev`): `RIFT_DPDFNET_PRIORITY=above_normal` in
Rift's environment puts the model's thread one step higher. It is a backup:
if normal still starves, this round measures one step up without a new build.

## Build

As in round 2. Build the Rust library first, or cargokit ships a stale one:

```
cd rust
cargo build -p rust_lib_rift --release --target x86_64-pc-windows-msvc
cd ..
flutter build windows --release
```

Check the build carries the changes:

```
$r = "build\windows\x64\runner\Release"
$has = { param($f, $s) [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes("$r\$f")).Contains($s) }
& $has rust_lib_rift.dll "DPDFNet's thread stopped"   # must be True (the model's own thread)
& $has rust_lib_rift.dll "RIFT_DPDFNET_PRIORITY"      # must be True (this branch's switch)
```

Every launch's log says which priority the thread got:
`DPDFNet's thread at normal priority` or `... above normal priority`. It
appears when DPDFNet loads.

## A. The noise models are back (a few minutes)

New build, Settings → Voice & audio:

- [ ] Noise suppression offers Off, Standard, RNNoise and DPDFNet, and Mic
  volume shows.
- [ ] Pick DPDFNet, quit Rift, start it again. Settings opens on DPDFNet, and
  the log shows `DPDFNet loaded`. There must be no line `Noise filter: the
  runner has none`.
- [ ] Did "Starting noise suppression…" show at all, and for how long? Open
  Settings straight after launch to catch it. A short flash or nothing is
  right. More than a second is worth reporting.

## B. Beside the stand-in game: is the voice still filtered?

`gameloop2` on all CPUs, game in front, the call as in round 2: the user alone
in a voice channel, DJ Riff's music on, and Gracie's unwatched share (or none,
the same in every run). Use DPDFNet-2, 60 s per run, 15 s apart.

Conditions, in this order:

1. Rift closed.
2. In the call, filter Off.
3. DPDFNet-2, normal priority.
4. DPDFNet-2, above normal (quit Rift, start it with `$env:RIFT_DPDFNET_PRIORITY = "above_normal"`, rejoin).
5. Above normal again.
6. Normal again (restart Rift without the variable).
7. Off again.
8. Closed again.

**Leave the call after each DPDFNet run, then join again for the next.** The
count of late frames is written to the log when a call ends:
`DPDFNet: N frames late, sent unfiltered`. If that line is missing, no frame
was late. Beside it is `Noise filter: N frames, worst …`. Report N against
the frame count. A 60 s run is about 6,000 frames.

Run `threadtop riftchat` alongside each in-call run. It shows the CPU and
priority of `rift-dpdfnet` and of the capture thread (`webrtc_audio_module`, or
whatever round 2 called it). Normal reads 8 and above normal 10. A thread
waking from a wait may read a little higher for a moment.

Report it as round 2's part F table, with three columns added: the model
thread's CPU and priority, and the share of frames unfiltered.

## C. CS2, CPU-bound

This is the run still owed from round 2. **Ask the user first:** CS2 on this
machine takes the Steam session from the other PC. Set it up as ROUND2.md part
F says: lowest settings, a resolution low enough to be CPU-bound, `fps_max
0`, de_dust2 offline, bots kicked, the same `setpos`/`setang`, PresentMon
2.6.0. Check it really is CPU-bound first.

Conditions, two runs each, in an A B B A order: Rift closed, filter Off,
DPDFNet-2 at normal. Add above normal only if B showed normal starving the
model and above normal not. Leave and rejoin after each DPDFNet run, as in B.
From each capture report average fps, the 1% low, p99, p99.9, max and the
share over 1.5× the median, plus the unfiltered count.

## The answer to give

For each priority:

1. **Does the game suffer?** Compare DPDFNet-2 with the filter Off, against
   the gap between the two Rift-closed runs (round 2's capture-thread figures:
   0.83–0.92% over 1.5×, p99.9 12.2 ms).
2. **Is the voice still filtered?** Give the share of frames sent unfiltered
   (round 1, below normal: 96%).

Normal is the answer if the game stays near Off and only a few percent of
frames go out unfiltered. If normal starves the model but above normal does
not, and the game still stays near Off, above normal is the answer. If
neither works, give the numbers and say so.

## Results

Write `results/laptop-windows-<date>-round3.md` the way round 2's file is
written:

- the machine, and whether anything changed;
- A's checklist;
- B's and C's tables, with round 2's numbers beside them;
- the answer;
- anything new worth fixing;
- raw lines in an appendix.

Then tell the user the outcome in a few lines. They bring the file back to the
session that made the fixes.
