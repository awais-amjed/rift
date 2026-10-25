# Rift performance kit

**Round 3 (after Oct 25 2026): read `ROUND3.md` for what to run** (and
`ROUND2.md`, which it builds on). This branch has since taken in `dev`, so the
branch description under *Why* below is round 1's; the tools, ground rules and
setup still hold.

For a Claude session on one of the user's own machines. It measures what Rift
costs a game running beside it, and whether this branch's change made that
cost go away. Read all of this before starting. **The user is at the computer
and does every step in Rift's UI and in the game.** You run the tools, tell
the user exactly what to click and when, and write up the results.

## Why

Two friends reported their games stuttering while they were in a Rift voice
call on Windows (CS2, AMD PCs; bug reports 40442f44 and 691a2ade, Oct 24
2026). Since 1.5.1, Rift's default noise filter has been DPDFNet, a neural
model. It ran on libwebrtc's microphone capture thread. On Windows that thread
is `THREAD_PRIORITY_TIME_CRITICAL` and registered with MMCSS as "Pro Audio",
so it pre-empts a game's threads. Each 10 ms audio frame took 2 to 8 ms of
model work at that priority. RNNoise, the previous default, takes about a
tenth of that.

This branch (`perf-testing`) is `dev` plus the fix, unreleased:

- **`50ca1c77`** stops pinning the audio thread to P-cores.
- **`1878ef67`** runs DPDFNet on its own thread, `rift-dpdfnet`, at
  `THREAD_PRIORITY_BELOW_NORMAL` (`rust/src/dpdfnet/handoff.rs`). The capture
  thread hands each frame over and waits at most 7 ms. A frame that is not
  back in time goes out **unfiltered**, so the game wins when the CPU is full.
- **`f18f082a`** makes DPDFNet-2, the small model, the default.

The *old* build is any released Rift up to 1.5.2-beta.4: the model runs on
the capture thread, pinned to P-cores where the CPU has them.

### What a Windows VM already showed (Oct 25)

2 vCPUs, no GPU. The old build there was `50ca1c77`. The stand-in game (`gameloop`) ran on every CPU, with
DPDFNet-2. The figure is the % of game frames more than 1.2× slower than the
fastest frame:

| Condition | Slow frames | p99 |
|---|---|---|
| Rift closed | 1.2% | 5.9 ms |
| Old build, filter Off | 17.7% | 25.3 ms |
| Old build, DPDFNet-2 | 59–61% | 29.8 ms |
| New build, filter Off | 17.3% | 23.3 ms |
| New build, DPDFNet-2 | 18–20% | 24.6 ms |

The price: with every CPU taken, 16,625 of 22,773 voice frames went out
unfiltered. With one CPU left free, it was 18%.

Rift in a call with the filter **Off** cost 25% of a core in the VM. About 17%
of that was the VM drawing Rift's window in software (WARP), because the VM
has no GPU. Rift draws about 2 frames a second in a call (the call timer and
the 1 s connection-quality poll), and still does while minimised. The rest
was the Opus encoder (about 3%), libwebrtc's capture and render threads (1–1.6%
each) and the network thread (under 1%). **A VM cannot give the real numbers.
That is what these machines are for.**

## Questions to answer

1. On real hardware, how much CPU does Rift use, and on which threads? Answer
   for four states: idle (not in a call); in a call with the filter Off; in a
   call with RNNoise; in a call with DPDFNet-2.
2. Does the old build make a game stutter in a call with DPDFNet-2, and does
   this branch stop it? First with the stand-in game, then with CS2.
3. How many voice frames does the new build send unfiltered while a game runs?
   This is the cost of the fix.
4. How many frames a second does Rift draw in a call, on the page and when
   minimised (Windows)?

## Ground rules

- **Never print secrets.** That means tokens, passwords, keys, invite codes and
  the clipboard. Rift's log is redacted, but still read it only through a
  `grep`/`Select-String` filter for the lines you need. Never print it whole.
- **Ask before installing anything.** That includes PresentMon, MangoHud and
  packages. Give the user the exact command.
- **Don't change app code on this branch** unless the user asks. If you find
  something worth fixing, describe it and propose the change.
- **Kill only processes you started,** and kill them by PID. Never close the
  user's game or other apps.
- **Commit and push only when the user says so.** Results go in
  `scripts/perf/results/` (below).
- **Only one Rift at a time.** The old and new builds share the same profile
  and settings, so close one before starting the other. If "Open Rift when your
  computer starts" is on, the installed build starts at sign-in. On Windows,
  that locks the exe for builds.
- **In a call, be unmuted with push-to-talk off.** Muting closes the mic, and
  with it the filter, so the call would measure nothing. The user can stay
  alone in a voice channel: their microphone is still captured, filtered,
  encoded and sent. Note in the results whether anyone else was in the call.

## Setup

### Build the tools

The kit is its own Cargo crate. It is not part of the app.

```
cd scripts/perf
cargo build --release
```

This gives you `target/release/gameloop` and `target/release/threadtop`
(`.exe` on Windows):

- **`gameloop calibrate`** prints the spin count for a frame of about 5 ms on
  this CPU. Use that number as SPINS in every run on this machine.
- **`gameloop run SECONDS SPINS LABEL [THREADS]`** is the stand-in game. It
  runs one thread per logical CPU by default. It prints the median, p99,
  p99.9 and max frame time, and the % of frames over 1.2×, 1.5× and 2× the
  fastest frame. Each line is also appended to `results.txt` in the current
  folder.
- **`threadtop riftchat SECONDS`** prints each Rift thread's CPU as % of one
  core, its context switches per second, its priority (Windows) or nice and
  policy (Linux), and its name. On Windows it also shows the module the thread
  started in.
- **`threadtop sample riftchat SECONDS`** (Windows only) suspends the busy
  threads about every 2 ms and counts which module each was in. Use it only if
  a thread's CPU needs explaining.
- **`presents.ps1 -Seconds 10`** (Windows, in an elevated PowerShell) counts
  DXGI Present calls per process, which is frames drawn.

### The new build (this branch)

- **Windows:** use `flutter build windows --release`. It needs Flutter,
  Rust, and Visual Studio's C++ workload with ATL. The exe is
  `build\windows\x64\runner\Release\RiftChat.exe`. Don't use
  `scripts\build_windows.ps1` for this: without MSYS2 it throws at the end
  over `rift_ffenc.dll`, which only matters for screen-share encoding. Expect
  the CMake warning about MSYS2.
- **Linux:** use `flutter build linux --release`. It needs clang 21 or newer
  and the packages in README.md's *Linux build dependencies*. The binary is
  `build/linux/x64/release/bundle/riftchat`.
- **Always a release build.** A debug build runs the Dart side much slower,
  and the CPU numbers would be meaningless.

### The old build

Ask the user which Rift is installed, and its version. They can find it in
Settings, or on the installer or AppImage name. Any version up to
1.5.2-beta.4 is the old behaviour. If none is installed, build `50ca1c77` in
a separate worktree: `git worktree add ../rift-old 50ca1c77`. That build has
the model on the capture thread without the P-core pinning. Say in the
results which one you used.

### The machine

Before measuring:

- Plug the laptop in to power.
- Use the same power mode for every run.
- Close what the user is happy to close: browsers, launchers, overlays.
- Keep everything the same between runs.
- Record the CPU model, its cores and threads, the RAM, the GPU, the OS and
  build, and the power mode.

## The tests

Run every gameloop condition **twice**, in an order such as A B C D D C B A.
That way, warming up or throttling does not favour one build. Use 60 s per
run. Between conditions, let the machine settle for 15 s.

Where to find the filter setting: Settings → **Voice & audio** → **Noise
suppression** (Off / Standard / RNNoise / DPDFNet). With DPDFNet selected,
choose **DPDFNet-2** in the size choice below it. A change applies at once, in
a call too.

### 1. Rift's own cost (both builds)

Leave the stand-in game off. For each state, run `threadtop riftchat 30` with
Rift on the Settings page:

- Not in a call.
- In a call, filter Off.
- In a call, RNNoise.
- In a call, DPDFNet-2.
- In a call, DPDFNet-8. New build only, if time allows.

On Windows, also run `presents.ps1 -Seconds 10` in a call twice: once with Rift
on the Settings page, and once with it minimised.

What to look for:

- In the **old** build, DPDFNet's cost shows on the capture thread. That
  thread has a high priority: 15 is TIME_CRITICAL, and the MMCSS boost may
  show higher.
- In the **new** build, the capture thread should drop to a few %, and a
  thread named `rift-dpdfnet` should carry the model. On Windows that thread
  should show priority −1.
- On Linux, libwebrtc's audio thread is an ordinary one: policy `other`,
  nice 0. So the old and new builds should differ less there.

### 2. The stand-in game

Run `gameloop calibrate` once, then for each condition:

```
gameloop run 60 <SPINS> "<build> <filter> all-cpus"
```

The conditions are:

- Rift closed.
- Old build in a call, filter Off.
- Old build in a call, DPDFNet-2.
- New build in a call, filter Off.
- New build in a call, DPDFNet-2.

While each in-call run is going, run `threadtop riftchat 30` alongside it, so
you can see whether `rift-dpdfnet` starved. Then repeat the in-call DPDFNet-2
conditions with **two logical CPUs left free** (THREADS = logical CPUs − 2).
A real game rarely takes every core.

After each in-call condition, the user leaves the call. When a call ends,
Rift logs how many frames the model was late with:

- Windows: `Select-String -Path (Get-ChildItem "$env:LOCALAPPDATA\com.codingfries\rift\logs\rift-*.log" | Sort-Object LastWriteTime | Select-Object -Last 1).FullName -Pattern 'DPDFNet' | Select-Object -Last 5`
- Linux: `grep -h DPDFNet "$(ls -t ~/.local/share/com.codingfries.rift/logs/rift-*.log | head -1)" | tail -5`

The lines are:

- `DPDFNet: N frames late, sent unfiltered` (new build only). Divide N by
  100 × the call's length in seconds to get the share of unfiltered frames.
- `DPDFNet: too slow here for DPDFNet-8, ran DPDFNet-2`.

### 3. A real game (CS2, if the user has it)

To measure CS2's frame times:

- **Windows:** use Intel PresentMon's command-line build, from GitHub
  releases. Ask the user before downloading it. For example:
  `PresentMon-<ver>-x64.exe --process_name cs2.exe --output_file cs2-<label>.csv --timed 90 --terminate_after_timed`.
  Read the header before computing anything: 2.x names the frame-time column
  `FrameTime` or `MsBetweenPresents`, depending on its options.
- **Linux:** use MangoHud's logging (`mangohud %command%` in Steam's launch
  options, `log_duration=90,autostart_log=1`). Ask before installing it.

The run has to repeat exactly between conditions. The best choice is a
workshop FPS-benchmark map. Otherwise, use the same offline map with bots,
standing still in the same spot. Use the same five conditions as test 2,
twice each if the user has the patience.

From each capture, report:

- the average fps;
- the 1% low;
- the p99 frame time;
- the share of frames more than 1.5× the median.

### 4. Optional: DPDFNet-8 beside the game (new build)

Does the large model now fall back to DPDFNet-2 under load, as it should, and
how many frames go out unfiltered?

## Results

Write `scripts/perf/results/<machine>-<YYYY-MM-DD>.md`, for example
`laptop-windows-2026-10-26.md` or `amd-linux-2026-10-26.md`. It holds:

1. The machine details from *The machine* above, and which old build you used.
2. Test 1: a table per build, with the top threads (CPU %, switches/s,
   priority, name) for each state, and the frames/s.
3. Tests 2 and 3: one row per run, with the condition, slow-frame %, p99 and
   max (or fps, 1% low and p99 for the game), and the unfiltered-frame count
   from the log.
4. A short plain-language conclusion. Does the fix remove the stutter here? What
   does it cost in unfiltered voice? What does Rift cost with the filter Off? And
   is anything left that looks worth fixing?

Copy the raw `results.txt` lines into an appendix. Then tell the user the
conclusion in a few lines. They will bring the file back to the session that
wrote the fix.
