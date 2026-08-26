import 'package:flutter/material.dart';

import '../../../../../common/context_menu/context_menu_item.dart';
import '../../../../../common/context_menu_region.dart';
import 'friend_row_action.dart';

/// One [FriendRowAction] as a row in a right-click menu.
///
/// A widget rather than a built `ContextMenuItem`, because the menu has to be
/// dismissed before the action runs and `ContextMenuScope` is only reachable
/// from *inside* the panel. Building the item where the list is built would
/// look up the scope in the tile's context, find nothing, and leave the menu
/// standing over whatever dialog the action opened.
///
/// The action's tooltip doubles as the label. They are written as short
/// imperatives for exactly this reason — "Remove friend" reads the same
/// hovering a circle as it does in a list of menu rows.
class FriendMenuItem extends StatelessWidget {
  final FriendRowAction action;

  const FriendMenuItem({super.key, required this.action});

  @override
  Widget build(BuildContext context) {
    return ContextMenuItem(
      icon: action.icon,
      label: action.tooltip,
      isDangerous: action.isDangerous,
      onTap: () {
        ContextMenuScope.of(context)?.call();
        action.onTap();
      },
    );
  }
}
