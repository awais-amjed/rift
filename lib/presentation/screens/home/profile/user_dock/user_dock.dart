import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/server_user.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_modal.dart';
import '../../../../theme/app_text.dart';
import '../connection_quality/connection_quality_indicator.dart';
import '../edit/profile_edit_modal.dart';
import 'widgets/dock_avatar_button.dart';
import 'widgets/dock_icon_button.dart';
import '../../../../../data/constants.dart';

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
                borderRadius: BorderRadius.circular(K.radiusCard),
                border: Border.all(color: themeState.borderElevated),
              ),
              child: Row(
                spacing: 9,
                children: [
                  DockAvatarButton(
                    user: user,

                    onTap: () => showAppModal<bool>(
                      context: context,
                      modal: const ProfileEditModal(),
                    ),
                  ),
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
              style: AppText.strong.copyWith(color: themeState.textPrimary),
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
        // Effective state: a moderator holding the mic reads as muted here,
        // and the tooltip says so rather than offering an "Unmute" that the
        // cubit will refuse.
        final micOn = lkState.isMicOn;
        final deafened = lkState.isDeafenedEffective;

        return Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 2,
          children: [
            DockIconButton(
              icon: micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
              tooltip: lkState.isModerated
                  ? 'Muted by a moderator'
                  : (micOn ? 'Mute' : 'Unmute'),
              isError: !micOn,
              onTap: () => context.read<LiveKitCubit>().toggleMicrophone(),
            ),
            DockIconButton(
              icon: deafened
                  ? Icons.headset_off_rounded
                  : Icons.headset_rounded,
              tooltip: lkState.isServerDeafened
                  ? 'Deafened by a moderator'
                  : (deafened ? 'Undeafen' : 'Deafen'),
              isError: deafened,
              onTap: () => context.read<LiveKitCubit>().toggleDeafen(),
            ),
            // Settings is not here: the rail carries it, opening the same
            // screen. Two doors to one room only make you wonder whether they
            // lead somewhere different. What is left is what the dock is for
            // — the two things you reach for without leaving the call.
          ],
        );
      },
    );
  }
}
