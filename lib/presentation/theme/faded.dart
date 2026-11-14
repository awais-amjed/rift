import 'package:material_ui/material_ui.dart';

/// A colour drawn at part strength, over whatever alpha it already has.
///
/// Fading a few small things by their own colours costs nothing, where an
/// `Opacity` round them draws them into a layer of their own every frame.
/// Overlapping parts then show through each other, which on a dimmed row
/// nobody can see.
extension Faded on Color {
  Color faded(double opacity) =>
      opacity >= 1 ? this : withValues(alpha: a * opacity);
}
