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

  static void use(NoiseSuppression mode) {}
}
