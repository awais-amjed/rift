import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/user_avatar.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../../../home/profile/connection_quality/connection_quality_indicator.dart';

/// You, on the server you are looking at, at the top of a phone's settings.
///
/// A profile is per server, so this names which one; in a call the second line
/// is the connection's health instead, as it is on the dock.
class SettingsProfileCard extends StatelessWidget {
  final VoidCallback onEdit;

  const SettingsProfileCard({super.key, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final server = context.watch<ServerCubit>().state.selectedServer;
    final user = server?.user;
    if (user == null) return const SizedBox.shrink();
    final inCall = context.select<LiveKitCubit, bool>(
      (c) => c.state.connectionState == LiveKitConnectionState.connected,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.bgHover,
        borderRadius: BorderRadius.circular(K.radiusCard),
        border: Border.all(color: theme.borderElevated),
      ),
      child: Row(
        spacing: 14,
        children: [
          UserAvatar(
            avatarPath: user.avatarPath,
            name: user.displayName,
            seed: user.id,
            size: 56,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: 1,
              children: [
                Text(
                  user.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.panelTitle.copyWith(color: theme.textPrimary),
                ),
                Text(
                  '@${user.username} · ${server!.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.meta.copyWith(color: theme.textTertiary),
                ),
                if (inCall) const ConnectionQualityIndicator(),
              ],
            ),
          ),
          AppButton(
            label: 'Edit',
            variant: AppButtonVariant.secondary,
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}
