import 'package:flutter/material.dart';

import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../responsive/shell_scope.dart';
import '../../../../theme/app_text.dart';
import '../../chat/widgets/chat_header.dart';
import '../../chat/widgets/header_pane_buttons.dart';

/// The bar above a DM conversation list: what the list is, and what it belongs
/// to.
///
/// On a phone this list is the whole surface, so this is the only bar on screen
/// and has to carry the way back to the drawer. [HeaderSidebarButton] renders
/// nothing where the sidebar is docked, so the wide layout is unchanged and
/// keeps its tighter lead-in.
class DmListHeader extends StatelessWidget {
  final String title;

  /// Sits under [title] — a handle, a server name.
  final String? subtitle;

  final ThemeState themeState;

  const DmListHeader({
    super.key,
    required this.title,
    required this.themeState,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final hasMenu = context.layoutMode.sidebarIsOverlay;

    return Container(
      height: ChatHeader.height,
      padding: EdgeInsets.fromLTRB(hasMenu ? 6 : 14, 0, 8, 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: themeState.borderPrimary)),
      ),
      // No "+": the search field below is the way to start a conversation, and
      // a button whose only job is to point at a field already on screen is one
      // control too many.
      child: Row(
        spacing: hasMenu ? 8 : 0,
        children: [
          const HeaderSidebarButton(),
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
                      color: themeState.textQuaternary,
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
