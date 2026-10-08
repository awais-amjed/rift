import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/server.dart';
import '../../../../../../data/classes/server_member.dart';
import '../../../../../../data/constants.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/hint_card.dart';
import '../../../../../common/loading_block.dart';
import '../../../bots/bot_directory_dialog.dart';
import '../../../channels/bots/bot_access_dialog.dart';
import '../widgets/bot_row.dart';
import '../widgets/manage_panel.dart';

/// The bots page of the manage-server dialog: every bot on the server, and
/// what each one can reach.
///
/// A bot's grants are per channel, and until now they were only findable a
/// channel at a time. This is the other way in: start from the bot, see
/// everything it holds ([BotAccessDialog]), and take any of it back.
///
/// It is also where a bot is *found*. Browsing the central directory
/// ([showBotDirectory]) belongs here rather than beside "Add server" on the
/// rail: a bot is not something you join, and adding one is minting an invite
/// on this server — which is the thing this page is already about.
///
/// The list is [ServerMembersCubit]'s bots, the dialog's copy for [server]:
/// a bot joining is a `users` row like anybody's, so it turns up here from
/// the server's doorbell — while the directory is still open, or added from
/// another device — rather than when the page is next reopened.
class BotsPanel extends StatelessWidget {
  final Server server;

  const BotsPanel({super.key, required this.server});

  void _openAccess(BuildContext context, ServerMember bot) {
    showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<ServerCubit>(),
        child: BotAccessDialog(bot: bot, serverId: server.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loaded = context.select<ServerMembersCubit, bool>(
      (c) => c.state.loaded,
    );
    final bots = context.select<ServerMembersCubit, List<ServerMember>>(
      (c) => c.state.bots,
    );
    return ManagePanel(
      title: 'Bots',
      subtitle: 'What each one can read and hear',
      footer: [
        AppButton(
          label: 'Browse bots',
          icon: const Icon(Icons.travel_explore_rounded, size: K.iconRow),
          onPressed: () => showBotDirectory(context),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!loaded)
            const LoadingBlock(padding: EdgeInsets.all(32))
          else if (bots.isEmpty)
            const HintCard(
              icon: Icons.smart_toy_outlined,
              text:
                  'No bots here yet. Browse bots below to find one, or create '
                  'an invite of your own from “Invite people” on the server '
                  'menu and choose Bot.',
            )
          else ...[
            const HintCard(
              icon: Icons.hearing_rounded,
              text:
                  'A bot hears only what it is told. Reading a channel means '
                  'holding its key, which cannot be taken back once given; '
                  'hearing a call can be.',
            ),
            const SizedBox(height: 12),
            for (final bot in bots)
              BotRow(bot: bot, onTap: () => _openAccess(context, bot)),
          ],
        ],
      ),
    );
  }
}
