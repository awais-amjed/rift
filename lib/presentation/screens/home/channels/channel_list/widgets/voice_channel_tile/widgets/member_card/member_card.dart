import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../../../data/participant_identity.dart';
import '../../../../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../../../common/app_button.dart';
import '../../../../../../../../common/popover_surface.dart';
import '../../../../../../../../common/server_scope.dart';
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

  /// The voice channel their row is in. Null from a row that is not in one,
  /// and the card looks them up: in this device's call, or wherever their
  /// own broadcast says they are.
  final String? channelId;

  /// Whether they are sharing a screen, as the row knows it, or null to look
  /// it up the same way.
  final bool? sharing;

  /// Watch their stream in a voice channel. The button shows only while
  /// they are sharing — the card stays open when that ends, and it goes.
  final ValueChanged<String>? onWatch;

  /// Closes the card and opens their profile.
  final VoidCallback onProfile;

  /// Closes the card.
  final VoidCallback? onClose;

  static const double width = 264;

  const MemberCard({
    super.key,
    required this.userId,
    required this.name,
    this.channelId,
    this.sharing,
    required this.onProfile,
    this.onWatch,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final place = _place(context);
    final channelId = place.channelId;
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
    final serverId = ServerScope.idOf(context);
    final isMe = context.select<ServerCubit, bool>(
      (cubit) => cubit.state.meOn(serverId)?.id == userId,
    );
    final sharing = place.sharing;
    final watch = onWatch;
    final canWatch = sharing && channelId != null && watch != null;
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
              if (sharing)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MemberCardStream(
                      userId: userId,
                      gapBelow: canWatch ? 12 : 0,
                    ),
                    if (canWatch)
                      AppButton(
                        label: switch (where) {
                          _Where.elsewhere => 'Join and watch',
                          _Where.inCall => 'Watch stream',
                          _Where.watching => 'Open stream',
                        },
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        expanded: true,
                        onPressed: () => watch(channelId),
                      ),
                  ],
                ),
              MemberCardControls(userId: userId, name: name, onCall: onClose),
              MemberCardModeration(userId: userId, channelId: channelId),
              if (!isMe) MemberCardMessage(userId: userId, name: name),
            ],
          ),
        ),
      ),
    );
  }

  /// Where they are in voice, and whether they have a screen up there.
  ///
  /// Their own broadcast comes first: when they leave this device's call it
  /// says so before LiveKit does (`ChannelPresenceState.isElsewhere`). It never
  /// answers for you, so your own place is your call's. Selected as records,
  /// so a breath in the call redraws nothing here.
  ({String? channelId, bool sharing}) _place(BuildContext context) {
    final call = context.select<LiveKitCubit, String?>(
      (cubit) => cubit.state.connectionState == LiveKitConnectionState.connected
          ? cubit.state.currentChannelId
          : null,
    );
    final live = context.select<AppCubit, ({bool here, bool sharing})>((cubit) {
      final info = cubit.state.participants
          .where((p) => p.userId == userId && !p.isShare)
          .firstOrNull;
      return (here: info != null, sharing: info?.isSharingScreen ?? false);
    });
    final heard = context
        .select<ChannelPresenceCubit, ({String? channelId, bool sharing})>((
          cubit,
        ) {
          final at = cubit.state.channelOf(userId);
          final user = at == null
              ? null
              : cubit.state
                    .usersIn(at)
                    .where((u) => u.userId == userId)
                    .firstOrNull;
          return (channelId: at, sharing: user?.isSharingScreen ?? false);
        });
    final channel = channelId ?? heard.channelId ?? (live.here ? call : null);
    final inThisCall = channel != null && channel == call && live.here;
    return (
      channelId: channel,
      sharing: sharing ?? (inThisCall ? live.sharing : heard.sharing),
    );
  }
}

enum _Where { elsewhere, inCall, watching }
