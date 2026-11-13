import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../data/classes/server_user.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/server_scope.dart';
import '../../../../routing/app_routes.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../connection_quality/connection_quality_indicator.dart';
import '../edit/profile_edit_modal.dart';
import 'widgets/dock_avatar_button.dart';
import 'widgets/dock_call_panel.dart';
import 'widgets/dock_icon_button.dart';

/// You, at the bottom of the sidebar: who you are, how your connection is
/// doing, and the two controls you reach for mid-call — and, with
/// [showCall], the call itself above them ([DockCallPanel]).
///
/// A floating pill inside the panel rather than a bar welded to its bottom
/// edge — it belongs to the same family as the voice card above it, and both
/// are things that sit *in* the sidebar rather than bound it. On a phone, with
/// [docked], it is the screen's foot instead: a card floating in a gutter
/// there read as a box inside a box.
class UserDock extends StatelessWidget {
  /// Adds a gear for settings. On a phone the dock is at the foot of the
  /// switcher and the rail that carried the gear on a desktop isn't built, so
  /// this is where settings lives there.
  final bool showSettings;

  /// Grows the call's controls on top while in one: a desktop's sidebar, and
  /// a phone's list of channels. A phone's chats have the call bar instead
  /// ([MiniCallBar]), as they have no dock.
  final bool showCall;

  /// Full width on the bottom edge, rounded only at the top, its fill running
  /// on under the system's bar at the foot of a phone's screen.
  final bool docked;

  const UserDock({
    super.key,
    this.showSettings = false,
    this.showCall = false,
    this.docked = false,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final serverId = ServerScope.idOf(context);
    // Selected with the id this build was given, not filtered by a
    // `buildWhen` holding the last one: a builder only takes a new state
    // when its filter lets one through, so the server just joined was looked
    // up in the list from before it existed, and the dock read "Guest".
    final user = context.select<ServerCubit, ServerUser?>(
      (cubit) => cubit.state.meOn(serverId),
    );

    return Container(
      margin: docked ? EdgeInsets.zero : const EdgeInsets.all(10),
      padding: docked
          ? EdgeInsets.fromLTRB(
              12,
              18,
              12,
              18 + MediaQuery.paddingOf(context).bottom,
            )
          : const EdgeInsets.all(8),
      decoration: ShapeDecoration(
        color: themeState.bgHover,
        shape: RoundedRectangleBorder(
          borderRadius: docked
              ? const BorderRadius.vertical(top: Radius.circular(K.radiusCard))
              : BorderRadius.circular(K.radiusCard),
          side: BorderSide(color: themeState.borderElevated),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showCall) DockCallPanel(inline: docked),
          Row(
            spacing: 9,
            children: [
              DockAvatarButton(
                user: user,
                onTap: user == null
                    ? null
                    : () => showAppModal<bool>(
                        context: context,
                        modal: const ProfileEditModal(),
                      ),
              ),
              Expanded(child: _buildIdentity(themeState, user)),
              _buildControls(context),
            ],
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
              style: AppText.strong.copyWith(color: themeState.textPrimary),
            ),
            // In a call the line is worth spending on live quality; otherwise
            // it just says who you are.
            if (inVoice)
              const ConnectionQualityIndicator()
            else if (username != null)
              // The quality line pads itself 1px top and bottom for its hover
              // box; this line matches it, or the dock grew by 2px the moment
              // a call connected.
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  '@$username',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.meta.copyWith(color: themeState.textTertiary),
                ),
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
          // A desktop's dock is a strip of chrome; a phone's lines these up
          // under the call's controls.
          spacing: docked ? K.dockIconGap : 2,
          children: [
            DockIconButton(
              icon: micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
              tooltip: lkState.isMicHeld
                  ? lkState.micHeldLabel
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
            // Settings only where there is no rail to carry it: two doors to
            // one room only make you wonder whether they lead somewhere
            // different.
            if (showSettings)
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
