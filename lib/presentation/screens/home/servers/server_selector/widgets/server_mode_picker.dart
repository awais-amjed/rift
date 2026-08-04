import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/constants.dart';
import '../../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../common/icon_tile.dart';
import '../../../../../theme/app_text.dart';

/// Widget for choosing between joining or creating a server.
class ServerModePicker extends StatelessWidget {
  final VoidCallback onJoin;
  final VoidCallback onCreate;
  final VoidCallback onBack;

  const ServerModePicker({
    super.key,
    required this.onJoin,
    required this.onCreate,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ModeCard(
          icon: Icons.login_rounded,
          title: 'Join server',
          subtitle: 'Join an existing server with an invite link',
          onTap: onJoin,
        ),
        const SizedBox(height: 10),
        _ModeCard(
          icon: Icons.build_outlined,
          title: 'Create server',
          subtitle: 'Set up your own server with Supabase and LiveKit',
          onTap: onCreate,
        ),
        const SizedBox(height: 16),
        TextButton(onPressed: onBack, child: const Text('Back to Servers')),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final radius = BorderRadius.circular(14);

        return Material(
          color: themeState.bgHover,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            hoverColor: themeState.bgActive,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: themeState.borderElevated),
              ),
              child: Row(
                spacing: 14,
                children: [
                  // Accent-tinted, not a neutral well: these two cards are the
                  // only things on the screen to press.
                  IconTile(
                    icon: icon,
                    color: themeState.accentBright,
                    size: 44,
                    radius: K.radiusCard,
                    iconSize: 20,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppText.row.copyWith(
                            color: themeState.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          subtitle,
                          style: AppText.secondary.copyWith(
                            color: themeState.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: themeState.textQuaternary,
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
