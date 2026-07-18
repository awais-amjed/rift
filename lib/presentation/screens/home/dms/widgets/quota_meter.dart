import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';

/// Composer footer for central DMs: shows the remaining daily messages once
/// it starts to matter, and the "move to a server" nudge when low.
class QuotaMeter extends StatelessWidget {
  /// Below this many remaining messages the meter becomes visible.
  static const _showBelow = 25;

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
        ? Colors.redAccent
        : (remaining < 10 ? Colors.orangeAccent : themeState.textQuaternary);

    return Row(
      children: [
        Icon(Icons.hourglass_bottom, size: 12, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            exhausted
                ? 'Daily limit reached — central DMs are for finding each '
                    'other. Continue on a server you share!'
                : '$remaining of $quota messages left today — for longer '
                    'chats, move to a shared server.',
            style: TextStyle(fontSize: 11, color: color),
          ),
        ),
      ],
    );
  }
}
