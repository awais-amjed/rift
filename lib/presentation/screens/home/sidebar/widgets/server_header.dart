import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/server.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/squircle_avatar.dart';
import '../../../../theme/app_shadows.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';

/// The selected server's identity at the top of the sidebar column.
///
/// It states the encryption guarantee under the name rather than hiding it in
/// settings: end-to-end encryption is the reason Rift exists, and a claim you
/// can see at all times is worth more than one you have to go looking for.
class ServerHeader extends StatelessWidget {
  final Server server;

  /// Admin-only. Null hides the gear.
  final VoidCallback? onOpenSettings;

  const ServerHeader({super.key, required this.server, this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onOpenSettings,
            hoverColor: themeState.bgHover,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 8, 12),
              child: Row(
                spacing: 11,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      boxShadow: AppShadows.accentGlow(
                        themeState.primary,
                        blurRadius: 16,
                        dy: 4,
                      ),
                    ),
                    child: SquircleAvatar(
                      name: server.name,
                      seed: server.id,
                      imageUrl: server.iconUrl,
                      size: 38,
                    ),
                  ),
                  Expanded(child: _buildIdentity(themeState)),
                  if (onOpenSettings != null)
                    Icon(
                      Icons.settings_outlined,
                      size: 17,
                      color: themeState.textTertiary,
                    ),
                  _buildPinToggle(themeState),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildIdentity(ThemeState themeState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          server.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.panelTitle.copyWith(color: themeState.textPrimary),
        ),
        const SizedBox(height: 1),
        Row(
          spacing: 5,
          children: [
            const Icon(
              Icons.lock_outline,
              size: 11,
              color: CustomColors.success,
            ),
            Flexible(
              child: Text(
                'End-to-end encrypted',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label.copyWith(color: themeState.textTertiary),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPinToggle(ThemeState themeState) {
    return BlocBuilder<AppCubit, AppState>(
      buildWhen: (p, c) => p.isPinned != c.isPinned,
      builder: (context, appState) {
        return IconButton(
          tooltip: appState.isPinned ? 'Unpin sidebar' : 'Pin sidebar',
          visualDensity: VisualDensity.compact,
          onPressed: () =>
              context.read<AppCubit>().setIsPinned(!appState.isPinned),
          icon: Icon(
            appState.isPinned
                ? Icons.chevron_left_rounded
                : Icons.push_pin_outlined,
            size: 18,
            color: themeState.textTertiary,
          ),
        );
      },
    );
  }
}
