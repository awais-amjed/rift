import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/context_menu/context_menu_item.dart';
import '../../../../common/context_menu/context_menu_submenu_item.dart';
import 'participant_roles_menu.dart';

/// The part of a participant's context menu that only staff see.
///
/// Two different permissions, with two different reaches:
///
/// * **Moderation** (mute, deafen) is for moderators, and only for someone in
///   a call with us — its current state arrives through LiveKit participant
///   metadata, so for anyone else the menu would be showing a guess.
/// * **Roles** is for server admins, and works whether or not they're in a
///   call, because the roster carries permissions either way.
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

  final bool isServerMuted;
  final bool isServerDeafened;

  const ParticipantAdminSection({
    super.key,
    required this.target,
    required this.targetUserId,
    required this.isModerator,
    required this.isServerAdmin,
    required this.isLive,
    required this.isServerMuted,
    required this.isServerDeafened,
  });

  bool get _showsAnything => (isModerator && isLive) || isServerAdmin;

  @override
  Widget build(BuildContext context) {
    if (!_showsAnything) return const SizedBox.shrink();

    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            Divider(height: 9, color: themeState.borderPrimary),
          ],
        );
      },
    );
  }
}
