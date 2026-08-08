import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/enums/home_surface.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/notifications/server_notifications_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/nav_row.dart';
import '../../../../common/unread_badge.dart';

/// The way into this server's DMs, above its channels.
///
/// It sits in the server column rather than on the rail because that is what
/// scopes it: these conversations belong to this server and change when you
/// switch. The rail's Home entry is the other tier — your account's DMs,
/// which follow you everywhere.
class ServerDmsRow extends StatelessWidget {
  const ServerDmsRow({super.key});

  @override
  Widget build(BuildContext context) {
    // Unread DMs, not a tally of open conversations: the badge used to show how
    // many people you'd ever talked to, which never changed when a message
    // arrived. It counts `notifications` rows now, exactly like a channel tile.
    final serverId = context.select<ServerCubit, String?>(
      (c) => c.state.selectedServerId,
    );
    final unread = serverId == null
        ? 0
        : context.select<ServerNotificationsCubit, int>(
            (c) => c.state.dmUnreadForServer(serverId),
          );

    return BlocBuilder<AppCubit, AppState>(
      buildWhen: (a, b) => a.surface != b.surface,
      builder: (context, appState) {
        return Padding(
          // No top gap: the jump field above carries the separation in its
          // own bottom padding, and the channel list below sets its
          // distance through the section header's 16px lead-in.
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
          child: NavRow(
            icon: Icons.forum_outlined,
            label: 'Server DMs',
            isSelected: appState.surface == HomeSurface.serverDms,
            isUnread: unread > 0,
            trailing: unread > 0
                ? UnreadBadge(
                    count: unread,
                    themeState: context.watch<ThemeCubit>().state,
                  )
                : null,
            onTap: () =>
                context.read<AppCubit>().setSurface(HomeSurface.serverDms),
          ),
        );
      },
    );
  }
}
