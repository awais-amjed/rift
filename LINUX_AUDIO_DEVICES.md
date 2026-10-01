# Audio devices on Linux — what is left

On Windows (Oct 2026) the input and output pickers were fixed and can be used
outside a call. Part of that work is shared and should already help on Linux,
and part is Windows-only and still has to be done on Linux. This file says which
is which, what to check first, and how to do the Linux half. Nothing here has
been run on Linux yet.

## What already applies to Linux (untested there)

These are in shared Dart code, gated on "desktop", not on Windows:

- **Every mic track names the chosen input.** flutter_webrtc's desktop
  `getUserMedia` (`common/cpp/src/flutter_media_stream.cc`, `GetUserAudio`)
  sets the recording device to **index 0** whenever a track is made without a
  device id. `common/cpp` is also its Linux implementation, so Linux had the
  same bug as Windows (Bug 13: the call ignores the picked mic). The fix passes
  the device id in `AudioCaptureOptions` (`_buildAudioCaptureOptions` in
  `livekit_cubit.dart`), and the rebuild after a pick puts the new options on
  the existing track (`_refreshMicrophoneCapture`).
- **Picks made outside a call are saved and applied on join**
  (`AudioDevices.applySaved`, called from `_applySavedAudioDevices` on every
  join).
- **"System default" is applied, not just forgotten**
  (`AudioDevices.systemDefault`). On Linux this currently does nothing, because
  the lookup it relies on returns nothing there (below).

## What is Windows-only and needs a Linux version

`rust/src/api/audio_endpoints.rs` answers only on Windows; on Linux every
function returns an empty list or `None`:

| Function | Used for | Linux today |
|---|---|---|
| `list_input_endpoints` / `list_output_endpoints` | the pickers outside a call (`AudioDevices.choices`), the "unsupported format" guard | empty → "No devices found" outside a call |
| `default_input_endpoint` / `default_output_endpoint` | "System default" (`AudioDevices.systemDefault`) | `None` → "System default" is saved but not applied |

The Dart side needs no change: `choices()` falls back to these lists whenever
WebRTC lists nothing, and `systemDefault()` matches the default id against
WebRTC's list. Once the Rust side answers on Linux, both work.

Not needed on Linux:

- **`_CaptureReviveMixin` (Bug 23)** is gated on
  `HostPlatform.recordsThroughOsEchoCanceller` (Windows). It works around
  Windows' built-in echo canceller, which the Linux device module does not use.
- **`AudioEndpoint.opens`** guards against Windows refusing a format. PulseAudio
  resamples and remixes, so on Linux report `opens: true`.

## Check first, before writing code

The whole thing rests on the ids lining up: the id Rust reports for a device has
to be the id WebRTC reports for the same device. flutter_webrtc builds a device's
id as `SanitizeDeviceIdFromAudioBuffers(name, guid)` — the **guid if WebRTC gives
one, otherwise the name**. On Windows the guid is the WASAPI endpoint id. On
Linux, from memory of WebRTC's PulseAudio module (verify this):

- the guid is left empty, so **the id is the device's display name** (the
  PulseAudio *description*, e.g. "Built-in Audio Analog Stereo");
- **index 0 is an extra "default" entry** carrying the default device's name, so
  the same id appears twice — once for "default", once for the real device;
- it may list **monitor sources** ("Monitor of …") as inputs.

How to check, in a call on the Linux build:

1. Print what WebRTC lists — `AudioDevices.inputs()` and `outputs()`: each
   `deviceId` and `label`. Compare with `pactl list short sources` / `sinks` and
   `pactl list sources | grep -E 'Name|Description'`.
2. Confirm Bug 13 was real on Linux before the fix, and is gone after it:
   pick a mic that is not the default mid-call, then `pactl list source-outputs`
   shows which source Rift is recording from (the Linux counterpart of the
   Windows session check used in testing). For the output, `pactl list
   sink-inputs`.
3. Try "System default" after picking another output in a call: does playout go
   back? (Expected not, until the Rust part below exists.)

If the ids are names: two devices with the same description would collide, and
the "default" entry duplicates a real one. Decide whether the picker should hide
the duplicate (match on label + skip WebRTC's index-0 entry) before going on.

## How to do the Linux half

All in Rust; the API shape does not change, so **no `flutter_rust_bridge_codegen`
run is needed** (it is only needed when a function or struct exposed to Dart
changes).

1. **Reuse the PulseAudio connection** in `rust/src/sharing/audio/pulse.rs`
   (it already lists sink inputs and monitors for Share sound, through
   `libpulse-binding`).
2. **List sinks and sources** with the introspector (`get_sink_info_list`,
   `get_source_info_list`). For each, build an `AudioEndpoint`:
   - `device_id`: **whatever WebRTC uses** as found above — most likely the
     `description`;
   - `name`: the `description`;
   - `channels` / `sample_rate`: from the sample spec (shown in the picker only
     when a device is refused, which on Linux it never is);
   - `opens: true`.
   - Skip monitor sources from the input list (`monitor_of_sink` set) if WebRTC
     does not offer them either.
3. **Defaults**: `get_server_info` gives `default_sink_name` and
   `default_source_name`; look those up in the lists and return the matching
   `device_id`.
4. Wire them into `rust/src/api/audio_endpoints.rs` under
   `#[cfg(target_os = "linux")]`, next to the Windows branches. Off both, keep
   returning empty / `None`.
5. Unit-test the mapping (description → id, monitor filtering, default lookup)
   with `cargo test`; the Windows probe has no tests to copy, but
   `sharing/audio` does.

## How to verify

On a Linux desktop with at least two inputs and two outputs (a USB headset, or a
null sink: `pactl load-module module-null-sink sink_name=test`):

- Settings → Voice & audio with no call: both pickers list the devices.
- Pick a non-default mic and output outside a call, join: `pactl list
  source-outputs` / `sink-inputs` show Rift on those devices.
- "System default" picked outside a call, then join: back on the defaults.
- In a call: pick another output, then "System default": playout returns to the
  default.
- Two clients, one leaves while the other is unmuted, then rejoins: the one who
  stayed is still heard (Bug 23 should not exist on Linux; confirm it).
- Update the rows in `TESTING.md` ("Picking the input and output device in a
  call…", "Choosing the input and output device outside a call") with what was
  driven on Linux.

## Related, still open on every platform

- The Settings mic test does nothing outside a call on Windows (it never starts
  recording without a call); check it on Linux.
- The device list does not refresh when a device is plugged in outside a call
  (WebRTC sends no change events then); reopening Settings re-reads it.
- macOS has neither the Rust device lookup nor any testing; the same plan would
  apply with Core Audio.
