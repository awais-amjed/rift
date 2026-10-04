import 'package:flutter/material.dart';

import '../theme/theme_context.dart';

/// The thin accent track every volume in the app is set with — a person, a
/// shared sound, the soundboard, a call cue.
///
/// A null [onChanged] disables it, which is how a muted volume reads: the
/// thumb sits at zero and cannot be dragged, rather than showing a level
/// that has no effect.
class VolumeSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  /// The loudest it goes: 1 is 100%. Above that the track catches at 100% on
  /// the way past, so the level something was meant to be at is easy to find
  /// again.
  final double max;

  /// The thumb's radius on each side, when null, so the track runs edge to
  /// edge with the label and the percentage beside it and the thumb's rim
  /// meets them at either end. Flutter's own default pads by the hover ring's
  /// radius instead, which left every slider in settings starting 12px in
  /// from its label.
  final EdgeInsetsGeometry? padding;

  static const double _thumbRadius = 6;

  /// How close to 100% a drag has to come to land on it.
  static const double _catch = 0.04;

  const VolumeSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.padding,
    this.max = 1.0,
  });

  double _caught(double value) =>
      max > 1 && (value - 1).abs() < _catch ? 1.0 : value;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: _thumbRadius,
        ),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        activeTrackColor: theme.primary,
        inactiveTrackColor: theme.bgActive,
        thumbColor: theme.primary,
      ),
      child: Slider(
        padding:
            padding ?? const EdgeInsets.symmetric(horizontal: _thumbRadius),
        value: value.clamp(0.0, max),
        max: max,
        onChanged: onChanged == null ? null : (v) => onChanged!(_caught(v)),
        onChangeEnd: onChangeEnd == null
            ? null
            : (v) => onChangeEnd!(_caught(v)),
      ),
    );
  }
}
