import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../logic/cubits/theme/theme_cubit.dart';

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
          icon: Icons.login,
          title: 'Join Server',
          subtitle: 'Join an existing server with an invite link',
          onTap: onJoin,
        ),
        const SizedBox(height: 10),
        _ModeCard(
          icon: Icons.build_outlined,
          title: 'Create Server',
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
        return Material(
          color: themeState.bgTertiary,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            hoverColor: themeState.bgHover,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: themeState.borderPrimary),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: themeState.bgSecondary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 22, color: themeState.primary),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: themeState.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: themeState.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: themeState.textTertiary),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
