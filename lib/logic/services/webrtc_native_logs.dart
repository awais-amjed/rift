import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:logger/logger.dart';

/// Pipes libwebrtc's own logging into the Flutter console.
///
/// The audio device module is the only part of the stack that knows why a
/// playout device did or did not open, and it says so through WebRTC's native
/// logger rather than through anything the plugin hands back: selecting an
/// output that cannot be opened still succeeds at the Dart end and simply goes
/// quiet. flutter_webrtc forwards those lines over its event channel once a
/// severity has been set, which makes this the only way to see them.
class WebrtcNativeLogs {
  const WebrtcNativeLogs._();

  static bool _enabled = false;

  /// Substrings that mark a line as being about audio devices.
  ///
  /// "verbose" covers the whole of WebRTC, most of which is per-packet noise,
  /// so anything that isn't about opening, closing or choosing a device is
  /// dropped before it reaches the console.
  static const List<String> _audioMarkers = [
    'AudioDeviceWindowsCore',
    'AudioDeviceModule',
    'audio_device',
    'Playout',
    'playout',
    'Recording',
    'recording',
    'IAudioClient',
    'AUDCLNT',
    'IMMDevice',
    'endpoint',
    'CoreAudio',
    'render device',
    'capture device',
  ];

  /// Debug builds only: this is a diagnostic tap, not something a release
  /// build should be paying an event-channel round trip for.
  static void enable() {
    if (!kDebugMode || _enabled) return;
    _enabled = true;
    rtc.Helper.setLogger(
      Logger(
        filter: ProductionFilter(),
        printer: _AudioDeviceOnlyPrinter(),
        output: _DebugPrintOutput(),
        level: Level.all,
      ),
      'verbose',
    );
  }

  static bool _isAboutAudioDevices(String line) =>
      _audioMarkers.any(line.contains);
}

/// Keeps only the audio-device lines. Returning an empty list drops the event.
class _AudioDeviceOnlyPrinter extends LogPrinter {
  @override
  List<String> log(LogEvent event) {
    final line = event.message.toString().trimRight();
    if (line.isEmpty) return const [];
    if (!WebrtcNativeLogs._isAboutAudioDevices(line)) return const [];
    return ['[webrtc] $line'];
  }
}

class _DebugPrintOutput extends LogOutput {
  @override
  void output(OutputEvent event) {
    for (final line in event.lines) {
      debugPrint(line);
    }
  }
}
