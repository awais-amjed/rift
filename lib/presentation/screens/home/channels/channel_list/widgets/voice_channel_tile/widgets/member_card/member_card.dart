import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../../../data/participant_identity.dart';
import '../../../../../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../../../common/app_button.dart';
import '../../../../../../../../common/popover_surface.dart';
import 'member_card_about.dart';
import 'member_card_controls.dart';
import 'member_card_header.dart';
import 'member_card_message.dart';
import 'member_card_moderation.dart';
import 'member_card_stream.dart';

/// The card a person's roster row opens, top to bottom:
///
/// * who they are ([MemberCardHeader]) — the avatar opens their profile;
/// * their roles, a time-out, and their state in the call
///   ([MemberCardAbout]);
/// * what they are sharing ([MemberCardStream]) and a button to watch it;
/// * quick controls for them ([MemberCardControls]), and for a moderator,
///   moderation ([MemberCardModeration]);
/// * a box to message them ([MemberCardMessage]).
///
/// The Watch button says what it will do from where you are: join their call
/// and watch, watch from inside it, or bring back a stream already watched.
class MemberCard extends StatelessWidget {
  final String userId;
  final String name;
  final String channelId;

  /// Null unless they are sharing a screen, which is when there is something
  /// to watch.
  final VoidCallback? onWatch;

  /// Closes the card and opens their profile.
  final VoidCallback onProfile;

  /// Closes the card.
  final VoidCallback? onClose;

  static const double width = 264;

  const MemberCard({
    super.key,
    required this.userId,
    required this.name,
    required this.channelId,
    required this.onProfile,
    this.onWatch,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
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
    return SizedBox(
      width: width,
      child: PopoverSurface(
        // A tall card in a short window scrolls rather than overflowing:
        // the layout keeps it inside the window, not its content.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              MemberCardHeader(
                userId: userId,
                name: name,
                sharing: sharing,
                isMe: isMe,
                onProfile: onProfile,
              ),
              MemberCardAbout(userId: userId, channelId: channelId),
              if (sharing) ...[
                MemberCardStream(userId: userId),
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
              ],
              MemberCardControls(userId: userId, name: name, onCall: onClose),
              MemberCardModeration(userId: userId, channelId: channelId),
              if (!isMe) MemberCardMessage(userId: userId, name: name),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Where { elsewhere, inCall, watching }
