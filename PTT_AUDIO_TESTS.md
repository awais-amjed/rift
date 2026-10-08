# Push-to-talk audio test on Windows

A brief for a Claude session on a Windows PC. People say push-to-talk cuts off
the start of what they say. You measure how much on Windows with the build
before the fix, **stop and ask the user**, then build the fix and measure again.

## What is known (Linux, Oct 8–9 2026)

- On every release Rift mutes the mic track, and libwebrtc then stops the
  microphone itself (its log: `MuteStream: ADM:1`, then `StopRecording`). Every
  press starts the device again. LiveKit's `stopAudioCaptureOnMute: false`
  does not change that, because the stop is libwebrtc's, not LiveKit's.
- On Linux that restart costs little. The audio missing after a press was a
  median of 34 ms, and a spoken sentence started on the press arrived whole
  with every noise filter.
- Windows is the suspect. There, with echo cancellation on, the mic records
  through Windows' own echo canceller, which starts with the device. The
  `_CaptureReviveMixin` doc in `lib/logic/cubits/livekit/` says how fragile
  that is. Nobody has measured it.

## The fix (the last commit on this branch)

Under push-to-talk the mic track is never muted, so the device keeps running.
With the key up, Rift's own processing of the mic, after the noise model and
the mic volume, replaces what it hears with silence:

- `native/noise_filter` (`rift_noise_filter_set_silenced`)
- `NoiseFilter.setSilenced`, called from `_applyMicrophoneTransmission` in
  `livekit_cubit.dart` before any track is touched

LiveKit then sees a live track, so the client publishes a `ptt_idle`
participant attribute, and other clients show the mic as muted
(`VoiceAttributes.isMicOpen`). Muting by hand, deafening and moderator mutes
still mute the track and release the device. On Linux the fix measured 0–2 ms
missing at the press, the device never stopped, and nothing was heard between
presses.

## Rules

- **Ask the user before:**
  - installing anything (Python packages, the virtual cable driver)
  - anything needing administrator rights
  - changing system settings
  - moving from one phase to the next
- Upload nothing anywhere, apart from pushing this branch at the end, once the
  user says so.
- Write your results to `PTT_AUDIO_RESULTS.md` at the root of this repository.
  Commit and push it only when the user agrees. Never add attribution lines
  (Co-Authored-By, Claude-Session or similar) to a commit.
- If the fix's build lets **anything** be heard while the key is up, stop at
  once and tell the user: that is an open mic.

## The rig

Two copies of Rift on this PC, both in one voice channel:

- **talker**: push-to-talk on F8, its microphone set to a virtual cable
- **listener**: mic muted, output to the speakers or headphones

`scripts/ptt_audio/ptt_audio.py` plays a test signal into the cable, presses F8
through `SendInput`, records the listener's output by WASAPI loopback, and
works out what was lost. Run it with `--help` for what it prints. Its analysis
was checked on Linux recordings; its Windows half (playback, loopback
recording, `SendInput`) has never run, so fix it if it needs fixing, and say
what you changed.

### Setup (ask the user for each step)

1. **Tools.** Flutter and Visual Studio for `flutter build windows --release`.
   Python 3.10+ with `pip install numpy soundcard`.
2. **Virtual cable.** VB-Audio Virtual Cable (vb-audio.com/Cable), free. It
   installs a driver, needs administrator rights and may want a restart.
   "CABLE Input" is where the script plays; "CABLE Output" is the talker's
   microphone.
3. **Server.** Ask the user which Rift server and voice channel to use. Both
   profiles must be members of it. Do not create accounts on the production
   central directory.
4. **Two profiles.** Start each copy from its own PowerShell, so the variable
   applies to that process only:
   ```powershell
   $env:RIFT_PROFILE = 'ptt_talker'; & .\build\windows\x64\runner\Release\rift.exe
   $env:RIFT_PROFILE = 'ptt_listener'; & .\build\windows\x64\runner\Release\rift.exe
   ```
   Each profile has its own storage and its own single-instance lock.
5. **Talker settings** (Settings → Voice & audio):
   - Input device: "CABLE Output".
   - Output device: the default, never "CABLE Input", which would loop back
     into its own microphone.
   - Echo cancellation on: that is the slow path under test.
   - Sounds → "Push to talk" off, so its own tone stays out of the recording.
   - Push-to-talk on, key F8. Microphone unmuted.
6. **Listener.** Mute its mic **before** it joins, then join. Its output is
   the default device, the one you record.
7. Run `python scripts/ptt_audio/ptt_audio.py devices`. Pick the cable's
   playback name and the listener's output device. Check the level with one
   short run: the steady part should be well above 0.01 RMS. The analysis
   treats anything below that as silence.
8. Keep the talker's window **behind** another window during runs, as in a
   game. Push-to-talk on Windows is a low-level keyboard hook, so it works in
   the background.

Quit both copies before every rebuild.

## Phase 1: the build before the fix

Build the commit titled "Add the Windows push-to-talk audio test brief"
(`git log --oneline`, the one before the tip). Use a plain
`flutter build windows --release`; the installer script is not needed.

Run:

1. **Sweep, noise suppression Off** (the noise models eat a steady tone):
   `run before_sweep --mode sweep --n 12 --hold 1.5 --play "CABLE Input" --record "<listener output>"`
2. **Speech, noise suppression RNNoise:**
   `run before_speech --mode speech --n 8 --hold 2.2 ...`
3. **Sweep with echo cancellation off**, if time allows. It tells whether
   Windows' echo canceller is what costs the time.
4. **Note the Windows microphone-in-use icon** in the taskbar during a run:
   does it come and go with each press?

Write the numbers to `PTT_AUDIO_RESULTS.md`, show them to the user, and
**ask before going on**.

## Phase 2: the fix

Build the branch tip. Same runs as Phase 1, then:

1. **Nothing heard outside a hold**, in every run (the script prints it).
2. **The mic-in-use icon** stays on for the whole call. It goes off when the
   talker mutes by hand, deafens or leaves.
3. **The listener's roster:** the talker shows as muted while F8 is up and
   unmuted while it is held, in the sidebar row and on the video tile.
4. **Mute, unmute, deafen and undeafen** the talker, then sweep again: no
   leak, and the press still opens at once.
5. **The capture revive.** Windows only: when the last remote audio leaves, the
   capture can die and Rift republishes the mic. Have the listener leave, wait
   5 s, rejoin, then sweep: the talker must still be heard, with no leak.
6. Switch noise suppression mid-call, then sweep.
7. Change the input device and back mid-call, then sweep.

Write it all to `PTT_AUDIO_RESULTS.md` and ask the user before committing and
pushing.

## Reading the numbers

| Line | Good | Means |
|---|---|---|
| `cut` | near 0, and below the before build | ms of speech lost at the press. The audio stack adds a constant few tens of ms, so compare runs on this PC |
| `tail` | about 200 | Rift keeps the mic open 200 ms after release on purpose |
| `ramp` | under ~30 | ms for the voice to reach full level |
| `first100` / `first300` | near 0 dB | the opening of a sentence against the rest of it; a cut opening reads well below 0 |
| `HEARD OUTSIDE A HOLD` | never | sound with the key up: stop and report |

Include the machine (Windows version, CPU, audio devices) in the results.
