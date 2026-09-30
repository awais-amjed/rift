import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:win32_registry/win32_registry.dart';
import '../../helper_methods.dart';

/// Windows' "when Windows detects communications activity" preference —
/// the Communications tab of the Sound panel — switched from Rift's settings.
///
/// Windows lowers other apps' volume when a call starts. The one control a
/// calling app has over that from the outside is this per-user preference,
/// `UserDuckingPreference`: 3 is "Do nothing", 1 (and no value at all) is the
/// default 80% reduction. It is the user's setting and it covers every app,
/// so Rift only ever writes it when the user flips Rift's own toggle, and
/// turning the toggle off puts back what was there before rather than a
/// default. Writing it at every launch, as this used to, overwrote whatever
/// the user had picked in the Sound panel each time Rift started.
///
/// Windows does not re-read the value when a call starts. The Sound panel
/// applies it at once; a write from here waits until Windows next loads it,
/// which a sign-in appears to do (not proven). Verified on Windows 11
/// 25H2, Sep 30 2026: the toggle's write left a call ducking exactly as
/// before; the same value set in the Sound panel took effect immediately.
///
/// What would stop Rift's own call from ducking anything, without touching a
/// system-wide setting, is `IAudioClientDuckingControl` on the capture
/// stream's `IAudioClient` — which libwebrtc owns, out of reach from here.
class WindowsAudioDucking {
  static const _keyPath = r'Software\Microsoft\Multimedia\Audio';
  static const _valueName = 'UserDuckingPreference';
  static const _doNothing = 3;

  /// Where the value from before Rift changed it is kept, so it can be put
  /// back. Rift's own key: nothing of ours goes under Microsoft's.
  static const _savedPath = r'Software\Rift\AudioDucking';
  static const _savedName = 'PreviousUserDuckingPreference';

  /// Stands for "there was no value", which Windows reads as its default.
  /// Not a preference Windows defines, so it cannot be mistaken for one.
  static const _unset = 0xFFFFFFFF;

  /// Sets "Do nothing", keeping the preference it replaces.
  static void disable() => _guard('disable', () {
    final audio = CURRENT_USER.create(_keyPath);
    try {
      final current = audio.getInt(_valueName);
      // Already "Do nothing" means either the user chose it or an earlier
      // disable did; in the second case the saved value is the real one,
      // and saving 3 over it would make "Do nothing" permanent.
      if (current != _doNothing || _readSaved() == null) {
        _save(current ?? _unset);
      }
      audio.setValue(_valueName, const RegistryValue.dword(_doNothing));
    } finally {
      audio.close();
    }
    HelperMethods.printDebug('[AudioDucking] Set to "Do nothing".');
  });

  /// Puts back the preference [disable] replaced.
  ///
  /// With nothing saved — the toggle was turned on by a version that did not
  /// keep it — the value is removed, which is Windows' own default rather
  /// than a guess at one.
  static void restore() => _guard('restore', () {
    final saved = _readSaved();
    final audio = CURRENT_USER.create(_keyPath);
    try {
      if (saved == null || saved == _unset) {
        if (audio.getInt(_valueName) != null) audio.removeValue(_valueName);
      } else {
        audio.setValue(_valueName, RegistryValue.dword(saved));
      }
    } finally {
      audio.close();
    }
    _clearSaved();
    HelperMethods.printDebug(
      '[AudioDucking] Restored the preference from before Rift changed it.',
    );
  });

  /// Applies the toggle: [disable] sets "Do nothing", otherwise the user's
  /// own preference comes back.
  static void apply({required bool disable}) {
    if (disable) {
      WindowsAudioDucking.disable();
    } else {
      restore();
    }
  }

  static int? _readSaved() {
    final key = CURRENT_USER.create(_savedPath);
    try {
      return key.getInt(_savedName);
    } finally {
      key.close();
    }
  }

  static void _save(int preference) {
    final key = CURRENT_USER.create(_savedPath);
    try {
      key.setValue(_savedName, RegistryValue.dword(preference));
    } finally {
      key.close();
    }
  }

  static void _clearSaved() {
    final key = CURRENT_USER.create(_savedPath);
    try {
      if (key.getInt(_savedName) != null) key.removeValue(_savedName);
    } finally {
      key.close();
    }
  }

  static void _guard(String verb, void Function() body) {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      body();
    } catch (e) {
      HelperMethods.printDebug('[AudioDucking] Failed to $verb: $e');
    }
  }
}
