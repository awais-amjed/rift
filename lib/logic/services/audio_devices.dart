import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../src/rust/api/audio_endpoints.dart';

/// Re-exported so callers reading formats through [AudioDevices] don't have to
/// reach into the generated bridge themselves.
export '../../src/rust/api/audio_endpoints.dart' show AudioEndpoint;

/// Reading and applying the saved audio device choices.
///
/// This used to live entirely inside the settings section, which meant a saved
/// device was applied when that screen was opened and at no other time: start
/// the app, join a call, never visit settings, and the choice was ignored.
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

  /// The sample rates WebRTC's Windows device module will offer an endpoint.
  ///
  /// It asks `IAudioClient::Initialize` for 16-bit PCM in mono or stereo at
  /// each of these in turn and gives up when none is accepted, so this list
  /// and a channel count of one or two are between them the whole of what it
  /// can open.
  static const Set<int> _deviceModuleSampleRates = {
    48000,
    44100,
    16000,
    96000,
    32000,
    8000,
  };

  /// Windows' own account of each render endpoint, keyed by device id.
  ///
  /// Empty off Windows and when the probe fails, which callers must read as
  /// "nothing known" rather than "nothing supported".
  static Future<Map<String, AudioEndpoint>> outputEndpointFormats() async =>
      _byDeviceId(await listOutputEndpoints());

  /// Windows' own account of each capture endpoint. See
  /// [outputEndpointFormats].
  static Future<Map<String, AudioEndpoint>> inputEndpointFormats() async =>
      _byDeviceId(await listInputEndpoints());

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
  static String? unusableFormat(AudioEndpoint? endpoint) {
    if (endpoint == null) return null;
    final usable =
        endpoint.channels >= 1 &&
        endpoint.channels <= 2 &&
        _deviceModuleSampleRates.contains(endpoint.sampleRate);
    if (usable) return null;
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

  /// Applies the saved devices, ignoring ids that no longer enumerate.
  ///
  /// A saved id outlives the machine it was chosen on — headsets get
  /// unplugged, and Windows is free to renumber what is left — so an id that
  /// is no longer present is dropped rather than forced onto whatever now sits
  /// in its place. Note that "no longer present" also covers "nothing is
  /// present yet": see [load] on when the device module answers.
  ///
  /// A device the device module cannot open is skipped here too, not only when
  /// picked by hand: applying one stops playout for the rest of the session,
  /// and a saved id is applied on every launch, so the one place it must not
  /// happen unattended is this one. The device stays saved — its format may
  /// well be fixed by the time it is next read.
  ///
  /// Throws if the platform refuses a device that does exist. Callers are
  /// expected to say so rather than swallow it: a failed switch is silent
  /// otherwise, and silence here sounds exactly like a dead output.
  static Future<void> applySaved({String? inputId, String? outputId}) async {
    if (inputId != null) {
      final device = _find(await inputs(), inputId);
      if (device != null && await _isUsable(device, isInput: true)) {
        await Hardware.instance.selectAudioInput(device);
      }
    }
    if (outputId != null) {
      final device = _find(await outputs(), outputId);
      if (device != null && await _isUsable(device, isInput: false)) {
        await Hardware.instance.selectAudioOutput(device);
      }
    }
  }

  static Future<bool> _isUsable(
    MediaDevice device, {
    required bool isInput,
  }) async {
    final format = await unusableFormatFor(device, isInput: isInput);
    if (format == null) return true;
    debugPrint(
      '[AudioDevices] not applying saved ${isInput ? 'input' : 'output'} '
      '"${device.label}": Windows runs it at $format',
    );
    return false;
  }

  static MediaDevice? _find(List<MediaDevice> devices, String deviceId) =>
      devices.cast<MediaDevice?>().firstWhere(
        (d) => d?.deviceId == deviceId,
        orElse: () => null,
      );
}
