import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/server.dart';
import '../../../../../../data/classes/server_member.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../common/hint_card.dart';
import '../../../../../common/loading_dots.dart';
import '../../../../../theme/theme_context.dart';
import '../../../channels/bots/bot_access_dialog.dart';
import '../widgets/bot_row.dart';
import '../widgets/manage_panel.dart';

/// The bots page of the manage-server dialog: every bot on the server, and
/// what each one can reach.
///
/// A bot's grants are per channel, and until now they were only findable a
/// channel at a time. This is the other way in: start from the bot, see
/// everything it holds ([BotAccessDialog]), and take any of it back. Adding
/// one is the invites page's job — a bot joins through an invite marked as
/// for a bot — so this only says so.
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
    final themeState = context.theme;
    return ManagePanel(
      title: 'Bots',
      subtitle: 'What each one can read and hear',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: LoadingDots(color: themeState.accentBright, dotSize: 6),
              ),
            )
          else if (_bots.isEmpty)
            const HintCard(
              icon: Icons.smart_toy_outlined,
              text:
                  'No bots here yet. A bot joins through an invite with '
                  '“this invite is for a bot” ticked — mint one under '
                  'Invites.',
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
