import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:toastification/toastification.dart';

import '../../../../../../../../../data/apis/voice_api.dart';
import '../../../../../../../../../data/repositories/session_repository.dart';
import '../../../../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../../../../../logic/helper_methods.dart';
import '../../../../../../../../common/context_menu/context_menu_overlay.dart';
import '../../../../../../../../theme/app_text.dart';
import '../../../../../../../../theme/theme_context.dart';
import '../../../../../../controls/widgets/control_button.dart';
import '../../../../../../sidebar/widgets/participant_move_menu.dart';

/// A moderator's row on a member card: server mute and deafen, move them to
/// another voice channel, and disconnect them from this one.
///
/// The same calls, and the same reach, as the right-click menu's moderation
/// section: mute and deafen only for somebody in this device's call, where
/// their current state is known; move and disconnect for anybody in a call.
/// Nothing against an admin, whom the server refuses — except a move, which
/// it allows — and nothing at all for somebody in no call.
class MemberCardModeration extends StatefulWidget {
  final String userId;

  /// The voice channel they are in, or null when they are in none.
  final String? channelId;

  const MemberCardModeration({super.key, required this.userId, this.channelId});

  @override
  State<MemberCardModeration> createState() => _MemberCardModerationState();
}

class _MemberCardModerationState extends State<MemberCardModeration> {
  final _moveMenu = ContextMenuOverlay();
  final _moveKey = GlobalKey();

  @override
  void dispose() {
    _moveMenu.dismiss();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userId = widget.userId;
    final moderator = context.select<ServerCubit, bool>((cubit) {
      final mine = cubit.state.myPermissions;
      return (mine?.isServerAdmin ?? false) ||
          (mine?.isChannelManager ?? false);
    });
    final me = context.select<ServerCubit, String?>(
      (cubit) => cubit.state.selectedServer?.user?.id,
    );
    if (!moderator || userId == me) return const SizedBox.shrink();

    final admin = context.select<ServerMembersCubit, bool>(
      (cubit) => cubit.state.byId[userId]?.permissions.isServerAdmin ?? false,
    );
    final live = context.select<AppCubit, ({bool muted, bool deafened})?>((
      cubit,
    ) {
      final info = cubit.state.participants
          .where((p) => p.userId == userId && !p.isShare)
          .firstOrNull;
      return info == null
          ? null
          : (muted: info.isServerMuted, deafened: info.isServerDeafened);
    });
    final theme = context.theme;
    final livekit = context.read<LiveKitCubit>();
    final channelId = widget.channelId;
    final canMute = live != null && !admin;
    final canMove = channelId != null;
    final canDisconnect = canMove && !admin;
    // One or two buttons have the width to say what they do; four share it
    // and lean on their tooltips, like the row above.
    final count =
        (canMute ? 2 : 0) + (canMove ? 1 : 0) + (canDisconnect ? 1 : 0);
    if (count == 0) return const SizedBox.shrink();
    String? named(String label) => count <= 2 ? label : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Text(
          'MODERATION',
          style: AppText.sectionLabel.copyWith(color: theme.textTertiary),
        ),
        Row(
          spacing: 6,
          children: [
            if (canMute) ...[
              Expanded(
                child: ControlButton(
                  dense: true,
                  icon: Icons.mic_off_rounded,
                  tooltip: live.muted ? 'Server unmute' : 'Server mute',
                  isError: live.muted,
                  onTap: () => _refused(
                    livekit.moderateParticipant(
                      participantIdentity: userId,
                      muted: !live.muted,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ControlButton(
                  dense: true,
                  icon: Icons.headset_off_rounded,
                  tooltip: live.deafened ? 'Server undeafen' : 'Server deafen',
                  isError: live.deafened,
                  onTap: () => _refused(
                    livekit.moderateParticipant(
                      participantIdentity: userId,
                      deafened: !live.deafened,
                    ),
                  ),
                ),
              ),
            ],
            if (canMove)
              Expanded(
                child: ControlButton(
                  key: _moveKey,
                  dense: true,
                  icon: Icons.moving_rounded,
                  tooltip: 'Move to',
                  label: named('Move to'),
                  onTap: _openMove,
                ),
              ),
            if (canDisconnect)
              Expanded(
                child: ControlButton(
                  dense: true,
                  icon: Icons.call_end_rounded,
                  tooltip: 'Disconnect',
                  label: named('Disconnect'),
                  onTap: _disconnect,
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// The menu's own list of channels, opened under the button. A submenu is
  /// its own overlay entry, so it is handed the cubits it reads.
  void _openMove() {
    final box = _moveKey.currentContext?.findRenderObject() as RenderBox?;
    final from = widget.channelId;
    if (box == null || from == null) return;
    final at = box.localToGlobal(box.size.bottomLeft(Offset.zero));
    _moveMenu.show(
      context,
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: context.read<ServerCubit>()),
          BlocProvider.value(value: context.read<ThemeCubit>()),
        ],
        child: ParticipantMoveMenu(userId: widget.userId, fromChannelId: from),
      ),
      at,
    );
  }

  /// Ends their connections to the call, as the menu's Disconnect does.
  Future<void> _disconnect() async {
    final voice = VoiceApi(session: context.read<SessionRepository>());
    final response = await voice.kickUser(userId: widget.userId);
    if (response.success) return;
    HelperMethods.showToast(
      title: 'Could not disconnect',
      description: '${response.error}',
      type: ToastificationType.error,
    );
  }

  /// A refusal would otherwise look like a button that does nothing.
  Future<void> _refused(Future<bool> call) async {
    if (await call) return;
    HelperMethods.showToast(
      title: 'Could not change that',
      description: 'The server refused. Try again in a moment.',
      type: ToastificationType.error,
    );
  }
}
