import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/apis/moderation_api.dart';
import '../../../../../../data/classes/server.dart';
import '../../../../../../data/classes/server_member.dart';
import '../../../../../../data/constants.dart';
import '../../../../../../data/enums/server_permission.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../../logic/helper_methods.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/hint_card.dart';
import '../../../../../common/loading_block.dart';
import '../../../../../common/server_scope.dart';
import '../../../../../common/show_custom_dialog.dart';
import '../../../bots/bot_directory_dialog.dart';
import '../../../channels/bots/bot_access_dialog.dart';
import '../../../members/widgets/kick_confirm.dart';
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
/// And it is where a bot is taken off the server: a kick, the same one the
/// voice menu and a report offer, so a bot that is not in a call and was
/// never reported can still be removed from the one page that lists it.
///
/// The list is [ServerMembersCubit]'s bots, the dialog's copy for [server]:
/// a bot joining is a `users` row like anybody's, so it turns up here from
/// the server's doorbell — while the directory is still open, or added from
/// another device — rather than when the page is next reopened.
class BotsPanel extends StatelessWidget {
  final Server server;

  const BotsPanel({super.key, required this.server});

  void _openAccess(BuildContext context, ServerMember bot) {
    showCustomDialog<void>(
      context: context,
      build: (_) => BlocProvider.value(
        value: context.read<ServerCubit>(),
        child: BotAccessDialog(bot: bot),
      ),
    );
  }

  Future<void> _kick(BuildContext context, ServerMember bot) async {
    // Read before the await: the confirmation is a route over this page.
    final moderation = ModerationApi(ServerScope.read(context));
    final members = context.read<ServerMembersCubit>();
    if (!await confirmKick(context, bot.displayName, isBot: true)) return;
    final response = await moderation.kickMember(userId: bot.id);
    if (!response.success) {
      HelperMethods.showToast(
        title: 'Could not kick',
        description: '${response.error}',
      );
      return;
    }
    HelperMethods.showToast(
      title: 'Kicked',
      description: '${bot.displayName} is out until a new bot invite.',
    );
    // The doorbell brings the same answer a moment later; the row should not
    // wait for it.
    await members.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final mayKick = context.select<ServerCubit, bool>(
      (c) =>
          c.state.permissionsOn(server.id)?.can(ServerPermission.kickMembers) ??
          false,
    );
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
              BotRow(
                bot: bot,
                onTap: () => _openAccess(context, bot),
                onKick: mayKick && !bot.isBanned
                    ? () => _kick(context, bot)
                    : null,
              ),
          ],
        ],
      ),
    );
  }
}
