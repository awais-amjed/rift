import 'dart:math' as math;

/// Converts between raw microphone levels and the 0–1 position the settings
/// UI draws on.
///
/// The gate compares its threshold directly against the analyser's normalised
/// band peak, and real audio only occupies the bottom of that 0–1 range: room
/// noise sits near 0.03, and speech around 0.07–0.25 depending on how loudly
/// someone talks. A slider mapped straight onto 0–1 therefore spends most of
/// its travel above any human voice — every position past roughly a quarter
/// means "mute me", which is not a control, it is a trapdoor.
///
/// So the slider's travel is squeezed into [maxThreshold] and curved, giving
/// most of the movement to the quiet end where the decisions actually happen.
/// The meter is drawn through the same transform, so the level bar and the
/// threshold marker stay comparable: a voice that lands on the marker is a
/// voice that opens the gate.
class MicLevelScale {
  const MicLevelScale._();

  /// The loudest the gate may be set to demand.
  ///
  /// Comfortably above the ~0.25 that a raised voice reaches, so the top of
  /// the slider is still usable rather than decorative — but far below 1.0,
  /// which no microphone reaches in this unit.
  static const double maxThreshold = 0.3;

  /// Curve applied to the slider travel. Squared, so the first half of the
  /// slider covers the quietest ~25% of the range.
  static const double _curve = 2;

  /// Slider position (0–1) → the raw level the gate compares against.
  static double toLevel(double position) {
    final clamped = position.clamp(0.0, 1.0);
    return math.pow(clamped, _curve).toDouble() * maxThreshold;
  }

  /// Raw level → where it sits on the slider's travel (0–1).
  static double toPosition(double level) {
    if (level <= 0) return 0;
    final ratio = (level / maxThreshold).clamp(0.0, 1.0);
    return math.pow(ratio, 1 / _curve).toDouble();
  }

  /// Raw level → where it is drawn on the level meter (0–1).
  ///
  /// Linear, unlike the slider. The curve exists to give the *slider* fine
  /// control down at the quiet end; applying it to the meter as well pushes
  /// room noise a third of the way along the bar and normal speech into the
  /// amber and red segments, which is a display that lies about how loud you
  /// are. The meter only has to share the slider's **range**, not its curve.
  ///
  /// Levels past [maxThreshold] peg the meter rather than running off it.
  static double toMeter(double level) {
    if (level <= 0) return 0;
    return (level / maxThreshold).clamp(0.0, 1.0);
  }
}
