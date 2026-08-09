import 'package:flutter/animation.dart';

/// The app's motion scale.
///
/// Durations live in `K` beside the geometry they move, because they are plain
/// numbers the data layer can hold. Curves are Flutter's, so they live here —
/// and they belong together anyway: two things moving over the same duration on
/// different curves still look like two separate animations.
class AppMotion {
  const AppMotion._();

  /// Panels opening and closing. Decelerating, so the panel arrives settled
  /// rather than stopping dead.
  static const Curve panel = Curves.easeOutCubic;
}
