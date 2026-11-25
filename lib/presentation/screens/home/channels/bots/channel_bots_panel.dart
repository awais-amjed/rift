import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../data/apis/bot_keys_api.dart';
import '../../../../../data/classes/channel.dart';
import '../../../../../data/classes/server_member.dart';
import '../../../../../data/repositories/server_session.dart';
import '../../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../common/confirm_dialog.dart';
import 'widgets/bot_grant_panel.dart';

/// Which bots hold the key to this channel.
///
/// This is the one screen in Rift that gives something away permanently. Every
/// other bot capability was arranged so a bot never needs a channel key — it
/// hears what it is told and nothing else — and a key is not a rule that can be
/// taken back, it is arithmetic. Revoking stops the server serving anything
/// more; it cannot unread what has been read.
///
/// So the confirm says that in as many words, and it is shown on the way *in*
/// rather than after. The header chip and the system message the grant leaves
/// behind are for everybody else in the room; this is for the person deciding.
class ChannelBotsPanel extends StatelessWidget {
  final Channel channel;

  const ChannelBotsPanel({super.key, required this.channel});

  @override
  Widget build(BuildContext context) => BotGrantPanel(
    subtitle: 'Bots that can read this channel',
    watchedVerb: 'read this channel',
    loadGranted: (session) =>
        BotKeysApi(session).channelListenerIds(channel.id),
    confirmGrant: (bot) => _confirmGrant(context, bot),
    setGranted: (session, bot, granting) =>
        _setGranted(context, session, bot, granting),
  );

  Future<({bool success, String? error})> _setGranted(
    BuildContext context,
    ServerSession session,
    ServerMember bot,
    bool granting,
  ) async {
    final result = await BotKeysApi(
      session,
    ).setBotChannelKey(channelId: channel.id, botId: bot.id, granted: granting);
    // The header's chip is the standing marker every member in the room reads.
    // It is loaded when a channel opens, so without this it keeps saying a bot
    // is reading a channel it was just shut out of — for as long as the channel
    // stays open, which is exactly the case that matters.
    if (result.success && context.mounted) {
      unawaited(context.read<ChannelChatCubit>().refreshBotListeners());
    }
    return (success: result.success, error: result.error);
  }

  Future<bool> _confirmGrant(BuildContext context, ServerMember bot) =>
      showConfirmDialog(
        context: context,
        title: 'Let ${bot.displayName} read #${channel.name}?',
        message:
            'It gets this channel’s encryption key and can read every message '
            'sent here from now on — including yours. It cannot read anything '
            'said before. Everyone in the channel is told, and taking it back '
            'later does not unread what it has already seen.',
        confirmLabel: 'Give it the key',
        icon: Icons.hearing_rounded,
        isDestructive: true,
      );
}
