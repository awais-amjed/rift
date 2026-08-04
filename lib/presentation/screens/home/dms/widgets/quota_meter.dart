import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';

/// Composer footer for central DMs: how many messages are left today, and the
/// nudge to move somewhere without a limit.
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
    final themeState = context.watch<ThemeCubit>().state;
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

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBar(themeState, color, remaining / quota),
          const SizedBox(height: 6),
          Row(
            spacing: 6,
            children: [
              Icon(Icons.hourglass_bottom_rounded, size: 12, color: color),
              Expanded(
                child: Text(
                  exhausted
                      ? 'Daily limit reached — central DMs are for finding '
                            'each other. Continue on a server you share!'
                      : '$remaining of $quota messages left today — for '
                            'longer chats, move to a shared server.',
                  style: AppText.label.copyWith(color: color),
                ),
              ),
            ],
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
        backgroundColor: themeState.bgActive,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}
