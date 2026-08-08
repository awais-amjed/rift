import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/constants.dart';
import '../../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../common/icon_tile.dart';
import '../../../../../theme/app_text.dart';

/// The first step of adding a server: join one, or create one.
///
/// Two cards side by side and nothing else. The server rail on the left is
/// already the way back, and on a full-page modal these two are the whole
/// screen — so they stand next to each other as a choice rather than stacking
/// into a list with an implied order.
class ServerModePicker extends StatelessWidget {
  final VoidCallback onJoin;
  final VoidCallback onCreate;

  const ServerModePicker({
    super.key,
    required this.onJoin,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        spacing: 14,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _ModeCard(
              icon: Icons.login_rounded,
              title: 'Join server',
              subtitle: 'Use an invite link from someone already on it',
              onTap: onJoin,
            ),
          ),
          Expanded(
            child: _ModeCard(
              icon: Icons.dns_outlined,
              title: 'Create server',
              subtitle: 'Point Rift at your own Supabase and LiveKit',
              onTap: onCreate,
            ),
          ),
        ],
      ),
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
        final radius = BorderRadius.circular(K.radiusDialog - 4);

        return Material(
          color: themeState.bgHover,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            hoverColor: themeState.bgActive,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: themeState.borderElevated),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Accent-tinted, not a neutral well: these two cards are the
                  // only things on the screen to press.
                  IconTile(
                    icon: icon,
                    color: themeState.accentBright,
                    size: 48,
                    radius: K.radiusCard,
                    iconSize: 22,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    style: AppText.sectionTitle.copyWith(
                      fontSize: 15,
                      color: themeState.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AppText.secondary.copyWith(
                      height: 1.45,
                      color: themeState.textTertiary,
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
