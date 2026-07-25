import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/server.dart';
import '../../../../../../logic/cubits/notifications/server_notifications_cubit.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/unread_badge.dart';
import 'widgets/server_avatar.dart';

/// Displays the currently selected server in the sidebar header.
class ServerButton extends StatelessWidget {
  final Server server;
  final VoidCallback onTap;

  const ServerButton({super.key, required this.server, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Activity on *other* servers → a dot nudging the user to open the switcher.
    final otherUnread = context.select<ServerNotificationsCubit, int>(
      (c) => c.state.totalUnreadExcept(server.id),
    );
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            hoverColor: themeState.bgHover,
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: themeState.borderPrimary),
                ),
              ),
              child: Row(
                children: [
                  // Unread on another server → a dot on the avatar's corner
                  // (kept off the trailing edge, which holds the pin/chevron).
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ServerAvatar(server: server),
                      if (otherUnread > 0)
                        Positioned(
                          top: -1,
                          right: -1,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: themeState.sidebarBg,
                              shape: BoxShape.circle,
                            ),
                            child: UnreadDot(themeState: themeState, size: 9),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      server.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: themeState.textPrimary,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
