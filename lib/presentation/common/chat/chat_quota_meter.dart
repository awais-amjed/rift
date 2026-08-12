import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/classes/chat_quota.dart';
import '../../../data/constants.dart';
import '../../../logic/cubits/theme/theme_cubit.dart';
import '../../theme/app_text.dart';
import '../../theme/custom_colors.dart';

/// Composer footer showing how many messages are left today, and — where there
/// is one — the nudge towards a surface without a limit.
///
/// Hidden until the number starts to matter. A quota you're nowhere near is
/// noise, and showing it constantly makes a limit feel meaner than it is; that
/// was true of central's 100/day and it is just as true of an operator's.
///
/// Presentational on purpose: central DMs, server DMs and channels all have a
/// daily budget now, and each wants its own sentence about what to do at the
/// wall, so the caller supplies [nudge] rather than this widget knowing which
/// tier it is on.
class ChatQuotaMeter extends StatelessWidget {
  /// Below this many remaining messages the meter becomes visible. Flat rather
  /// than a fraction: on a tight quota it means "always", which is right.
  static const showBelow = 25;

  /// Below this it turns amber; at zero, red.
  static const warnBelow = 10;

  final ChatQuota quota;

  /// Trailing suggestion while messages remain, e.g. "move longer chats to a
  /// shared server". Null shows nothing — a channel's limit is the operator's
  /// rule, and there is nowhere else to be pointed.
  final String? nudge;

  /// Trailing suggestion once the budget is spent.
  final String? exhaustedNudge;

  const ChatQuotaMeter({
    super.key,
    required this.quota,
    this.nudge,
    this.exhaustedNudge,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;
    if (!quota.isLimited || quota.remaining! >= showBelow) {
      return const SizedBox.shrink();
    }

    final remaining = quota.remaining!;
    final exhausted = quota.isExhausted;
    final color = exhausted
        ? CustomColors.error
        : (remaining < warnBelow
              ? CustomColors.warning
              : themeState.textTertiary);
    final trailing = exhausted ? exhaustedNudge : nudge;

    // Bar and text on one line: the meter is a footnote under the composer,
    // and stacking it made a limit you're nowhere near look like a warning.
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 7, 4, 0),
      child: Row(
        spacing: 8,
        children: [
          Expanded(child: _buildBar(themeState, color)),
          Text(
            exhausted
                ? 'Daily limit reached'
                : '$remaining of ${quota.quota} messages left today',
            style: AppText.label.copyWith(color: color),
          ),
          if (trailing != null)
            Flexible(
              child: Text(
                '· $trailing',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label.copyWith(
                  fontWeight: FontWeight.w400,
                  color: themeState.textQuaternary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBar(ThemeState themeState, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(K.radiusPill),
      child: LinearProgressIndicator(
        value: quota.fraction,
        minHeight: 3,
        backgroundColor: themeState.borderPrimary,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}
