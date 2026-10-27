import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/chat_message.dart';
import '../../../../../data/classes/poll.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../common/chat/live_bar/live_bar.dart';
import '../../../../responsive/shell_scope.dart';

/// The open channel's [LiveBar], watching only what it draws: a keystroke, an
/// upload tick or somebody typing leaves it alone, and a vote rebuilds it and
/// not the history.
class ChannelLiveBar extends StatelessWidget {
  /// The chat's height, of which an opened line takes at most a share.
  final double chatHeight;

  const ChannelLiveBar({super.key, required this.chatHeight});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ChannelChatCubit>();
    final phone = context.layoutMode.isCompact;
    return BlocSelector<
      ChannelChatCubit,
      ChannelChatState,
      (List<ChatMessage>, Map<String, PollTally>, bool)
    >(
      selector: (s) =>
          (s.live, s.pollTallies, s.status == ChannelChatStatus.ready),
      builder: (context, slice) {
        final (live, tallies, ready) = slice;
        final side = phone ? K.composerSideInsetTouch : K.composerSideInset;
        return LiveBar(
          live: live,
          tallies: tallies,
          // The history's rule: a seat that cannot send cannot vote.
          onVote: ready ? cubit.vote : null,
          onClosePoll: ready ? cubit.closePoll : null,
          maxHeight:
              chatHeight * (phone ? K.liveBarMaxSharePhone : K.liveBarMaxShare),
          margin: EdgeInsets.fromLTRB(side, 4, side, 0),
        );
      },
    );
  }
}
