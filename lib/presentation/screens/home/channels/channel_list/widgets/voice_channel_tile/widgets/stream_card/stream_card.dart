import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../../../data/participant_identity.dart';
import '../../../../../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../../../common/app_button.dart';
import '../../../../../../../../common/member_avatar.dart';
import '../../../../../../../../common/popover_surface.dart';
import '../../../../../../../../theme/app_text.dart';
import '../../../../../../../../theme/theme_context.dart';
import 'stream_card_controls.dart';
import 'stream_card_message.dart';

/// The card a sharing person's roster row opens: who, that they are live,
/// quick controls for them ([StreamCardControls]), one button to watch, and
/// a box to message them ([StreamCardMessage]).
///
/// The button says what it will do from where you are: join their call and
/// watch, watch from inside it, or bring back a stream already being watched.
class StreamCard extends StatelessWidget {
  final String userId;
  final String name;
  final String channelId;
  final VoidCallback onWatch;

  static const double width = 248;

  const StreamCard({
    super.key,
    required this.userId,
    required this.name,
    required this.channelId,
    required this.onWatch,
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
            StreamCardControls(userId: userId),
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
            if (!isMe) StreamCardMessage(userId: userId, name: name),
          ],
        ),
      ),
    );
  }
}

enum _Where { elsewhere, inCall, watching }
