import 'package:flutter/services.dart';

import '../helper_methods.dart';

/// What an Android phone's screen can do. The native half is `ScreenRates.kt`.
class PhoneScreen {
  const PhoneScreen._();

  static const _channel = MethodChannel('rift/screen_rates');

  /// Assumed where the screen cannot be asked: what every phone can do.
  static const _unknownRate = 60.0;

  /// The fastest the screen can run, in Hz.
  static Future<double> topRefreshRate() async {
    try {
      final rate = await _channel.invokeMethod<double>('top') ?? _unknownRate;
      HelperMethods.printDebug('[LiveKit] Phone screen up to $rate Hz');
      return rate;
    } catch (e) {
      HelperMethods.printDebug('[LiveKit] Phone screen rate unknown: $e');
      return _unknownRate;
    }
  }
}
