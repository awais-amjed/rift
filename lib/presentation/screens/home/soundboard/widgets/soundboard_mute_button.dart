import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';

/// The chip's one control: a glyph until the pointer is on it, then a word.
class SoundboardMuteButton extends StatelessWidget {
  /// Null draws the glyph alone — the resting desktop state.
  final String? label;
  final bool quiet;
  final VoidCallback onTap;

  const SoundboardMuteButton({
    super.key,
    this.label,
    this.quiet = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final color = quiet ? theme.textSecondary : CustomColors.error;
    final radius = BorderRadius.circular(K.radiusPill);

    return Material(
      color: label == null
          ? Colors.transparent
          : (quiet
                ? theme.bgHover
                : CustomColors.error.withValues(alpha: 0.10)),
      borderRadius: radius,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          height: 30,
          constraints: const BoxConstraints(minWidth: 30),
          padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 11),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: label == null
                ? null
                : Border.all(
                    color: quiet
                        ? theme.borderElevated
                        : CustomColors.error.withValues(alpha: 0.25),
                  ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!quiet) ...[
                Icon(
                  Icons.volume_off_rounded,
                  size: label == null ? 17 : 15,
                  color: label == null ? theme.textTertiary : color,
                ),
                if (label != null) const SizedBox(width: 6),
              ],
              if (label != null)
                Text(
                  label!,
                  style: AppText.secondaryStrong.copyWith(color: color),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
