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
  final ServerManageTab? active;
  final ValueChanged<ServerManageTab> onSelected;

  /// The whole width, as a phone's list of pages rather than a column beside
  /// one.
  final bool expand;

  const ManageNav({
    super.key,
    required this.tabs,
    required this.active,
    required this.onSelected,
    this.expand = false,
  });

  static const double width = 196;

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Container(
      width: expand ? null : width,
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
                label: tab.label,
                // Nothing is selected in a phone's list — it is the way in,
                // and the page opened is on its own screen.
                isSelected: !expand && tab == active,
                pushes: expand,
                onTap: () => onSelected(tab),
              ),
            ),
        ],
      ),
    );
  }

  static IconData _icon(ServerManageTab tab) => switch (tab) {
    ServerManageTab.overview => Icons.tune_rounded,
    ServerManageTab.limits => Icons.speed_rounded,
    ServerManageTab.roles => Icons.shield_outlined,
    ServerManageTab.members => Icons.group_outlined,
    ServerManageTab.bots => Icons.smart_toy_outlined,
    ServerManageTab.webhooks => Icons.webhook_rounded,
    ServerManageTab.soundboard => Icons.graphic_eq_rounded,
    ServerManageTab.danger => Icons.warning_amber_rounded,
  };
}
