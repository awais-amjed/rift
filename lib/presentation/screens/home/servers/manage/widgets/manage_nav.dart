import 'package:flutter/material.dart';

import '../../../../../common/nav_row.dart';
import '../../../../../theme/theme_context.dart';
import '../server_manage_tab.dart';

/// The dialog's left-hand nav: one row per page the viewer may see.
///
/// The settings screen's rows, so a page picker reads the same wherever it
/// is. Only the rows are here; which of them exist is [ServerManageTabs].
class ManageNav extends StatelessWidget {
  final List<ServerManageTab> tabs;
  final ServerManageTab active;
  final ValueChanged<ServerManageTab> onSelected;

  const ManageNav({
    super.key,
    required this.tabs,
    required this.active,
    required this.onSelected,
  });

  static const double width = 196;

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Container(
      width: width,
      color: themeState.bgSecondary,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final tab in tabs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: NavRow(
                icon: _icon(tab),
                label: _label(tab),
                isSelected: tab == active,
                onTap: () => onSelected(tab),
              ),
            ),
        ],
      ),
    );
  }

  static IconData _icon(ServerManageTab tab) => switch (tab) {
    ServerManageTab.overview => Icons.tune_rounded,
    ServerManageTab.roles => Icons.shield_outlined,
    ServerManageTab.members => Icons.group_outlined,
    ServerManageTab.invites => Icons.person_add_outlined,
    ServerManageTab.bots => Icons.smart_toy_outlined,
    ServerManageTab.webhooks => Icons.webhook_rounded,
    ServerManageTab.danger => Icons.warning_amber_rounded,
  };

  static String _label(ServerManageTab tab) => switch (tab) {
    ServerManageTab.overview => 'Overview',
    ServerManageTab.roles => 'Roles',
    ServerManageTab.members => 'Members',
    ServerManageTab.invites => 'Invites',
    ServerManageTab.bots => 'Bots',
    ServerManageTab.webhooks => 'Webhooks',
    ServerManageTab.danger => 'Danger zone',
  };
}
