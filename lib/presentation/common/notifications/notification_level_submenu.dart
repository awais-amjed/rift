import 'package:flutter/material.dart';

import '../../../data/enums/notification_level.dart';
import '../context_menu/context_menu_item.dart';
import '../context_menu/context_menu_panel.dart';
import '../context_menu/context_menu_submenu_item.dart';

/// The "Notifications" row in a context menu, and the panel of levels it opens.
///
/// One widget for channels, server DMs and central DMs, because the choice is
/// the same choice everywhere and three copies of it would be three places for
/// the wording to drift. What differs is only which levels are on offer —
/// [choices] — since a DM has nobody in it to be named among.
class NotificationLevelSubmenu extends StatelessWidget {
  final NotificationLevel current;
  final List<NotificationLevel> choices;
  final ValueChanged<NotificationLevel> onSelected;

  const NotificationLevelSubmenu({
    super.key,
    required this.current,
    required this.onSelected,
    this.choices = NotificationLevel.channelChoices,
  });

  static IconData iconFor(NotificationLevel level) => switch (level) {
    NotificationLevel.all => Icons.notifications_active_outlined,
    NotificationLevel.mentions => Icons.alternate_email_rounded,
    NotificationLevel.none => Icons.notifications_off_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return ContextMenuSubmenuItem(
      icon: iconFor(current),
      label: 'Notifications',
      submenuBuilder: (context) => ContextMenuPanel(
        heading: 'Notify me about',
        maxWidth: 208,
        children: [
          for (final level in choices)
            ContextMenuItem(
              icon: iconFor(level),
              label: level.label,
              // The tick, rather than a highlighted row: the levels are three
              // things you could pick, and one of them happening to be current
              // should not look like the one being hovered.
              trailing: level == current
                  ? const Icon(Icons.check_rounded, size: 15)
                  : null,
              onTap: () => onSelected(level),
            ),
        ],
      ),
    );
  }
}
