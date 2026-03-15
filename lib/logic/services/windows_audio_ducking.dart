import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:win32_registry/win32_registry.dart';

/// Manages Windows Audio Ducking via the registry.
///
/// Windows automatically lowers the volume of other applications when
/// communications activity is detected (e.g. a WebRTC/VoIP session).
/// Setting `UserDuckingPreference` to 3 tells Windows to "Do nothing".
class WindowsAudioDucking {
  static const _keyPath = r'Software\Microsoft\Multimedia\Audio';
  static const _valueName = 'UserDuckingPreference';

  /// Disables audio ducking by setting the registry preference to "Do nothing" (3).
  static void disable() {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      final key = Registry.openPath(
        RegistryHive.currentUser,
        path: _keyPath,
        desiredAccessRights: AccessRights.allAccess,
      );
      key.createValue(const RegistryValue.int32(_valueName, 3));
      key.close();
      debugPrint('[AudioDucking] Disabled (set to Do Nothing).');
    } catch (e) {
      debugPrint('[AudioDucking] Failed to disable: $e');
    }
  }

  /// Restores audio ducking to the Windows default (80% reduction = value 1).
  static void restore() {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      final key = Registry.openPath(
        RegistryHive.currentUser,
        path: _keyPath,
        desiredAccessRights: AccessRights.allAccess,
      );
      key.createValue(const RegistryValue.int32(_valueName, 1));
      key.close();
      debugPrint('[AudioDucking] Restored to default (80% reduction).');
    } catch (e) {
      debugPrint('[AudioDucking] Failed to restore: $e');
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
