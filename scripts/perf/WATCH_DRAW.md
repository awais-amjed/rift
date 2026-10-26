# Watching a stream: why it costs a core, and the fix

For the Claude session on the Intel laptop's own Windows. This one is more
than a measurement: **you find the Windows-specific numbers, then fix the
problem on this branch, testing on Windows as you go.** When it's done, the
user switches back to Linux, and the Linux session checks the fix there and
moves it to `dev`.

Read `README.md` first for the tools (`threadtop`, `presents.ps1`,
`gameloop2`) and the ground rules. Then read `results/laptop-windows-2026-10-25.md`
(round 1, the *What a call costs* table) and
`results/laptop-windows-2026-10-25-round2.md` (part E). Your numbers will be
compared with theirs. In the app, read `AGENTS.md`, `CODE_STYLE.md`,
`BEST_PRACTICES.md` and `CALLS.md` before changing code.

## The branch

`watch-draw` is `dev` (at `a1cf63b1`, 1.5.2-beta.5 plus a release-script fix)
with the perf kit on top, the same way `perf-testing` was. **Keep kit commits
and fix commits separate.** Each fix commit touches only app code and its
docs, so the Linux session can move the fix commits to `dev` without the kit.

## The problem

Watching a 1080p60 stream costs Rift **132–145% of a core** on this laptop
(round 2, part E, with Rift maximised behind `gameloop2`). It costs a game
beside it about as much as Rift ever did: 2.6–3.4% of frames over 1.5×,
against about 0.1% with Rift closed. That's the CS2 stutter your friends
report. Round 2 split it as:
- Flutter's raster thread: 70–74%;
- the Intel driver: 20–22%;
- the decoder (`VideoDecoderQueue`): 21–30%.

So **the cost is the drawing, not the decoding.** Round 1 also found that
watching keeps drawing while Rift is **minimised (94 frames/s) or behind
another window (156/s)**. Those counts were taken while the old speaking ring
was also redrawing (fixed since). The stream's own rate should be about 60;
nobody has recounted it.

## Why, as worked out on Linux (Oct 26)

This comes from reading the source of flutter_webrtc and Flutter 3.47.7's
engine. The engine source is in the Flutter SDK checkout under
`engine/src/flutter`.

1. **Every decoded frame redraws the whole window.**
   - `third_party/flutter_webrtc/common/cpp/src/flutter_video_renderer.cc`
     `OnFrame` calls `MarkTextureFrameAvailable` for each frame.
   - The engine (`shell/common/shell.cc`,
     `OnPlatformViewMarkTextureFrameAvailable`) then calls
     `ScheduleFrame(false)`, which re-draws the last frame in full
     (`Animator::DrawLastLayerTrees`).
   - Dart doesn't run for it, so Dart's "app is hidden, don't draw" check
     never applies.
   - Neither desktop embedder supports drawing only what changed (no
     `populate_existing_damage`). `shell/platform/windows/compositor_opengl.cc`
     blits the whole frame to the window every time.
2. **Each frame is converted and uploaded on the CPU, on the raster thread.**
   - `CopyPixelBuffer` in `flutter_video_renderer.cc` converts the full
     1920×1080 I420 frame to RGBA (8 MB).
   - `shell/platform/windows/external_texture_pixelbuffer.cc` uploads it
     with `glTexImage2D` every frame.
3. **Windows only: every OpenGL call goes through ANGLE to Direct3D 11**
   (`shell/platform/windows/egl/manager.cc`). Impeller is the default
   renderer since 3.47, on its OpenGL ES backend, so ANGLE translates all of
   it on the CPU. That's the likely reason Windows' raster thread is about 3×
   Linux's.
4. **Windows only: nothing stops it when minimised or covered.**
   - Windows' frame timing is a timer (`FlutterWindowsEngine::FrameInterval`
     reads the refresh rate from `DwmGetCompositionTimingInfo`). Nothing
     waits on the window being visible.
   - On Linux, GTK stops ticking a minimised window, so it stops drawing
     there (measured below).
   - The engine does tell Dart about minimising:
     `windows_lifecycle_manager.cc` sends `AppLifecycleState.hidden` on
     `SIZE_MINIMIZED`. That is a hook a fix can use. **Check that Rift's
     Dart side actually receives it**: on Windows Rift runs Dart on its own
     thread (`windows/runner/main.cpp`).
5. **The glass blur over the stream is a small part.**
   - The name badge, quality badge, watchers and control bar are
     `BackdropFilter` blurs.
   - Over a watched stream they fade out when the mouse is still, and then
     cost nothing.
   - The small tiles beside a stream keep theirs on screen.

### Linux numbers, same laptop (Iris Xe), Oct 26

Two clients on the local stack. cara shared a 1080p60 test pattern on
NVENC; dave watched. The stats overlay read 1920×1080, 60 fps, 14.6 Mbps,
H264. Figures are dave's CPU in % of one core, over 15–20 s.

| Dave | Total | Raster | Main thread | Decoder |
|---|---|---|---|---|
| In the call, not watching | 9.9 | – | 2.3 | – |
| Watching, 960×1000 window, overlays faded | 65.2 | 23.2 | 13.2 | 15.6 |
| Watching, 640×500 window | 63.6 | 21.6 | 12.1 | 15.0 |
| Watching, overlays shown (mouse moving) | 75.9 | 26.3 | 17.9 | 16.4 |
| Same, throwaway build with every blur removed | 64.7 | 21.2 | 15.1 | 14.8 |
| Watching, but on the Settings page | 46.3 | 6.4 | 11.5 | 15.4 |
| Watching, minimised | 26.7 | 0.7 | – | 14.3 |

On Linux the main thread is also Dart's and GTK's, which show each frame.

What these readings say:
- **Converting and uploading each frame: about 15–17%.** That's the stream
  page against Settings. Window size barely matters.
- **Redrawing and showing the window at the video's rate, whatever is on
  it: about 15%.** Settings still redraws 60 times a second while a stream
  is watched.
- **Decoding: about 15%.**
- **The blur: about 10%, only while the overlays show.**

## Step 1: the Windows split (no code change)

Ask the user to set up the call as in round 2: Gracie shares CS2 at 1080p60,
and you watch on this laptop. Rift is maximised, with the mouse off it. Build
this branch first (see *Build* below).

For each state, measure 30 s of `threadtop` and 10 s of `presents.ps1`
(frames drawn):

| | State |
|---|---|
| a | In the call, not watching |
| b | Watching, stream page in front |
| c | Watching, Settings page in front (the stream is still being received) |
| d | Watching, minimised |
| e | Watching, behind another maximised window |
| f | Watching, behind `gameloop2` (round 2's E2 setup), plus `gameloop2`'s numbers |

How to read the split:
- **b − c** is the convert-and-upload part plus drawing the video.
- **c − a** is redrawing the window at the video's rate.
- **d and e** show how much of that still runs when nobody can see it.

Also note the frames drawn in b: about 60 means the redraws follow the
stream. Much more means something else also redraws.

Write this to `results/laptop-windows-<date>-watch-draw.md`, commit it (kit
commit), then **show the user the split before changing code**.

## Step 2: the fix

What the Linux session recommends: **stop drawing the stream when nobody can
see it, on Windows, and stop downloading the picture too, so decoding stops
as well.** Keep the stream's sound. For the CS2 case, Rift behind a game,
that should remove most of the ~140%. Agree the approach with the user
before building it, and change it if step 1 says otherwise.

What "nobody can see it" covers:
1. **Rift is minimised.** Flutter sends `AppLifecycleState.hidden` (see
   above).
2. **Rift is covered**, e.g. by a fullscreen or borderless game on the same
   monitor. Flutter gives no signal for this, so the runner has to work it
   out and tell Dart over a platform channel. Anything that must run on the
   window's thread goes through a platform channel, as the push-to-talk keys
   do (`AGENTS.md`, *On Windows, Dart is not on the main thread*).
   - Chromium does this properly (`NativeWindowOcclusionTrackerWin`).
   - A simpler first cut: the foreground window isn't Rift and covers Rift's
     whole monitor. Hook `EVENT_SYSTEM_FOREGROUND` and location changes with
     `SetWinEventHook`, or check on a timer.
   - **Rift on a second monitor beside the game must keep drawing.** That's
     a real way to watch while playing. A partly covered Rift keeps drawing
     too.
3. Lower priority: **the stream isn't on Rift's screen**, e.g. Settings or a
   chat is open while still watching. Same pause, same resume.

How to pause, as far as the Linux session knows. Check it in the code before
relying on it.
- The watched share's **video** publication can be disabled
  (`RemoteTrackPublication.disable()` in `livekit_client`, vendored in
  `third_party/livekit_client`). The server then stops sending it, so
  nothing is decoded or drawn. `enable()` resumes and asks for a key frame.
  Measure how long the picture takes to come back after restore. It should
  feel instant, about a second at most.
- **Never touch the share's audio this way.** Remote audio is held, never
  unsubscribed (`AGENTS.md`, `_AudioReceptionMixin`, `hearsRemoteAudio`).
  A picture may be unsubscribed or disabled; audio may not.
- Keep the viewer's `watching` attribute while paused. They're still
  watching, just not looking. Check what the sharer's dynacast does when
  every viewer pauses, and that it recovers.
- Where watching is decided: `lib/logic/cubits/livekit/`
  (`livekit_screenshare.dart` and its neighbours). Keep it in one place,
  with its state in the cubit, not in a widget (`BEST_PRACTICES.md`).

**Not in this task** (say so if you find they're needed):
- GPU decoding into a D3D texture (`ExternalTextureD3d`), which would remove
  the CPU convert-and-upload. It's a big job, next on the list.
- Replacing the blur.
- H264 High and the automatic codec switch-down. That waits until this is
  done.

### Testing while you work

After each change, rebuild and rerun the relevant states from step 1:
- d, e and f must drop to about the "not watching" cost, apart from the
  stream's sound;
- b must not change;
- the picture must come back on restore or uncover, with the sound
  continuous throughout.

Also check:
- Rift on the second monitor beside a fullscreen window keeps drawing (if
  the user has a second monitor here; otherwise say it wasn't checked);
- Alt+Tab in and out of a fullscreen game several times; the picture comes
  back every time;
- minimise and restore while the share stops, or the sharer leaves;
- `flutter analyze` and `flutter test` clean.

### Docs, in the same commit as the code

- `CALLS.md`: how watching behaves when Rift is hidden, with the Windows
  numbers and how they were measured.
- `TESTING.md`: the rows you verified, and what wasn't checked.
- `AGENTS.md`, if the fix sets a rule later code must follow (for example,
  "a stream is paused while Rift can't be seen; don't …").

## Build

As in round 3. Build the Rust library first, then the app:

```
cd rust
cargo build -p rust_lib_rift --release --target x86_64-pc-windows-msvc
cd ..
flutter build windows --release
```

A Dart-only change still needs `flutter build windows --release`, but not
the Rust step.

## Handing back

When the fix works:
1. Commit the fix commits and the results file on `watch-draw`.
2. Tell the user it's ready to push. Push only when they say so.
3. Finish `results/laptop-windows-<date>-watch-draw.md` with:
   - the before and after tables;
   - what you changed, with the commit hashes;
   - what you couldn't check;
   - anything the Linux session should look at (Linux has its own minimise
     behaviour, and the Settings-page case is shared).

The user then switches back to Linux, where that session tests the fix on
Linux, moves the fix commits to `dev`, and releases when the user says so.

## Ground rules (from the user, on top of README.md's)

- **Git:**
  - Commit verified work on this branch without asking. Never push unless
    the user says so.
  - Stage specific paths, never `git add -A`.
  - Write commit messages to a file and use `git commit -F`.
  - **No `Co-Authored-By` or other attribution lines in commits, ever.**
  - Never `git stash`. Never `-c user.email`.
  - Never commit `.idea/`, `SHARE_DIALOG_PLAN.md` or `out.zip`.
  - Keep `dart format` and `cargo fmt` changes, even in files you didn't
    touch.
- **Never print a secret:** tokens, keys, the call key, `.env` values.
  Read Rift's log only through a filter (`Select-String -NotMatch
  'key|token|secret|password'`).
- **Your machine:**
  - Ask before installing anything.
  - Kill only processes you started, by PID.
  - Don't touch the user's servers, the Mac mini or any deploy.
- **Talking to the user:**
  - Plain, short answers, with one recommendation rather than a list of
    options.
  - For a UI choice, build one and show it.
  - Keep this branch's results file up to date as you go, so a context reset
    loses nothing.
