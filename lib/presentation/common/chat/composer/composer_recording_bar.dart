import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../../theme/custom_colors.dart';
import 'composer_icon_button.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';

/// What the composer bar shows while a voice note is being recorded.
///
/// A bare [Row] — the bar container wraps it — built from the same controls as
/// the input row, so the bar keeps its height when recording starts.
class ComposerRecordingBar extends StatelessWidget {
  final Duration elapsed;
  final VoidCallback onCancel;
  final VoidCallback onStop;

  const ComposerRecordingBar({
    super.key,
    required this.elapsed,
    required this.onCancel,
    required this.onStop,
  });

  static String _fmtElapsed(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Row(
      children: [
        ComposerIconButton(
          icon: Icons.delete_outline_rounded,
          tooltip: 'Discard',

          onPressed: onCancel,
        ),
        const SizedBox(width: 2),
        Container(
          width: 9,
          height: 9,
          decoration: const BoxDecoration(
            color: CustomColors.error,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 9),
        Text(
          'Recording…',
          style: AppText.input.copyWith(
            height: K.composerLineHeight,
            color: themeState.textSecondary,
          ),
        ),
        const Spacer(),
        Text(
          _fmtElapsed(elapsed),
          // Already tabular via AppText.figure — a recording timer that
          // reflows every second is the exact case that style exists for.
          style: AppText.code.copyWith(color: themeState.textTertiary),
        ),
        const SizedBox(width: 4),
        ComposerIconButton(
          icon: Icons.stop_circle_rounded,
          tooltip: 'Stop & attach',

          active: true,
          onPressed: onStop,
        ),
      ],
    );
  }
}
