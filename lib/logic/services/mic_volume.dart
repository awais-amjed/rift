import 'call_volume.dart';
import 'noise_filter.dart';

/// How loud this device's microphone is sent: the Mic volume in Voice &
/// Audio. It is applied in the runner's filter, after the noise model, so it
/// exists where the filter does — Windows and Linux (see [NoiseFilter]).
abstract final class MicVolume {
  /// The top of the slider, as it reads: 200%.
  static const double max = 2.0;

  /// Whether this device can set it at all.
  static bool get adjustable => NoiseFilter.canSetGain;

  /// What the slider sends at, from what it reads: the same curve as the
  /// call volume ([CallVolume.outputGain]), so 100% is the microphone as it
  /// is and the slider's 200% is four times as loud. A quiet microphone is
  /// often 12 dB short, and a limiter keeps the loud end from cutting off.
  static double gain(double shown) => CallVolume.outputGain(shown);

  /// Puts [shown] on the microphone.
  static void apply(double shown) =>
      NoiseFilter.setGain(gain(shown.clamp(0.0, max)));
}
