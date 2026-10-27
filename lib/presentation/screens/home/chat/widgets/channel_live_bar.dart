import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/chat_message.dart';
import '../../../../../data/classes/poll.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../../logic/services/live_items.dart';
import '../../../../common/chat/live_bar/live_bar.dart';
import '../../../../responsive/shell_scope.dart';

/// The open channel's [LiveBar], watching only what it draws: a keystroke, an
/// upload tick or somebody typing leaves it alone, and a vote rebuilds it and
/// not the history.
class ChannelLiveBar extends StatelessWidget {
  /// The chat's height, of which an opened line takes at most a share.
  final double chatHeight;

  const ChannelLiveBar({super.key, required this.chatHeight});

  /// The live panels among [live] the bar shows — the ones whose bot is
  /// connected — and so the ones the history leaves out. Both ask here, so
  /// the two never disagree and a panel is never in neither.
  ///
  /// Watches presence for the answer alone: somebody else coming online
  /// rebuilds nothing unless it changes which panels are shown.
  static List<ChatMessage> shownPanels(
    BuildContext context,
    List<ChatMessage> live,
  ) {
    List<ChatMessage> decide(ChannelPresenceCubit presence) =>
        LiveItems.shownPanels(
          live,
          onlineIds: presence.state.onlineUserIds,
          onlineKnown: presence.state.onlineKnown,
        );
    context.select<ChannelPresenceCubit, String>(
      (presence) => decide(presence).map((m) => m.id).join(','),
    );
    return decide(context.read<ChannelPresenceCubit>());
  }

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
          panels: shownPanels(context, live),
          tallies: tallies,
          // The history's rule: a seat that cannot send cannot vote.
          onVote: ready ? cubit.vote : null,
          onClosePoll: ready ? cubit.closePoll : null,
          onPanelAction: cubit.pressPanelAction,
          loader: cubit.attachmentLoader,
          maxHeight:
              chatHeight * (phone ? K.liveBarMaxSharePhone : K.liveBarMaxShare),
          margin: EdgeInsets.fromLTRB(side, 4, side, 0),
        );
      },
    );
  }
}
