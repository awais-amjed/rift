import 'package:flutter/material.dart';

import '../../../../responsive/shell_scope.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../../chat/widgets/chat_header.dart';
import '../../pane_toggles/show_sidebar_button.dart';

/// The bar above a DM conversation list: what the list is, and what it belongs
/// to.
///
/// Not drawn on a phone, where the list sits under the server's own header and
/// its Channels / Direct tabs — the two already say what this bar would.
class DmListHeader extends StatelessWidget {
  final String title;

  /// Sits under [title] — a handle, a server name.
  final String? subtitle;

  const DmListHeader({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    if (context.layoutMode.isCompact) return const SizedBox.shrink();
    final themeState = context.theme;

    return Container(
      height: ChatHeader.height,
      padding: const EdgeInsets.fromLTRB(14, 0, 8, 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: themeState.borderPrimary)),
      ),
      // No "+": the search field below is the way to start a conversation, and
      // a button whose only job is to point at a field already on screen is one
      // control too many.
      child: Row(
        children: [
          if (ShowSidebarButton.shows(context)) ...[
            const ShowSidebarButton(),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.strong.copyWith(color: themeState.textPrimary),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.meta.copyWith(
                      color: themeState.textTertiary,
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
