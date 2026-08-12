import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/context_menu/context_menu_item.dart';
import '../../../../common/context_menu/context_menu_panel.dart';
import '../../../../common/context_menu_region.dart';
import '../../dms/server_dm_settings_dialog.dart';

/// Right-click menu for the Server DMs entry — the way to its retention
/// settings, mirroring the one on a channel.
///
/// Server admins only, and for the same reason the channel menu is managers
/// only: `update_server` refuses anyone else, so this is about not offering
/// what would be turned down. There is no delete item — DMs are not a thing
/// that can be removed.
class ServerDmsContextMenu extends StatelessWidget {
  const ServerDmsContextMenu({super.key});

  /// Wraps [child] in the menu for an admin, and returns it untouched for
  /// everyone else — so a member's right-click falls through instead of opening
  /// an empty panel.
  static Widget wrap({required BuildContext context, required Widget child}) {
    final isAdmin =
        context
            .watch<ServerCubit>()
            .state
            .selectedServer
            ?.user
            ?.permissions
            .isServerAdmin ??
        false;
    if (!isAdmin) return child;
    return ContextMenuRegion(
      contextMenu: const ServerDmsContextMenu(),
      child: child,
    );
  }

  void _openSettings(BuildContext context) {
    ContextMenuScope.of(context)?.call();
    showCustomDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<ServerCubit>(),
        child: const ServerDmSettingsDialog(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ContextMenuPanel(
      heading: 'Direct messages',
      subheading: 'This server',
      leading: Icon(
        Icons.forum_outlined,
        size: 16,
        color: context.watch<ThemeCubit>().state.textTertiary,
      ),
      children: [
        ContextMenuItem(
          icon: Icons.tune_rounded,
          label: 'Settings',
          onTap: () => _openSettings(context),
        ),
      ],
    );
  }
}
