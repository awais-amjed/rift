import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/custom_colors.dart';

/// Bottom area of the sidebar showing the current user info + theme toggle.
class UserProfile extends StatelessWidget {
  const UserProfile({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? CustomColors.bgTertiaryDark
        : CustomColors.bgTertiaryLight;
    final borderColor = isDark
        ? CustomColors.borderPrimaryDark
        : CustomColors.borderPrimaryLight;
    final textPrimary = isDark
        ? CustomColors.textPrimaryDark
        : CustomColors.textPrimaryLight;
    final textTertiary = isDark
        ? CustomColors.textTertiaryDark
        : CustomColors.textTertiaryLight;
    final textQuaternary = isDark
        ? CustomColors.textQuaternaryDark
        : CustomColors.textQuaternaryLight;
    final hoverColor = isDark
        ? CustomColors.bgHoverDark
        : CustomColors.bgHoverLight;

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
                    hoverColor: hoverColor,
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
                                  color: isDark
                                      ? CustomColors.bgSecondaryDark
                                      : CustomColors.bgSecondaryLight,
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
                                        : textQuaternary,
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
                                    color: textPrimary,
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
              // Theme toggle
              BlocBuilder<ThemeCubit, ThemeState>(
                builder: (context, themeState) {
                  return IconButton(
                    onPressed: () => context.read<ThemeCubit>().switchTheme(),
                    icon: Icon(
                      themeState.isDarkTheme
                          ? Icons.wb_sunny_outlined
                          : Icons.nightlight_round,
                      size: 18,
                      color: textTertiary,
                    ),
                    tooltip: 'Toggle theme',
                    style: IconButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  );
                },
              ),
              // Settings (placeholder)
              IconButton(
                onPressed: () {},
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
  }
}
