import 'package:flutter/foundation.dart';

import '../../data/classes/participant_setting.dart';

/// How loud other people's call audio may be turned up here, and what a track
/// is actually played at.
///
/// Beyond 100% only where libwebrtc plays the call — desktop and phones — as
/// its per-track gain goes up to ten times. The browser plays a call through
/// an audio element, which stops at 1.
abstract final class CallVolume {
  /// The top of both sliders, as they read: 200%.
  static double get max => kIsWeb ? 1.0 : 2.0;

  /// What the call volume plays at, from what its slider reads.
  ///
  /// Up to 100% the two agree. Above it, each step on the slider is three:
  /// the slider's 200% plays at 400%. Calls were quiet beside everything else
  /// on the machine and 200% was not enough, but a longer scale would have
  /// crowded the useful half of the track. A person's own volume is not
  /// stretched: with both at the top a voice plays at 8×, inside libwebrtc's
  /// 10×.
  static double outputGain(double shown) =>
      shown <= 1 ? shown : 1 + (shown - 1) * 3;

  /// A person's (or a share's) own volume times the volume for every call,
  /// [output]; nothing while it is muted.
  static double of(ParticipantSetting setting, double output) => setting.muted
      ? 0
      : (setting.volume * outputGain(output)).clamp(0.0, max * outputGain(max));
}
