import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';

/// One answer in a poll: what it says, whether the reader picked it, and —
/// once results are showing — its share of the picks, drawn as a fill behind
/// the row.
///
/// The fill is the selection tint, not an accent: a bar of solid colour per
/// option turns a poll into a chart, and the picked option has to stay the
/// one that stands out.
class PollOptionRow extends StatelessWidget {
  final String label;
  final bool picked;

  /// Several may be picked, so the mark is a box rather than a dot.
  final bool multiple;

  /// This option's share of every pick, 0–1, or null while results are
  /// hidden.
  final double? share;

  final VoidCallback? onTap;

  const PollOptionRow({
    super.key,
    required this.label,
    required this.picked,
    required this.multiple,
    required this.share,
    this.onTap,
  });

  static const double height = 38;

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final share = this.share;
    final mark = switch ((multiple, picked)) {
      (true, true) => Icons.check_box_rounded,
      (true, false) => Icons.check_box_outline_blank_rounded,
      (false, true) => Icons.radio_button_checked_rounded,
      (false, false) => Icons.radio_button_unchecked_rounded,
    };
    final radius = BorderRadius.circular(K.radiusRow);

    return Material(
      color: themeState.bgTertiary,
      borderRadius: radius,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: picked
                  ? themeState.channelActiveBorder
                  : themeState.borderPrimary,
            ),
          ),
          child: Stack(
            alignment: AlignmentDirectional.centerStart,
            children: [
              if (share != null)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: radius,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: share),
                        duration: AppMotion.state,
                        curve: AppMotion.settle,
                        builder: (context, value, _) => FractionallySizedBox(
                          widthFactor: value,
                          heightFactor: 1,
                          child: ColoredBox(color: themeState.channelActiveBg),
                        ),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  spacing: 8,
                  children: [
                    Icon(
                      mark,
                      size: K.iconRow,
                      color: picked
                          ? themeState.accentBright
                          : themeState.textTertiary,
                    ),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.secondaryStrong.copyWith(
                          color: themeState.textPrimary,
                        ),
                      ),
                    ),
                    if (share != null)
                      Text(
                        '${(share * 100).round()}%',
                        style: AppText.figure.copyWith(
                          color: themeState.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
