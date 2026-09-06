import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/server.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/public_servers/public_servers_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../common/app_modal.dart';
import '../../../../theme/theme_context.dart';
import 'panels/bots_panel.dart';
import 'panels/danger_zone_panel.dart';
import 'panels/invites_panel.dart';
import 'panels/members_panel.dart';
import 'panels/overview_panel.dart';
import 'panels/roles_panel.dart';
import 'panels/webhooks_panel.dart';
import 'server_manage_tab.dart';
import 'widgets/manage_nav.dart';

/// Everything about running [server], in one dialog with a page per concern.
///
/// There used to be a dialog for each — settings here, roles behind a shield
/// in the members list, invites and members on the rail's menu, bots and
/// webhooks under each channel's right-click — and finding any of them meant
/// already knowing where it was. Now the rail's menu and the sidebar's gear
/// both open this, on whichever page the caller had in mind, and the rest are
/// one click to the left.
///
/// Which pages exist is [ServerManageTabs]; each page owns its own footer.
class ServerManageDialog extends StatefulWidget {
  final Server server;
  final ServerManageTab? initial;

  const ServerManageDialog({super.key, required this.server, this.initial});

  @override
  State<ServerManageDialog> createState() => _ServerManageDialogState();
}

class _ServerManageDialogState extends State<ServerManageDialog> {
  ServerManageTab? _active;

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    // Live, so a demotion while the dialog is open takes its pages away.
    final server =
        context.watch<ServerCubit>().state.serverById(widget.server.id) ??
        widget.server;
    final tabs = ServerManageTabs.visible(server.user?.permissions);
    final active = tabs.contains(_active)
        ? _active!
        : tabs.contains(widget.initial)
        ? widget.initial!
        : tabs.first;

    return AppModal(
      title: 'Manage server',
      subtitle: server.name,
      maxWidth: K.dialogWidthWidest,
      maxHeight: K.manageDialogHeight,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ManageNav(
            tabs: tabs,
            active: active,
            onSelected: (tab) => setState(() => _active = tab),
          ),
          VerticalDivider(width: 1, color: themeState.borderPrimary),
          Expanded(child: _page(active, server)),
        ],
      ),
    );
  }

  Widget _page(ServerManageTab tab, Server server) => switch (tab) {
    ServerManageTab.overview => OverviewPanel(server: server),
    ServerManageTab.roles => const RolesPanel(),
    ServerManageTab.members => MembersPanel(server: server),
    ServerManageTab.invites => InvitesPanel(server: server),
    ServerManageTab.bots => BotsPanel(server: server),
    ServerManageTab.webhooks => WebhooksPanel(server: server),
    ServerManageTab.danger => DangerZonePanel(server: server),
  };
}

/// The dialog with everything its pages read, for whichever route opens it.
///
/// Four cubits rather than one because the pages reach four places: the
/// server itself, the central listing and the account behind it, and the
/// app's own settings for the invite form.
Widget serverManageDialog(
  BuildContext context, {
  required Server server,
  ServerManageTab? initial,
}) {
  return MultiBlocProvider(
    providers: [
      BlocProvider.value(value: context.read<ServerCubit>()),
      BlocProvider.value(value: context.read<PublicServersCubit>()),
      BlocProvider.value(value: context.read<SupabaseBackupCubit>()),
      BlocProvider.value(value: context.read<AppCubit>()),
    ],
    child: ServerManageDialog(server: server, initial: initial),
  );
}

/// Open the dialog from anywhere with a plain context.
Future<void> showServerManageDialog(
  BuildContext context, {
  required Server server,
  ServerManageTab? initial,
}) {
  return showCustomDialog(
    context: context,
    barrierDismissible: true,
    builder: (_) =>
        serverManageDialog(context, server: server, initial: initial),
  );
}
