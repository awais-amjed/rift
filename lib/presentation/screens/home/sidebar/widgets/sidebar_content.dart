import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/enums/home_surface.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../dms/widgets/central_dm_list_panel.dart';
import '../../profile/user_dock/user_dock.dart';
import '../../servers/server_rail/server_rail.dart';
import 'server_dms_row.dart';
import 'sidebar_channel_list.dart';
import 'sidebar_header.dart';

/// The main content of the sidebar.
///
/// The column beside the rail is a list of *whatever tier the rail has
/// selected*: a server's channels, or — with Home picked — your central
/// conversations. The rail and the user dock frame both, because those two
/// belong to you rather than to either tier.
class SidebarContent extends StatelessWidget {
  final double topPadding;

  const SidebarContent({super.key, this.topPadding = 0});

  @override
  Widget build(BuildContext context) {
    // The panel's background, border and rounding belong to [AppPanel], which
    // wraps this in both modes — this widget is only the contents.
    return Row(
      children: [
        ServerRail(topPadding: topPadding),
        Expanded(
          child: BlocBuilder<AppCubit, AppState>(
            buildWhen: (a, b) => a.surface != b.surface,
            builder: (context, appState) {
              return Column(
                children: [
                  SizedBox(height: topPadding),
                  Expanded(
                    child: appState.surface == HomeSurface.centralDms
                        ? const CentralDmListPanel()
                        : const _ServerColumn(),
                  ),
                  const UserDock(),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// A server's own column: who the server is, its DMs, and its channels.
///
/// Identity, then navigation, and nothing else — the actions that act on the
/// server as a whole (invite, settings, manage members, leave) live on the
/// rail chip's context menu, on the chip they act on. A toolbar here would be
/// a second home for them that every member pays for in vertical space.
class _ServerColumn extends StatelessWidget {
  const _ServerColumn();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [SidebarHeader(), ServerDmsRow(), SidebarChannelList()],
    );
  }
}
