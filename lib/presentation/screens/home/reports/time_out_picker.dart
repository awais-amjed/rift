import 'package:flutter/material.dart';

import '../../../../data/enums/time_out_length.dart';
import '../../../common/app_modal.dart';
import '../../../common/context_menu/context_menu_item.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';

/// Ask how long to time [name] out for. Null when the moderator backed out.
///
/// Used from a profile and from a report, so both say the same thing about
/// what a time-out does — the part a moderator deciding between this and a ban
/// needs to know.
Future<TimeOutLength?> showTimeOutPicker(BuildContext context, String name) {
  return showCustomDialog<TimeOutLength>(
    context: context,
    barrierDismissible: true,
    build: (dialogContext) {
      final theme = dialogContext.theme;
      return AppModal(
        title: 'Time out $name',
        subtitle: 'For how long?',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'They can still read, but can\'t send messages, DMs or '
              'reactions until it ends. It ends by itself.',
              style: AppText.meta.copyWith(color: theme.textTertiary),
            ),
            const SizedBox(height: 10),
            for (final length in TimeOutLength.values)
              ContextMenuItem(
                icon: Icons.timer_outlined,
                label: length.label,
                onTap: () => Navigator.of(dialogContext).pop(length),
              ),
          ],
        ),
      );
    },
  );
}
