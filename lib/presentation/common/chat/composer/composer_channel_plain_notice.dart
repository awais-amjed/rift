import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../../theme/app_text.dart';
import '../../../theme/custom_colors.dart';
import '../../../theme/theme_context.dart';

/// Sits above the composer in a channel whose encryption was turned off.
///
/// The header's chip says it too, but this is the one that is in view at the
/// moment it matters: while somebody is deciding what to write. It stands in
/// for the badge every message there would otherwise carry
/// (`MessageOriginBadge`), so it does not go away.
class ComposerChannelPlainNotice extends StatelessWidget {
  const ComposerChannelPlainNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: CustomColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(K.radiusRow),
        border: Border.all(color: CustomColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        spacing: 8,
        children: [
          Icon(
            Icons.lock_open_rounded,
            size: K.iconInline,
            color: theme.statusInk(CustomColors.warning),
          ),
          Expanded(
            child: Text(
              'Encryption is off in this channel. The server can read what '
              'you send.',
              style: AppText.meta.copyWith(color: theme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
