import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../../../data/participant_identity.dart';
import '../../../../../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../../../../common/app_button.dart';
import '../../../../../../../../common/member_avatar.dart';
import '../../../../../../../../common/popover_surface.dart';
import '../../../../../../../../theme/app_text.dart';
import '../../../../../../../../theme/theme_context.dart';
import 'member_card_controls.dart';
import 'member_card_message.dart';

/// The card a person's roster row opens: who, quick controls for them
/// ([MemberCardControls]), a box to message them ([MemberCardMessage]), and
/// while they are sharing their screen, one button to watch it.
///
/// That button says what it will do from where you are: join their call and
/// watch, watch from inside it, or bring back a stream already being watched.
class MemberCard extends StatelessWidget {
  final String userId;
  final String name;
  final String channelId;

  /// Null unless they are sharing a screen, which is when there is something
  /// to watch.
  final VoidCallback? onWatch;

  static const double width = 248;

  const MemberCard({
    super.key,
    required this.userId,
    required this.name,
    required this.channelId,
    this.onWatch,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final where = context.select<LiveKitCubit, _Where>((cubit) {
      final lk = cubit.state;
      if (lk.connectionState != LiveKitConnectionState.connected ||
          lk.currentChannelId != channelId) {
        return _Where.elsewhere;
      }
      return lk.subscribedScreenshares.any(
            (identity) => ParticipantIdentity.userIdOf(identity) == userId,
          )
          ? _Where.watching
          : _Where.inCall;
    });
    final isMe = context.select<ServerCubit, bool>(
      (cubit) => cubit.state.selectedServer?.user?.id == userId,
    );
    final sharing = onWatch != null;
    // Their handle under the name, as the dock shows yours, when there is no
    // stream to talk about instead.
    final handle = context.select<ServerMembersCubit, String?>(
      (cubit) => cubit.state.byId[userId]?.username,
    );
    return SizedBox(
      width: width,
      child: PopoverSurface(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Row(
              spacing: 10,
              children: [
                MemberAvatar(userId: userId, name: name, size: 36),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.strong.copyWith(
                          color: theme.textPrimary,
                        ),
                      ),
                      if (!sharing && handle != null && handle.isNotEmpty)
                        Text(
                          '@$handle',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.secondary.copyWith(
                            color: theme.textTertiary,
                          ),
                        ),
                      if (sharing)
                        Row(
                          spacing: 4,
                          children: [
                            // The same screen the roster row shows.
                            Icon(
                              Icons.monitor_outlined,
                              size: 14,
                              color: theme.accentBright,
                            ),
                            Flexible(
                              child: Text(
                                isMe
                                    ? 'Sharing your screen'
                                    : 'Sharing their screen',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.secondary.copyWith(
                                  color: theme.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
            MemberCardControls(userId: userId),
            if (sharing)
              AppButton(
                label: switch (where) {
                  _Where.elsewhere => 'Join and watch',
                  _Where.inCall => 'Watch stream',
                  _Where.watching => 'Open stream',
                },
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                expanded: true,
                onPressed: onWatch,
              ),
            if (!isMe) MemberCardMessage(userId: userId, name: name),
          ],
        ),
      ),
    );
  }
}

enum _Where { elsewhere, inCall, watching }
