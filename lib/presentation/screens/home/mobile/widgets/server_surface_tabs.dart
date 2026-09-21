import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../data/enums/home_surface.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/notifications/server_notifications_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../common/selectable_surface.dart';
import '../../../../common/unread_badge.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// Channels or Direct — the two lists a server has, under its header.
///
/// On a desktop the server's DMs are a row above its channels, because a
/// column can hold both. A phone's list is the whole screen, so the two become
/// halves of one switch: each keeps its own unread count visible while the
/// other is showing, which is the job the row's badge did.
class ServerSurfaceTabs extends StatelessWidget {
  const ServerSurfaceTabs({super.key});

  @override
  Widget build(BuildContext context) {
    final surface = context.select<AppCubit, HomeSurface>(
      (c) => c.state.surface,
    );
    final serverId = context.select<ServerCubit, String?>(
      (c) => c.state.selectedServerId,
    );
    final (channels, direct) = serverId == null
        ? (0, 0)
        : context.select<ServerNotificationsCubit, (int, int)>((c) {
            final dms = c.state.dmUnreadForServer(serverId);
            return (c.state.unreadForServer(serverId) - dms, dms);
          });
    final onDirect = surface == HomeSurface.serverDms;

    void show(HomeSurface next) => context.read<AppCubit>().setSurface(next);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
      child: Row(
        spacing: 8,
        children: [
          Expanded(
            child: _Tab(
              icon: Icons.tag_rounded,
              label: 'Channels',
              unread: channels,
              selected: !onDirect,
              onTap: () => show(HomeSurface.server),
            ),
          ),
          Expanded(
            child: _Tab(
              icon: Icons.forum_outlined,
              label: 'Direct',
              unread: direct,
              selected: onDirect,
              onTap: () => show(HomeSurface.serverDms),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final IconData icon;
  final String label;
  final int unread;
  final bool selected;
  final VoidCallback onTap;

  const _Tab({
    required this.icon,
    required this.label,
    required this.unread,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final radius = BorderRadius.circular(K.radiusRow);
    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 7,
      children: [
        Icon(
          icon,
          size: 16,
          color: selected ? theme.accentBright : theme.textTertiary,
        ),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (selected ? AppText.row : AppText.rowQuiet).copyWith(
              color: selected ? theme.channelActiveText : theme.textSecondary,
            ),
          ),
        ),
        if (unread > 0) UnreadBadge(count: unread),
      ],
    );

    // Selected is the shared tint-and-ring; the other half is left bare, so
    // the pair reads as one switch with a position rather than two buttons.
    return SizedBox(
      height: K.controlHeight,
      child: selected
          ? SelectableSurface(
              selected: true,
              onTap: onTap,
              borderRadius: radius,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: content,
            )
          : Material(
              type: MaterialType.transparency,
              child: InkWell(
                mouseCursor: WidgetStateMouseCursor.clickable,
                borderRadius: radius,
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: content,
                ),
              ),
            ),
    );
  }
}
