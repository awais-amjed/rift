import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../data/classes/server.dart';
import '../../../../../../../logic/cubits/notifications/server_notifications_cubit.dart';
import '../../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../common/confirm_dialog.dart';
import '../../../../../common/unread_badge.dart';
import '../../../../../common/squircle_avatar.dart';

/// A single server item in the server list.
class ServerListItem extends StatelessWidget {
  final Server server;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const ServerListItem({
    super.key,
    required this.server,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
  });

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Remove Server',
      message:
          'Remove "${server.name}" from your server list? Your account on '
          'this server will remain intact — you can rejoin with your token '
          'at any time.',
      confirmLabel: 'Remove',
      icon: Icons.logout_rounded,
      isDestructive: true,
    );
    if (confirmed) onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final unread = context.select<ServerNotificationsCubit, int>(
      (c) => c.state.unreadForServer(server.id),
    );
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            hoverColor: themeState.bgHover,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  // Avatar
                  SquircleAvatar(
                    name: server.name,
                    seed: server.id,
                    imageUrl: server.iconUrl,
                  ),
                  const SizedBox(width: 12),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          server.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: themeState.textPrimary,
                          ),
                        ),
                        Text(
                          server.supabaseUrl,
                          style: TextStyle(
                            fontSize: 11,
                            color: themeState.textTertiary,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Unread badge
                  if (unread > 0) ...[
                    UnreadBadge(count: unread, themeState: themeState),
                    const SizedBox(width: 8),
                  ],
                  // Selected indicator
                  if (isSelected) ...[
                    Text(
                      'Active',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: themeState.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.check, size: 16, color: themeState.primary),
                  ],
                  // Delete
                  IconButton(
                    onPressed: () => _confirmDelete(context),
                    icon: Icon(
                      Icons.logout_rounded,
                      size: 15,
                      color: themeState.textTertiary,
                    ),
                    style: IconButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
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
