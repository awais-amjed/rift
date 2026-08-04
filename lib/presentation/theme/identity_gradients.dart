import 'package:flutter/material.dart';

/// A gradient standing in for one identity — a person or a server.
class IdentityGradient {
  final Color start;
  final Color end;

  /// Text drawn on top of the gradient. Fixed per pair rather than computed,
  /// because the right answer at the light end differs from the dark end and
  /// a luminance threshold picks wrong in the middle.
  final Color onColor;

  const IdentityGradient({
    required this.start,
    required this.end,
    required this.onColor,
  });

  LinearGradient get gradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [start, end],
  );
}

/// The fixed set of avatar gradients, and how an identity is assigned one.
///
/// These are deliberately *not* palette-derived: an avatar should look the
/// same to everyone in a channel whatever theme each person is running, and
/// under the Mono palette they are the only colour on screen — which is the
/// point of that palette.
class IdentityGradients {
  static const List<IdentityGradient> all = [
    IdentityGradient(
      start: Color(0xFF7B83FF),
      end: Color(0xFFEC4899),
      onColor: Color(0xFFFFFFFF),
    ),
    IdentityGradient(
      start: Color(0xFF38BDF8),
      end: Color(0xFF2DD4BF),
      onColor: Color(0xFF06211E),
    ),
    IdentityGradient(
      start: Color(0xFFFB923C),
      end: Color(0xFFF43F5E),
      onColor: Color(0xFF2A1204),
    ),
    IdentityGradient(
      start: Color(0xFFA56BFA),
      end: Color(0xFF7B83FF),
      onColor: Color(0xFFFFFFFF),
    ),
    IdentityGradient(
      start: Color(0xFF22C55E),
      end: Color(0xFF38BDF8),
      onColor: Color(0xFF052E16),
    ),
    IdentityGradient(
      start: Color(0xFFFBBF24),
      end: Color(0xFFFB923C),
      onColor: Color(0xFF2A1204),
    ),
  ];

  /// The gradient for [seed] — a user id, server id, or name.
  ///
  /// Deliberately sums code units rather than using [String.hashCode], which
  /// Dart does not promise to keep stable: an avatar that changes colour
  /// between runs, or differs between two people looking at the same user,
  /// stops working as an identity cue.
  static IdentityGradient forSeed(String seed) {
    if (seed.isEmpty) return all.first;
    var sum = 0;
    for (final unit in seed.codeUnits) {
      sum = (sum + unit) % all.length;
    }
    return all[sum];
  }
}
