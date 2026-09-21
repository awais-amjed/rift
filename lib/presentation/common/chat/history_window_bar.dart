import 'package:flutter/material.dart';

import '../../../data/constants.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_text.dart';
import '../../theme/theme_context.dart';

/// The pill shown while the list is a window into history rather than the
/// live end of the conversation.
///
/// It is not a courtesy. Jumping to an old message replaces the list with
/// the fifty rows around it, so scrolling to the bottom of *that* reaches
/// the end of the window and stops — which looks exactly like the end of the
/// conversation. Without a line saying otherwise, the reader is looking at a
/// stretch of last month believing it is today. Scrolling down loads forward
/// from here too; this is the way back for somebody who does not want to
/// read the intervening thousand messages to get there.
///
/// It takes layout space rather than floating over the list. Normally that
/// would be the wrong call — a bar appearing mid-read shoves the
/// conversation — but this one only ever appears or leaves as the list is
/// replaced wholesale, and floating it put the pill on top of the newest
/// message in the window.
class HistoryWindowBar extends StatelessWidget {
  final VoidCallback onReturn;

  const HistoryWindowBar({super.key, required this.onReturn});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: Material(
        color: theme.bgElevated,
        borderRadius: BorderRadius.circular(K.radiusPill),
        elevation: 0,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(K.radiusPill),
            border: Border.all(color: theme.borderElevated),
            boxShadow: AppShadows.floatingBar,
          ),
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            onTap: onReturn,
            borderRadius: BorderRadius.circular(K.radiusPill),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 7, 12, 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Viewing older messages',
                    style: AppText.label.copyWith(
                      fontWeight: FontWeight.w400,
                      color: theme.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Jump to present',
                    style: AppText.chip.copyWith(color: theme.primary),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_downward_rounded,
                    size: 13,
                    color: theme.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
