import 'package:flutter/material.dart';

import '../../../../../../data/constants.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/custom_colors.dart';
import '../../../../../theme/theme_context.dart';

/// That this person is banned from the server the profile is about.
///
/// A notice and not a pill. `BOT` beside a name is an attribute of the
/// person — it is what they are, everywhere, and a word is the right size
/// for it. A ban is a *state of this server's relationship with them*: it
/// has a consequence, it can be lifted, and somebody reading the profile
/// needs both of those facts, neither of which fits in a six-letter chip.
/// Drawn where a pill was, so the answer is in the same place the question
/// was asked.
///
/// A kick is drawn the same way with its own words: the same lock-out, but one
/// any new invite ends.
class ProfileBannedNotice extends StatelessWidget {
  /// Kicked rather than banned.
  final bool kicked;

  const ProfileBannedNotice({super.key, this.kicked = false});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: CustomColors.error.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(K.radiusRow),
        border: Border.all(color: CustomColors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Icon(
            kicked ? Icons.logout_rounded : Icons.gavel_rounded,
            size: K.iconRow,
            color: CustomColors.error,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kicked
                      ? 'Kicked from this server'
                      : 'Banned from this server',
                  style: AppText.secondaryStrong.copyWith(
                    color: CustomColors.error,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  kicked
                      ? 'A new invite brings them back, without the roles '
                            'they had. Their messages stay where they are.'
                      : 'They cannot rejoin. Their messages stay where they '
                            'are. Any admin can lift it.',
                  style: AppText.secondary.copyWith(
                    height: 1.5,
                    color: theme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
