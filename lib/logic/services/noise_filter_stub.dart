import '../../data/enums/noise_suppression.dart';

/// The web's [NoiseFilter]: the browser does its own processing, so only the
/// built-in suppressor is offered.
abstract final class NoiseFilter {
  static List<NoiseSuppression> get choices => const [
    NoiseSuppression.off,
    NoiseSuppression.standard,
  ];

  static bool usesBuiltIn(NoiseSuppression mode) =>
      mode != NoiseSuppression.off;

  static Future<void> use(NoiseSuppression mode) async {}

  static bool get canSetGain => false;

  static void setGain(double gain) {}

  static Future<void> forMicTest(
    NoiseSuppression mode, {
    required bool autoGain,
  }) async {}
}
