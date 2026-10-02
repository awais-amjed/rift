import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/constants.dart';
import '../../../../data/enums/home_surface.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../common/empty_state.dart';
import '../../../theme/theme_context.dart';
import '../dms/server_dm_view.dart';
import '../dms/widgets/central_dm_list_panel.dart';
import '../main_content/widgets/banned_notice.dart';
import '../profile/user_dock/user_dock.dart';
import '../sidebar/widgets/sidebar_channel_list.dart';
import 'widgets/mini_call_bar.dart';
import 'widgets/server_surface_tabs.dart';
import 'widgets/switcher_header.dart';

/// The bottom of a phone's page stack: the list you are standing on.
///
/// A server's channels or its DMs, under the Channels / Direct tabs; or, with
/// Home picked in the switcher, your central conversations. These are the
/// desktop sidebar's own lists — the same channel rows and conversation list —
/// given the whole screen instead of a column.
class MobileHomePage extends StatelessWidget {
  const MobileHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final surface = context.select<AppCubit, HomeSurface>(
      (c) => c.state.surface,
    );
    final server = context
        .select<ServerCubit, ({bool any, String? banned, bool kicked})>((c) {
          final s = c.state.selectedServer;
          return (
            any: s != null,
            banned: (s?.user?.isBanned ?? false) ? s!.name : null,
            kicked: s?.user?.isKicked ?? false,
          );
        });

    final Widget body;
    if (surface == HomeSurface.centralDms) {
      body = const Expanded(child: CentralDmListPanel());
    } else if (!server.any) {
      body = const Expanded(
        child: EmptyState(
          icon: Icons.dns_outlined,
          title: 'No server yet',
          message: 'Tap the header to join or create one.',
        ),
      );
    } else if (server.banned != null) {
      // No tabs: every read on a server that banned you comes back empty, and
      // two halves of nothing would say the app is broken rather than closed.
      body = Expanded(
        child: BannedNotice(serverName: server.banned!, kicked: server.kicked),
      );
    } else {
      body = Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ServerSurfaceTabs(),
            if (surface == HomeSurface.serverDms)
              const Expanded(child: ServerDmView())
            else
              const SidebarChannelList(),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.bgSecondary,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SwitcherHeader(),
            body,
            // You, at the foot of the list, the way you are at the foot of
            // the sidebar on a desktop. It used to live only inside the
            // switcher sheet, which made muting yourself something you did
            // by opening a server picker.
            const Padding(
              padding: EdgeInsets.fromLTRB(
                K.panelGutter,
                0,
                K.panelGutter,
                K.panelGutter,
              ),
              child: UserDock(showSettings: true),
            ),
            const MiniCallBar(),
          ],
        ),
      ),
    );
  }
}
