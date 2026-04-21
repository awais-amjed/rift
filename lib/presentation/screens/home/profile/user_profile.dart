import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../routing/app_routes.dart';
import '../../../theme/custom_colors.dart';

/// Bottom area of the sidebar showing the current user info + theme toggle.
class UserProfile extends StatelessWidget {
  const UserProfile({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final bgColor = themeState.bgTertiary;
        final borderColor = themeState.borderPrimary;
        final textTertiary = themeState.textTertiary;

        return BlocBuilder<ServerCubit, ServerState>(
          builder: (context, serverState) {
            final user = serverState.selectedServer?.user;
            final displayName = user?.displayName ?? 'Guest';
            final username = user?.username;

            return Container(
              height: 64,
              decoration: BoxDecoration(
                color: bgColor,
                border: Border(top: BorderSide(color: borderColor)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  // User info area
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        hoverColor: themeState.bgHover,
                        onTap: () {},
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              // Avatar
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: themeState.bgSecondary,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: borderColor),
                                    ),
                                    alignment: Alignment.center,
                                    child: const Text(
                                      '🐱',
                                      style: TextStyle(fontSize: 18),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: -2,
                                    right: -2,
                                    child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: user != null
                                            ? CustomColors.userStatusOnline
                                            : themeState.textQuaternary,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: bgColor,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 10),
                              // Name
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      displayName,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: themeState.textPrimary,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (username != null)
                                      Text(
                                        '@$username',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: textTertiary,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Mic mute / deafen buttons
                  BlocBuilder<LiveKitCubit, LiveKitState>(
                    builder: (context, lkState) {
                      final micOn = lkState.isMicEnabled && !lkState.isDeafened;
                      final deafened = lkState.isDeafened;

                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Mute toggle
                          _ProfileIconButton(
                            icon: micOn ? Icons.mic : Icons.mic_off,
                            tooltip: micOn ? 'Mute' : 'Unmute',
                            isError: !micOn,
                            iconColor: micOn
                                ? textTertiary
                                : CustomColors.error,
                            onTap: () =>
                                context.read<LiveKitCubit>().toggleMicrophone(),
                          ),
                          // Deafen toggle
                          _ProfileIconButton(
                            icon: deafened ? Icons.headset_off : Icons.headset,
                            tooltip: deafened ? 'Undeafen' : 'Deafen',
                            isError: deafened,
                            iconColor: deafened
                                ? CustomColors.error
                                : textTertiary,
                            onTap: () =>
                                context.read<LiveKitCubit>().toggleDeafen(),
                          ),
                        ],
                      );
                    },
                  ),
                  // Settings (placeholder)
                  IconButton(
                    onPressed: () => context.push(AppRoutes.settings),
                    icon: Icon(
                      Icons.settings_outlined,
                      size: 18,
                      color: textTertiary,
                    ),
                    tooltip: 'Settings',
                    style: IconButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ProfileIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isError;
  final Color iconColor;
  final VoidCallback onTap;

  const _ProfileIconButton({
    required this.icon,
    required this.tooltip,
    required this.iconColor,
    required this.onTap,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Tooltip(
          message: tooltip,
          child: Material(
            color: isError
                ? CustomColors.error.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              hoverColor: themeState.bgHover,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(icon, size: 18, color: iconColor),
              ),
            ),
          ),
        );
      },
    );
  }
}
