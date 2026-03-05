import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/user_permissions.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';

/// Shows invite and create-channel action buttons based on user permissions.
class ServerActionBar extends StatelessWidget {
  final UserPermissions permissions;
  final VoidCallback? onInvite;
  final VoidCallback? onCreateChannel;

  const ServerActionBar({
    super.key,
    required this.permissions,
    this.onInvite,
    this.onCreateChannel,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final borderColor = themeState.borderPrimary;
        final textTertiary = themeState.textTertiary;
        final hoverColor = themeState.bgHover;

        final showInvite = permissions.canCreateTokens;
        final showCreateChannel = permissions.isChannelManager;

        if (!showInvite && !showCreateChannel) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: borderColor)),
          ),
          child: Row(
            children: [
              if (showInvite)
                Expanded(
                  child: _ActionButton(
                    icon: Icons.person_add_outlined,
                    label: 'Invite',
                    color: textTertiary,
                    hoverColor: hoverColor,
                    onTap: onInvite,
                  ),
                ),
              if (showInvite && showCreateChannel) const SizedBox(width: 4),
              if (showCreateChannel)
                Expanded(
                  child: _ActionButton(
                    icon: Icons.create_new_folder_outlined,
                    label: 'New Channel',
                    color: textTertiary,
                    hoverColor: hoverColor,
                    onTap: onCreateChannel,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color hoverColor;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.hoverColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: hoverColor,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
