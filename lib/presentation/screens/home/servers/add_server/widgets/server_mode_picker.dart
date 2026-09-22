import 'package:flutter/material.dart';

import '../../../../../../data/constants.dart';
import '../../../../../common/icon_tile.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';

/// Widget for choosing how to get onto a server: find one, join one you were
/// invited to, or build your own.
///
/// Cards and nothing else: the server rail on the left is already the way back
/// to the servers, so this step doesn't carry its own.
///
/// Browsing comes first because it is the only one of the three that works
/// with nothing in hand. The other two need something you were given or
/// something you have paid for.
class ServerModePicker extends StatelessWidget {
  final VoidCallback onBrowse;
  final VoidCallback onJoin;
  final VoidCallback onCreate;

  const ServerModePicker({
    super.key,
    required this.onBrowse,
    required this.onJoin,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 10,
      children: [
        _ModeCard(
          icon: Icons.travel_explore_outlined,
          title: 'Browse servers',
          subtitle: 'Find a public server and join it',
          onTap: onBrowse,
        ),
        _ModeCard(
          icon: Icons.login_rounded,
          title: 'Join server',
          subtitle: 'Join an existing server with an invite link',
          onTap: onJoin,
        ),
        _ModeCard(
          icon: Icons.build_outlined,
          title: 'Create server',
          subtitle: 'Set up your own server with Supabase and LiveKit',
          onTap: onCreate,
        ),
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
    final themeState = context.theme;
    final radius = BorderRadius.circular(K.radiusCard);

    return Material(
      color: themeState.bgHover,
      borderRadius: radius,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
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
  }
}
