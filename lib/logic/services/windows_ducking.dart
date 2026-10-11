import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../data/enums/ducking_preference.dart';
import '../../src/rust/api/ducking.dart' as rust;
import '../helper_methods.dart';

/// Windows' ducking, read from Rust (`rust/src/ducking.rs`): what the person
/// has Windows do to other apps during a call, and the moments it does it.
class WindowsDucking {
  const WindowsDucking._();

  static bool get supported => !kIsWeb && Platform.isWindows;

  /// The choice in Windows' Sound window, read fresh: the person changes it
  /// there, outside Rift. Null off Windows.
  static DuckingPreference? preference() {
    if (!supported) return null;
    try {
      final value = rust.duckingPreference();
      return value == null ? null : DuckingPreference.fromRegistry(value);
    } catch (e) {
      HelperMethods.printDebug('WindowsDucking: preference – $e');
      return null;
    }
  }

  /// Each time Windows lowers other apps or lets them back up. Empty off
  /// Windows.
  static Stream<rust.DuckingEvent> events() =>
      supported ? rust.duckingEvents() : const Stream.empty();
}
