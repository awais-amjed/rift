import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:win32_registry/win32_registry.dart';
import '../../helper_methods.dart';

/// Manages Windows Audio Ducking via the registry.
///
/// Windows automatically lowers the volume of other applications when
/// communications activity is detected (e.g. a WebRTC/VoIP session).
/// Setting `UserDuckingPreference` to 3 tells Windows to "Do nothing".
class WindowsAudioDucking {
  static const _keyPath = r'Software\Microsoft\Multimedia\Audio';
  static const _valueName = 'UserDuckingPreference';

  /// Disables audio ducking by setting the registry preference to "Do nothing" (3).
  static void disable() =>
      _write(3, 'Disabled (set to Do Nothing).', 'disable');

  /// Restores audio ducking to the Windows default (80% reduction = value 1).
  static void restore() =>
      _write(1, 'Restored to default (80% reduction).', 'restore');

  /// Writes the preference, which is the whole of both calls above.
  ///
  /// `CURRENT_USER.open` with an explicit config is win32_registry 3's
  /// replacement for `Registry.openPath`; the key is opened for everything
  /// rather than for writing alone because that is what shipped, and no
  /// machine here runs Windows to prove a narrower right is enough.
  static void _write(int preference, String outcome, String verb) {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      final key = CURRENT_USER.open(
        _keyPath,
        config: const RegistryOpenConfig(access: RegistryAccess.all),
      );
      key.setValue(_valueName, RegistryValue.dword(preference));
      key.close();
      HelperMethods.printDebug('[AudioDucking] $outcome');
    } catch (e) {
      HelperMethods.printDebug('[AudioDucking] Failed to $verb: $e');
    }
  }

  /// Applies the given preference: disables ducking if [disable] is true,
  /// otherwise restores the Windows default.
  static void apply({required bool disable}) {
    if (disable) {
      WindowsAudioDucking.disable();
    } else {
      restore();
    }
  }
}
