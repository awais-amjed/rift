import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../data/classes/server.dart';
import '../../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../../theme/custom_colors.dart';
import 'server_avatar.dart';

/// A single server item in the server list.
class ServerListItem extends StatelessWidget {
  final Server server;
  final bool isSelected;
  final bool canDelete;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const ServerListItem({
    super.key,
    required this.server,
    required this.isSelected,
    required this.canDelete,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
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
                  ServerAvatar(server: server),
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
                  // Selected indicator
                  if (isSelected) ...[
                    Text(
                      'Active',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: CustomColors.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.check,
                      size: 16,
                      color: CustomColors.primary,
                    ),
                  ],
                  // Delete
                  if (canDelete)
                    IconButton(
                      onPressed: onDelete,
                      icon: Icon(
                        Icons.close,
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
