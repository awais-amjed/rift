import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../src/rust/api/audio_endpoints.dart';
import '../helper_methods.dart';

/// Re-exported so callers reading formats through [AudioDevices] don't have to
/// reach into the generated bridge themselves.
export '../../src/rust/api/audio_endpoints.dart' show AudioEndpoint;

/// Reading and applying the saved audio device choices.
///
/// This used to live entirely inside the settings section, which meant a saved
/// device was applied when that screen was opened and at no other time: start
/// the app, join a call, never visit settings, and the choice was ignored.
/// [applySaved] now runs as part of joining a channel, which is both the first
/// moment it can work and every moment it needs to.
class AudioDevices {
  const AudioDevices._();

  static Future<List<MediaDevice>> inputs() =>
      Hardware.instance.enumerateDevices(type: 'audioinput');

  static Future<List<MediaDevice>> outputs() =>
      Hardware.instance.enumerateDevices(type: 'audiooutput');

  /// Both lists, which are empty unless a call is up.
  ///
  /// Audio devices are not enumerated by the operating system here but by
  /// WebRTC's audio device module: the plugin walks `RecordingDevices()` and
  /// `PlayoutDevices()` and reports what they return. Both refuse to answer
  /// until that module has been initialised, and return -1, which the plugin
  /// loops zero times over — so outside a call both lists come back empty and
  /// the settings screen says "No devices found" until a channel is joined.
  /// Only the camera shows, because video devices are enumerated separately.
  ///
  /// Two ways of bringing that module up from here have been tried and
  /// measured, and neither does: `getUserMedia` builds an audio source straight
  /// off the peer connection factory without touching it, and a peer connection
  /// carrying a receive-only audio transceiver in its local description does not
  /// reach it either. Listing devices outside a call needs to come from Windows
  /// instead — `listInputEndpoints` and `listOutputEndpoints` already can —
  /// but applying a choice still goes through the device module, so the two
  /// halves have to be solved together rather than by priming.
  static Future<({List<MediaDevice> inputs, List<MediaDevice> outputs})>
  load() async => (inputs: await inputs(), outputs: await outputs());

  /// Windows' own account of each render endpoint, keyed by device id.
  ///
  /// Empty off Windows and when the probe fails, which callers must read as
  /// "nothing known" rather than "nothing supported". Never asked on the web,
  /// which has no Rust library to ask: the call throws there, and took the
  /// whole device list down with it.
  static Future<Map<String, AudioEndpoint>> outputEndpointFormats() async =>
      kIsWeb ? const {} : _byDeviceId(await listOutputEndpoints());

  /// Windows' own account of each capture endpoint. See
  /// [outputEndpointFormats].
  static Future<Map<String, AudioEndpoint>> inputEndpointFormats() async =>
      kIsWeb ? const {} : _byDeviceId(await listInputEndpoints());

  static Map<String, AudioEndpoint> _byDeviceId(List<AudioEndpoint> endpoints) {
    return {for (final endpoint in endpoints) endpoint.deviceId: endpoint};
  }

  /// The format of an endpoint the device module cannot open, or null when it
  /// can — or when nothing is known about it.
  ///
  /// Selecting an endpoint that fails to open does not just lose that device:
  /// playout stops and is not started again, and the device module will only
  /// restart it on a later switch if it was still playing, which it isn't. So
  /// the call stays silent through every subsequent choice until it is
  /// rejoined. That is worth refusing a device over.
  ///
  /// Whether it can is Windows' answer to the module's own question
  /// ([AudioEndpoint.opens]), not a guess from the mix format: the module asks
  /// for 16-bit PCM in mono or stereo at six rates, and inside Rift's process
  /// a stereo laptop speaker reported an 8 channel mix while the module played
  /// through it, so the guess refused a working default device. The mix format
  /// is still what the message names.
  static String? unusableFormat(AudioEndpoint? endpoint) {
    if (endpoint == null || endpoint.opens) return null;
    return '${endpoint.channels} channel ${_kHz(endpoint.sampleRate)}';
  }

  /// The format that stops [device] being opened, or null when it can be — or
  /// when Windows tells us nothing about it. Reads the endpoint list itself,
  /// for callers that don't already hold one.
  static Future<String?> unusableFormatFor(
    MediaDevice device, {
    required bool isInput,
  }) async {
    final formats = isInput
        ? await inputEndpointFormats()
        : await outputEndpointFormats();
    return unusableFormat(formats[device.deviceId]);
  }

  static String _kHz(int sampleRate) {
    final kHz = sampleRate / 1000;
    final text = kHz == kHz.roundToDouble()
        ? kHz.toStringAsFixed(0)
        : kHz.toStringAsFixed(1);
    return '$text kHz';
  }

  /// The device WebRTC lists that Windows uses by default, or null when that
  /// cannot be known: off Windows, outside a call (when WebRTC lists nothing),
  /// or with no default device at all.
  ///
  /// "System default" needs this because the plugin can only point WebRTC's
  /// device module at a device in its list. Leaving the choice alone does not
  /// mean the default: the module keeps whatever it was last given for the
  /// life of the process, so picking a device and then "System default" left
  /// the call on the device just un-picked.
  static Future<MediaDevice?> systemDefault({required bool isInput}) async {
    if (kIsWeb) return null;
    final id = isInput
        ? await defaultInputEndpoint()
        : await defaultOutputEndpoint();
    if (id == null) return null;
    return byId(isInput ? await inputs() : await outputs(), id);
  }

  /// The id a new mic track should name: the saved input, else Windows'
  /// default, else null — which leaves the device module where it is.
  ///
  /// For the mic test outside a call, where there is no [applySaved] result
  /// to read. WebRTC lists nothing then, so an id that cannot be matched just
  /// leaves the device alone, which is still better than the first one.
  static Future<String?> preferredInputId(String? savedId) async {
    if (savedId != null || kIsWeb) return savedId;
    return defaultInputEndpoint();
  }

  /// Applies the saved devices — or, where nothing is saved, Windows' default
  /// — ignoring ids that no longer enumerate, and reports what it moved: the
  /// input by id, since every mic track made afterwards has to name it.
  ///
  /// **Call this only once a call is up.** Everything here goes through the
  /// same device module [load] describes, so before a room is connected there
  /// is nothing to enumerate and nothing to select — this would run to
  /// completion having done nothing. It was called from app startup for
  /// exactly that reason once, on the argument that the choice should be in
  /// place "before any call can open a device", which is the one moment it
  /// cannot be.
  ///
  /// A saved id outlives the machine it was chosen on — headsets get
  /// unplugged, and Windows is free to renumber what is left — so an id that
  /// is no longer present is dropped rather than forced onto whatever now sits
  /// in its place.
  ///
  /// A device the device module cannot open is skipped here too, not only when
  /// picked by hand: applying one stops playout for the rest of the session,
  /// and a saved id is applied on every join, so the one place it must not
  /// happen unattended is this one. The device stays saved — its format may
  /// well be fixed by the time it is next read.
  ///
  /// The input has to be named again on every mic track because the plugin's
  /// `getUserMedia` resets the device module to the *first* listed input
  /// whenever a track is made without one. Selecting the device here alone
  /// therefore lasted only until the next mute, rejoin or rebuild — which is
  /// immediately, since the track a room raises on connect predates this.
  ///
  /// Throws if the platform refuses a device that does exist. Callers are
  /// expected to say so rather than swallow it: a failed switch is silent
  /// otherwise, and silence here sounds exactly like a dead output.
  static Future<({String? input, bool output})> applySaved({
    String? inputId,
    String? outputId,
  }) async {
    String? appliedInput;
    var appliedOutput = false;
    final input = inputId != null
        ? byId(await inputs(), inputId)
        : await systemDefault(isInput: true);
    if (input != null && await _isUsable(input, isInput: true)) {
      await Hardware.instance.selectAudioInput(input);
      appliedInput = input.deviceId;
    }
    final output = outputId != null
        ? byId(await outputs(), outputId)
        : await systemDefault(isInput: false);
    if (output != null && await _isUsable(output, isInput: false)) {
      await Hardware.instance.selectAudioOutput(output);
      appliedOutput = true;
    }
    return (input: appliedInput, output: appliedOutput);
  }

  static Future<bool> _isUsable(
    MediaDevice device, {
    required bool isInput,
  }) async {
    final format = await unusableFormatFor(device, isInput: isInput);
    if (format == null) return true;
    HelperMethods.printDebug(
      '[AudioDevices] not applying saved ${isInput ? 'input' : 'output'} '
      '"${labelOf(device)}": Windows runs it at $format',
    );
    return false;
  }

  /// The device with this id, or null.
  ///
  /// There is deliberately no "or the first one" fallback. That turned an id
  /// the list does not hold into a silent switch to an unrelated device, which
  /// is worse than doing nothing and much harder to notice.
  static MediaDevice? byId(List<MediaDevice> devices, String? deviceId) {
    if (deviceId == null) return null;
    return devices.cast<MediaDevice?>().firstWhere(
      (d) => d?.deviceId == deviceId,
      orElse: () => null,
    );
  }

  /// A device's name, or a stand-in. Labels come back empty when the platform
  /// has not granted microphone permission yet.
  static String labelOf(MediaDevice device) =>
      device.label.isEmpty ? 'Unknown' : device.label;
}
