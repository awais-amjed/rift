import 'package:flutter/material.dart';

import '../../data/constants.dart';
import '../theme/theme_context.dart';

/// What a volume reads beside its slider, with a button back to 100% before
/// it.
///
/// The button keeps its place while hidden (at 100%, or muted), so neither
/// the figure nor the track moves when a drag takes the level off 100%. It
/// goes by the rounded figure, not the exact level, so it never offers to
/// reset something that already reads 100%.
class VolumeReadout extends StatelessWidget {
  final double value;

  /// Muted reads an em dash rather than 0%, which would look like a volume
  /// you'd chosen, and offers no reset: the slider is off.
  final bool muted;

  /// Where the reset sends 100%. Null offers no reset.
  final ValueChanged<double>? onChanged;

  /// Size and weight only; the colour is the readout's own.
  final TextStyle style;

  /// A fixed width for the figure, wide enough for its largest value, so the
  /// track beside it does not shift as it is dragged. Null sizes it to fit.
  final double? width;

  static const double _buttonSize = 20;

  const VolumeReadout({
    super.key,
    required this.value,
    required this.style,
    this.onChanged,
    this.muted = false,
    this.width,
  });

  static String figure({required bool muted, required double value}) =>
      muted ? '—' : '${(value * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final reset = onChanged;
    final offered = reset != null && !muted && (value * 100).round() != 100;
    final text = Text(
      figure(muted: muted, value: value),
      textAlign: TextAlign.end,
      style: style.copyWith(color: theme.textSecondary),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        Visibility(
          visible: offered,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: IconButton(
            tooltip: 'Reset to 100%',
            mouseCursor: WidgetStateMouseCursor.clickable,
            onPressed: offered ? () => reset(1.0) : null,
            icon: const Icon(Icons.restart_alt_rounded, size: K.iconInline),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(
              width: _buttonSize,
              height: _buttonSize,
            ),
            style: IconButton.styleFrom(
              foregroundColor: theme.textTertiary,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(K.radiusRow),
              ),
            ),
          ),
        ),
        if (width == null) text else SizedBox(width: width, child: text),
      ],
    );
  }
}
