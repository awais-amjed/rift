import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../../app_modal_header_button.dart';

/// The pinned panel's title bar: what it is, how many, and a way out.
class PinnedMessagesHeader extends StatelessWidget {
  /// Null while the list is still loading, or when it could not be.
  final int? count;

  const PinnedMessagesHeader({super.key, this.count});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: 8,
        children: [
          Icon(
            Icons.push_pin_outlined,
            size: K.iconRow,
            color: themeState.textTertiary,
          ),
          Text(
            'Pinned messages',
            style: AppText.dialogTitle.copyWith(color: themeState.textPrimary),
          ),
          if (count case final count?)
            Text(
              '$count',
              style: AppText.figure.copyWith(color: themeState.textTertiary),
            ),
          const Spacer(),
          AppModalHeaderButton(
            icon: Icons.close_rounded,
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}
