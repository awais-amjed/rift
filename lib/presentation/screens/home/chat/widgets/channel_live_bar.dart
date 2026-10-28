import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/chat_message.dart';
import '../../../../../data/classes/poll.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/call_panels/call_panels_cubit.dart';
import '../../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../../logic/services/live_items.dart';
import '../../../../common/chat/live_bar/live_bar.dart';
import '../../../../responsive/shell_scope.dart';

/// The open channel's [LiveBar], watching only what it draws: a keystroke, an
/// upload tick or somebody typing leaves it alone, and a vote rebuilds it and
/// not the history. A bot in a call shows its panel only to the people in it,
/// and to them in every channel's bar, wherever it was posted. While the
/// saved copy is on screen, its players are in neither the bar nor the
/// history: they are from whenever it was saved.
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
    // Who is in this device's call, as ids: speaking and mic changes leave it.
    final callUserIds = context
        .select<AppCubit, String>(
          (app) =>
              (app.state.participants.map((p) => p.userId).toSet().toList()
                    ..sort())
                  .join(','),
        )
        .split(',')
        .where((id) => id.isNotEmpty)
        .toSet();
    final voiceUserIds = context
        .select<ChannelPresenceCubit, String>(
          (presence) =>
              (presence.state.channelPresence.values
                      .expand((users) => users.map((u) => u.userId))
                      .toSet()
                      .toList()
                    ..sort())
                  .join(','),
        )
        .split(',')
        .where((id) => id.isNotEmpty)
        .toSet();
    final fromCall = context.select<CallPanelsCubit, CallPanelsState>(
      (call) => call.state,
    );
    final callPanels = shownPanels(context, fromCall.panels);
    return BlocSelector<
      ChannelChatCubit,
      ChannelChatState,
      (List<ChatMessage>, Map<String, PollTally>, bool, bool)
    >(
      selector: (s) => (
        s.live,
        s.pollTallies,
        s.status == ChannelChatStatus.ready,
        s.showingSaved,
      ),
      builder: (context, slice) {
        final (live, tallies, ready, saved) = slice;
        // The saved copy's player is from whenever it was saved, and pressing
        // it reaches a bot that has moved on: the bar waits for the fresh
        // page. The call's players were read just now, so they stay.
        final shown = shownPanels(context, live);
        final here = saved
            ? const <ChatMessage>[]
            : LiveItems.forCall(
                shown,
                callUserIds: callUserIds,
                voiceUserIds: voiceUserIds,
              );
        final side = phone ? K.composerSideInsetTouch : K.composerSideInset;
        return LiveBar(
          live: live,
          panels: LiveItems.withCallPanels(here, callPanels),
          tallies: tallies,
          // The history's rule: a seat that cannot send cannot vote.
          onVote: ready ? cubit.vote : null,
          onClosePoll: ready ? cubit.closePoll : null,
          onPanelAction: (messageId, action, value) {
            final channelId = fromCall.channelOf[messageId];
            final bot = callPanels.where((m) => m.id == messageId).firstOrNull;
            cubit.pressPanelAction(
              messageId,
              action,
              value,
              elsewhere: channelId == null || bot == null
                  ? null
                  : (channelId: channelId, botId: bot.authorId),
            );
          },
          loader: cubit.attachmentLoader,
          maxHeight:
              chatHeight * (phone ? K.liveBarMaxSharePhone : K.liveBarMaxShare),
          margin: EdgeInsets.fromLTRB(side, 4, side, 0),
        );
      },
    );
  }
}
