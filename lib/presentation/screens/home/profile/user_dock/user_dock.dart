import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../../data/classes/server_user.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/user_avatar.dart';
import '../../../../routing/app_routes.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../connection_quality/connection_quality_indicator.dart';
import '../edit/profile_edit_modal.dart';
import 'widgets/dock_icon_button.dart';

/// You, at the bottom of the sidebar: who you are, how your connection is
/// doing, and the two controls you reach for mid-call.
///
/// A floating pill inside the panel rather than a bar welded to its bottom
/// edge — it belongs to the same family as the voice card above it, and both
/// are things that sit *in* the sidebar rather than bound it.
class UserDock extends StatelessWidget {
  const UserDock({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return BlocBuilder<ServerCubit, ServerState>(
          buildWhen: (a, b) => a.selectedServer?.user != b.selectedServer?.user,
          builder: (context, serverState) {
            final user = serverState.selectedServer?.user;

            return Container(
              margin: const EdgeInsets.all(10),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: themeState.bgHover,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: themeState.borderElevated),
              ),
              child: Row(
                spacing: 9,
                children: [
                  _buildAvatar(context, themeState, user),
                  Expanded(child: _buildIdentity(themeState, user)),
                  _buildControls(context),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAvatar(
    BuildContext context,
    ThemeState themeState,
    ServerUser? user,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: () =>
          showAppModal<bool>(context: context, modal: const ProfileEditModal()),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          UserAvatar(
            avatarPath: user?.avatarPath,
            name: user?.displayName ?? 'Guest',
            size: 34,
            themeState: themeState,
            fallbackColor: themeState.bgSecondary,
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: user != null
                    ? CustomColors.userStatusOnline
                    : themeState.textQuaternary,
                shape: BoxShape.circle,
                // Ringed in the panel colour, not the dock's, so the dot reads
                // as punched through the avatar rather than stuck on it.
                border: Border.all(color: themeState.bgSecondary, width: 2.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentity(ThemeState themeState, ServerUser? user) {
    final username = user?.username;

    return BlocBuilder<LiveKitCubit, LiveKitState>(
      buildWhen: (prev, curr) => prev.connectionState != curr.connectionState,
      builder: (context, lkState) {
        final inVoice =
            lkState.connectionState == LiveKitConnectionState.connected;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              user?.displayName ?? 'Guest',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.row.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: themeState.textPrimary,
              ),
            ),
            // In a call the line is worth spending on live quality; otherwise
            // it just says who you are.
            if (inVoice)
              const ConnectionQualityIndicator()
            else if (username != null)
              Text(
                '@$username',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.meta.copyWith(color: themeState.textTertiary),
              ),
          ],
        );
      },
    );
  }

  Widget _buildControls(BuildContext context) {
    return BlocBuilder<LiveKitCubit, LiveKitState>(
      builder: (context, lkState) {
        final micOn = lkState.isMicEnabled && !lkState.isDeafened;
        final deafened = lkState.isDeafened;

        return Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 2,
          children: [
            DockIconButton(
              icon: micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
              tooltip: micOn ? 'Mute' : 'Unmute',
              isError: !micOn,
              onTap: () => context.read<LiveKitCubit>().toggleMicrophone(),
            ),
            DockIconButton(
              icon: deafened
                  ? Icons.headset_off_rounded
                  : Icons.headset_rounded,
              tooltip: deafened ? 'Undeafen' : 'Deafen',
              isError: deafened,
              onTap: () => context.read<LiveKitCubit>().toggleDeafen(),
            ),
            DockIconButton(
              icon: Icons.settings_outlined,
              tooltip: 'Settings',
              onTap: () => context.push(AppRoutes.settings),
            ),
          ],
        );
      },
    );
  }
}
