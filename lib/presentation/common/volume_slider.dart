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

  /// The thumb's radius on each side, when null, so the track runs edge to
  /// edge with the label and the percentage beside it and the thumb's rim
  /// meets them at either end. Flutter's own default pads by the hover ring's
  /// radius instead, which left every slider in settings starting 12px in
  /// from its label.
  final EdgeInsetsGeometry? padding;

  static const double _thumbRadius = 6;

  const VolumeSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.padding,
  });

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
        value: value,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    );
  }
}
