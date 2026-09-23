import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/server.dart';
import '../../../../../../data/classes/server_member.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
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
class BotsPanel extends StatefulWidget {
  final Server server;

  const BotsPanel({super.key, required this.server});

  @override
  State<BotsPanel> createState() => _BotsPanelState();
}

class _BotsPanelState extends State<BotsPanel> {
  List<ServerMember> _bots = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bots = await context.read<ServerCubit>().listBots(
      serverId: widget.server.id,
    );
    if (!mounted) return;
    setState(() {
      _bots = bots;
      _isLoading = false;
    });
  }

  /// Find one in the central directory. Reloads on the way back, because
  /// adding a bot is the program joining, which may have happened while the
  /// browser was still open.
  Future<void> _browse() async {
    await showBotDirectory(context);
    if (mounted) await _load();
  }

  void _openAccess(ServerMember bot) {
    showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<ServerCubit>(),
        child: BotAccessDialog(bot: bot),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ManagePanel(
      title: 'Bots',
      subtitle: 'What each one can read and hear',
      footer: [
        AppButton(
          label: 'Browse bots',
          icon: const Icon(Icons.travel_explore_rounded, size: 16),
          onPressed: _browse,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isLoading)
            const LoadingBlock(padding: EdgeInsets.all(32))
          else if (_bots.isEmpty)
            const HintCard(
              icon: Icons.smart_toy_outlined,
              text:
                  'No bots here yet. Browse bots below to find one, or mint '
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
            for (final bot in _bots)
              BotRow(bot: bot, onTap: () => _openAccess(bot)),
          ],
        ],
      ),
    );
  }
}
