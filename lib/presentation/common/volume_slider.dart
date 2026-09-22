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

  /// Flutter's own padding, when null. A slider lined up under something
  /// else passes its thumb's radius, so the track meets that thing's edges.
  final EdgeInsetsGeometry? padding;

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
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        activeTrackColor: theme.primary,
        inactiveTrackColor: theme.bgActive,
        thumbColor: theme.primary,
      ),
      child: Slider(
        padding: padding,
        value: value,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    );
  }
}
