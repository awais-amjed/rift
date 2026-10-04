import 'package:flutter/foundation.dart';

import '../../data/classes/participant_setting.dart';

/// How loud other people's call audio may be turned up here, and what a track
/// is actually played at.
///
/// Beyond 100% only where libwebrtc plays the call — desktop and phones — as
/// its per-track gain goes up to ten times. The browser plays a call through
/// an audio element, which stops at 1.
abstract final class CallVolume {
  static double get max => kIsWeb ? 1.0 : 2.0;

  /// A person's (or a share's) own volume times the volume for every call,
  /// [output]; nothing while it is muted.
  static double of(ParticipantSetting setting, double output) =>
      setting.muted ? 0 : (setting.volume * output).clamp(0.0, max * max);
}
