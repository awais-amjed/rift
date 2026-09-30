import 'dart:io';

import 'package:flutter/foundation.dart';

import '../helper_methods.dart';

/// Opens Windows' own Sound window on its Communications tab — where the
/// user decides what Windows does to other apps' volume during a call.
///
/// Opened rather than set from here. The choice is stored per user in the
/// registry (`UserDuckingPreference`) and covers every app, and Windows does
/// not re-read it when a call starts: a value Rift wrote there changed nothing
/// until the next sign-in, while the same choice made in this window applies
/// at once (measured Sep 30 2026 on Windows 11 25H2). The switch that would
/// stop only Rift's call from lowering others, `IAudioClientDuckingControl`,
/// belongs to the capture stream inside libwebrtc and is out of reach.
///
/// `mmsys.cpl,,3` is the Sound control panel with its fourth tab —
/// Playback, Recording, Sounds, Communications — selected.
class WindowsSoundSettings {
  const WindowsSoundSettings._();

  static bool get canOpen => !kIsWeb && Platform.isWindows;

  static Future<void> openCommunicationsTab() async {
    try {
      await Process.start('control.exe', [
        'mmsys.cpl,,3',
      ], mode: ProcessStartMode.detached);
    } catch (e) {
      HelperMethods.printDebug(
        'WindowsSoundSettings: could not open the Sound window – $e',
      );
    }
  }
}
