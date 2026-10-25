# Round 2: the fixes from round 1, on the laptop's Windows

For the Claude session on the Intel laptop's own Windows. Read `README.md` first,
for the tools, the ground rules and how round 1 ran, and then
`results/laptop-windows-2026-10-25.md`: this round checks the fixes for what that
file found, against its numbers. The ground rules there still hold (never print a
secret, read Rift's log only through a filter, ask before installing anything,
one Rift at a time, kill only your own processes by PID, commit and push only
when the user says so). As in round 1, you may drive Rift and the game yourself
once the user says so.

## What changed since round 1

This branch is now `dev` merged in, with the kit on top. Against the released
1.5.2-beta.4 it has:

| Round 1 found | The change | Commit |
|---|---|---|
| While anyone talked, Rift redrew 66–147 frames a second, even minimised or behind a game (`SpeakingRing`'s pulse) | The ring fades in and out, then holds still while someone talks | `9dd05628` |
| Joining while someone shared received their stream unwatched (15–33 Mbit/s, decoder 9–17% of a core) until leaving, and Watch showed only the avatar | The unwatched stream is dropped after joining, asked again once the connection is up | `d6ff8902` |
| `VideoDecoderQueue` at priority 15 (time-critical) | Decoding and drawing a received video at 1 (above normal); Opus encoding (`AudioEncoderQueue`) up from 0 to 2 (highest) | `31cd5810` |
| Main thread and a Flutter thread waking 2,500–5,500 times a second at rest | Dart on its own UI thread: on the main thread, Flutter's timer kept firing once it had fired. In a VM this took the main thread from 760–1,110 wake-ups a second to about 140 | `de081299` |
| — | **DPDFNet is back on the capture thread** (the model's own thread was reverted, `56a501c2`), with DPDFNet-2 still the default | |

The DPDFNet thread was reverted because it sends most of the voice
unfiltered when the computer is busy (96% beside the stand-in game), and the
redrawing cost a game more than the model did. **Part F decides whether it comes
back.**

Not changed, so expect these to look the same as in round 1: watching a stream
still draws 94–156 frames a second when minimised or covered, and DPDFNet-8 still
falls back to DPDFNet-2 on this laptop.

## Builds

- **New:** this branch. Build the Rust library first. Round 1 found that
  cargokit otherwise copies whatever stale `rust_lib_rift.dll` is in
  `rust/target`, and this branch's Rust has changed since:

  ```
  cd rust
  cargo build -p rust_lib_rift --release --target x86_64-pc-windows-msvc
  cd ..
  flutter build windows --release
  ```

  Check the build carries the changes before measuring anything:

  ```
  $r = "build\windows\x64\runner\Release"
  $has = { param($f, $s) [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes("$r\$f")).Contains($s) }
  & $has rust_lib_rift.dll "DPDFNet's thread stopped"            # must be False (the reverted thread)
  & $has flutter_webrtc_plugin.dll "WebRTC-MediaTaskQueuePriorities"  # must be True
  ```

- **Old:** the installed 1.5.2-beta.4, as in round 1. Keep "Open Rift when your
  computer starts" off for the session.

Round 1's numbers are the "before" for every part. Run the old build again only
where a part says so, to check that today's machine matches that day's.

## Measuring: what round 1 learned

- **The game in front, Rift behind it,** or Windows confines the game to the
  efficiency cores. Use `gameloop2` if it is still on this machine (round 1 kept it
  outside the repository; it judges each frame against its own CPU's fastest and
  opts out of power throttling). If it is gone, rebuild it from its description in
  round 1's results before running any game test, and say so.
- **`presents.ps1` reports nothing here.** Count Present events from the trace it
  leaves instead: event IDs 42 and 55, PIDs parsed as hex.
- **Rift's sound and network:** round 1's `measure.ps1` (threads, GPU engine,
  bytes received, memory, frames) may also still be here. If not, bytes received
  per second come from `Get-Counter '\Network Interface(*)\Bytes Received/sec'`.
- **The same call as round 1:** the user's account alone in a voice channel on
  their own server, unmuted, push to talk off, the filter as each part says. A
  sharer (Gracie, from the user's other PC, CS2 at 1080p60 with sound) and the
  DJ Riff music bot when a part asks for them. The user starts and stops those.
- Two runs per game condition, in an order such as A B B A, 60 s each, 15 s apart.

## A. At rest: the wake-ups

`threadtop riftchat 30`, new build, Rift in front on Settings, the mouse still:

1. Not in a call.
2. In a call, alone, filter Off.

Report the main thread's and the Dart UI thread's switches a second (round 1:
2,500–5,500 each, both at 1.5–3% of a core). Then the old build, the same two
readings, one each, so this machine today is compared with itself.

**Pass:** the new build's main thread wakes a few hundred times a second or
less, where the old one wakes thousands.

## B. Dart on its own thread: what could have broken

Dart now runs on a thread of its own instead of the window's. Nothing in Rift
should mind, but these are the places that talk to Windows. Check each one by
hand, new build:

- [ ] **Push to talk, keyboard key:** set one in Settings → Voice & audio, join a
  call, hold it with Rift in front, then with another window in front. The mic
  opens and closes each time. Rift's log shows `Push-to-talk: pressed` and
  `released` lines (read them with a filter).
- [ ] **Push to talk, mouse side button**, the same way.
- [ ] **Mute and deafen keys** in the window, after clicking somewhere in it first.
- [ ] **Share picker:** start a share; screens and windows are listed with
  thumbnails; share a window, see it in the call, stop.
- [ ] **Mic test** (Settings → Voice & audio, Test mic): you hear yourself back.
- [ ] **File dialogs:** attach a file in a chat; change your avatar (pick, crop,
  save).
- [ ] **Paste:** copy a picture, Ctrl+V in the composer; it attaches.
- [ ] **The window:** drag by the title bar, resize from an edge, maximise and
  restore, minimise and bring back.
- [ ] **A notification:** a mention from the user's other PC while Rift is
  behind another window shows a Windows notification, and clicking it opens the
  channel.

Note anything slow, missing, or different from beta.4.

## C. Someone talking: the speaking ring

New build, in the call, the music bot playing (it counts as someone talking
without stopping). Frames drawn over 10 s and `threadtop riftchat 30`:

| | Round 1 (beta.4) |
|---|---|
| Call page in front | 66 frames/s, 92–104% of a core |
| Minimised | 68–74/s, 108–111% |
| Behind another window | 147/s, 134% |

Then `gameloop2` on all CPUs, game in front, music playing, no stream. Round 1:
5.35% slow, 1.31% over 1.5×, p99.9 on the performance cores 23.1 ms, Rift at
110% of a core. Rift closed was 1.35–1.41% and 0.07–0.10%.

**Pass:** a few frames a second at most while the music plays, and Rift's
cost close to a quiet call's (6–8% of a core). Also look at the ring itself: it
should fade in when the music starts, hold, and fade out when it stops.

## D. Joining while someone shares

Gracie shares first. Then, new build, join the call and do not press Watch. For
30 s read bytes received and `threadtop` (`VideoDecoderQueue`). Leave and join
again **five times**: on Linux it failed one join in four before the fix.

Then:

1. Press Watch: the picture shows, not the avatar.
2. Press Stop watching: bytes received fall back to tens of kbit/s.

Round 1 (beta.4): 15–33 Mbit/s received unwatched, decoder at 9–17%, and Watch
showed only the avatar, in both tries.

**Pass:** tens of kbit/s and no decoder work on every join, the picture on Watch,
and back down on Stop.

## E. Watching a stream beside a game: the decoder's priority

New build, watching Gracie's share.

1. `threadtop`: `VideoDecoderQueue` and `IncomingVideoStreamQueue` read 1,
   `AudioEncoderQueue` reads 2. On beta.4 they were 15, 15 and 0.
2. `gameloop2` on all CPUs, game in front, Rift behind it watching, with the
   music on as in round 1. Round 1: 11.91% slow, 2.79% over 1.5×, 1.23% over
   2×, p99.9 on the performance cores 18.0 ms, Rift at 144%. Run it once more
   with the music off, so the stream's own cost shows without the ring.
3. **Does the stream suffer?** This is the cost of the lower priority. Put Rift
   in front, watching, with the stats overlay on, and run `gameloop2` on all CPUs
   behind it for 60 s. The user watches for stutter, and you note the overlay's
   FPS and Dropped/s, before and during the run. Do the same on beta.4 for
   comparison. A stream at 1080p60 should hold close to 60 with Dropped near 0.

**Pass:** the game's slow frames close to a quiet call's, and the stream
not visibly worse than on beta.4 when the CPU is full.

## F. DPDFNet on the capture thread: does the thread come back?

This is the decision the round is for. The friends who reported stutter played
CS2 on AMD PCs. Round 1's CS2 was GPU-bound at about 300 fps and showed nothing,
so this time make it **CPU-bound**: the lowest graphics settings and a
resolution low enough that the GPU waits on the CPU, frame rate uncapped
(`fps_max 0`). The same spot as round 1 (de_dust2, offline, bots kicked,
`setpos`/`setang` bound to a key, unbound after). PresentMon 2.6.0 as before.
First check it is CPU-bound: CS2's CPU time a frame should be close to its
frame time, and the GPU's well below.

New build, conditions, two runs each:

1. Rift closed.
2. In the call, filter Off.
3. In the call, DPDFNet-2.
4. In the call, DPDFNet-2, with the music playing (a call where people talk).

Read `threadtop` alongside the in-call runs (the capture thread's CPU and
priority). From each capture, report average fps, the 1% low, p99, p99.9, max,
and the share over 1.5× the median. If time allows, the same four with
`gameloop2` on all CPUs.

**The answer to give:** does DPDFNet-2 (3) cost CS2 more than the gap between the
two Rift-closed runs, compared with the filter Off (2)? If it doesn't, the thread
stays out. If it does, say how much, and the thread move comes back.

## Results

Write `results/laptop-windows-<date>.md` the way round 1's file is written: the
machine (and whether anything changed since round 1), each part's table with
round 1's numbers beside it, B's checklist ticked with notes, F's answer, and
anything new worth fixing. Raw `gameloop2` and PresentMon summary lines go in an
appendix. Then tell the user the outcome in a few lines. They bring the file back
to the session that made the fixes.
