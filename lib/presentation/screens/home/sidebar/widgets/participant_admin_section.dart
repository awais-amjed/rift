import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/context_menu/context_menu_item.dart';
import '../../../../common/context_menu/context_menu_submenu_item.dart';
import '../../../../theme/app_text.dart';
import 'participant_move_menu.dart';
import 'participant_removal_items.dart';
import 'participant_roles_menu.dart';

/// The part of a participant's context menu that only staff see.
///
/// Two different permissions, with two different reaches:
///
/// * **Moderation** (mute, deafen) is for moderators, and only for someone in
///   a call with us — its current state arrives through LiveKit participant
///   metadata, so for anyone else the menu would be showing a guess.
/// * **Move to** is for moderators as well, and reaches further: it needs the
///   target to be in *a* call, not in ours, because pulling someone out of
///   another channel is most of the point.
/// * **Roles** is for server admins, and works whether or not they're in a
///   call, because the roster carries permissions either way.
/// * **Disconnect and Ban** come last, in that order, because they are the two
///   biggest things on here and the list should not start with them. Their own
///   reaches differ again — see [ParticipantRemovalItems].
class ParticipantAdminSection extends StatelessWidget {
  /// A live LiveKit identity, or a bare user id — moderation resolves the user
  /// out of it either way.
  final String target;
  final String targetUserId;

  final bool isModerator;
  final bool isServerAdmin;

  /// Whether they're in a voice channel with us, which is the only place their
  /// live moderation state can be read from.
  final bool isLive;

  /// The voice channel they're in — ours or another one — or null if they're
  /// not in a call, in which case there is nothing to move.
  final String? voiceChannelId;

  /// Shown beside the removal items, which name the person they act on.
  final String name;

  /// Whether the target is a server admin, in which case neither removal is
  /// offered — the server refuses both.
  final bool targetIsAdmin;

  final bool isServerMuted;
  final bool isServerDeafened;

  const ParticipantAdminSection({
    super.key,
    required this.target,
    required this.targetUserId,
    required this.isModerator,
    required this.isServerAdmin,
    required this.isLive,
    required this.voiceChannelId,
    required this.name,
    required this.targetIsAdmin,
    required this.isServerMuted,
    required this.isServerDeafened,
  });

  bool get _canMove => isModerator && voiceChannelId != null;

  /// Same reach as a move: staff, and only into a call that exists — but not
  /// against an admin, who `kick_user` refuses.
  bool get _canDisconnect => _canMove && !targetIsAdmin;

  bool get _showsAnything =>
      (isModerator && isLive) || _canMove || isServerAdmin;

  @override
  Widget build(BuildContext context) {
    if (!_showsAnything) return const SizedBox.shrink();

    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Named, so the staff half of a long menu reads as a group of its
            // own rather than more of the same list — on a phone this menu is
            // a sheet most of a screen tall.
            Divider(height: 9, color: themeState.borderPrimary),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
              child: Text(
                'MODERATION',
                style: AppText.sectionLabel.copyWith(
                  color: themeState.textTertiary,
                ),
              ),
            ),
            if (isModerator && isLive) ...[
              ContextMenuItem(
                icon: isServerMuted ? Icons.mic : Icons.mic_off,
                label: isServerMuted ? 'Server unmute' : 'Server mute',
                isDangerous: !isServerMuted,
                onTap: () => context.read<LiveKitCubit>().moderateParticipant(
                  participantIdentity: target,
                  muted: !isServerMuted,
                ),
              ),
              ContextMenuItem(
                icon: isServerDeafened ? Icons.headset : Icons.headset_off,
                label: isServerDeafened ? 'Server undeafen' : 'Server deafen',
                isDangerous: !isServerDeafened,
                onTap: () => context.read<LiveKitCubit>().moderateParticipant(
                  participantIdentity: target,
                  deafened: !isServerDeafened,
                ),
              ),
            ],
            if (_canMove)
              ContextMenuSubmenuItem(
                icon: Icons.moving_rounded,
                label: 'Move to',
                submenuBuilder: (_) => MultiBlocProvider(
                  providers: [
                    BlocProvider.value(value: context.read<ServerCubit>()),
                    BlocProvider.value(value: context.read<ThemeCubit>()),
                  ],
                  child: ParticipantMoveMenu(
                    userId: targetUserId,
                    fromChannelId: voiceChannelId,
                  ),
                ),
              ),
            if (isServerAdmin)
              ContextMenuSubmenuItem(
                icon: Icons.badge_outlined,
                label: 'Roles',
                submenuBuilder: (_) => MultiBlocProvider(
                  // A submenu is its own overlay entry, so it starts outside
                  // this tree and has to be handed the cubits it reads.
                  providers: [
                    BlocProvider.value(value: context.read<ServerCubit>()),
                    BlocProvider.value(
                      value: context.read<ServerMembersCubit>(),
                    ),
                    BlocProvider.value(value: context.read<ThemeCubit>()),
                  ],
                  child: ParticipantRolesMenu(userId: targetUserId),
                ),
              ),
            ParticipantRemovalItems(
              targetUserId: targetUserId,
              name: name,
              canDisconnect: _canDisconnect,
              // Admin only, matching `moderate_user`'s own `app.is_admin()`,
              // and never against another admin, which it also refuses.
              canBan: isServerAdmin && !targetIsAdmin,
            ),
            Divider(height: 9, color: themeState.borderPrimary),
          ],
        );
      },
    );
  }
}
