import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';

/// Composer footer for central DMs: how many messages are left today, and the
/// nudge to move somewhere without a limit.
///
/// Central is the only tier that rations messages. A self-hosted server bounds
/// *storage* instead — a cap on history and on file size, which nothing about
/// sending needs to know — so this meter has exactly one home and stays here
/// rather than in the shared chat kit.
///
/// Hidden until the number starts to matter — a quota you're nowhere near is
/// noise, and showing it constantly would make the central tier feel meaner
/// than it is.
class QuotaMeter extends StatelessWidget {
  /// Below this many remaining messages the meter becomes visible.
  static const _showBelow = 25;

  /// Below this it turns amber; at zero, red.
  static const _warnBelow = 10;

  const QuotaMeter({super.key});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final state = context.watch<CentralDmCubit>().state;
    final remaining = state.remaining;
    final quota = state.quota;

    if (remaining == null || quota == null || remaining >= _showBelow) {
      return const SizedBox.shrink();
    }

    final exhausted = remaining <= 0;
    final color = exhausted
        ? CustomColors.error
        : (remaining < _warnBelow
              ? CustomColors.warning
              : themeState.textTertiary);

    // Bar and text on one line: the meter is a footnote under the composer,
    // and stacking it made a limit you're nowhere near look like a warning.
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 7, 4, 0),
      child: Row(
        spacing: 8,
        children: [
          Expanded(child: _buildBar(themeState, color, remaining / quota)),
          Text(
            exhausted
                ? 'Daily limit reached'
                : '$remaining of $quota messages left today',
            style: AppText.label.copyWith(color: themeState.statusInk(color)),
          ),
          Flexible(
            child: Text(
              exhausted
                  ? '· continue on a server you share'
                  : '· move longer chats to a shared server',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.label.copyWith(
                fontWeight: FontWeight.w400,
                color: themeState.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBar(ThemeState themeState, Color color, double fraction) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(K.radiusPill),
      child: LinearProgressIndicator(
        value: fraction.clamp(0.0, 1.0),
        minHeight: 3,
        backgroundColor: themeState.borderPrimary,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}
