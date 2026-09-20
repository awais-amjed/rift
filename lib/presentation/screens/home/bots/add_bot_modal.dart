import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/public_bot.dart';
import '../../../../data/classes/server.dart';
import '../../../../data/constants.dart';
import '../../../../data/enums/server_permission.dart';
import '../../../../data/invite_link.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../common/app_button.dart';
import '../../../common/app_modal.dart';
import '../../../common/empty_state.dart';
import '../../../common/hint_card.dart';
import '../../../common/nav_row.dart';
import 'widgets/bot_setup_card.dart';

/// Adding a listed bot to one of your servers.
///
/// **The invite travels the other way round from a server listing, and that
/// is the whole of this screen.** Joining a listed server means using the
/// invite the listing carries. A bot has no address to send anything to — it
/// runs on the author's machine, or on yours — so adding one means *your*
/// server minting a bot invite and you handing it to the program. Central is
/// not involved and never hears that it happened, which is also why the
/// directory ranks on likes rather than on installs.
///
/// Two steps, because they are two different acts: pick the server (a
/// decision), then run the bot (a thing to do elsewhere, with a string to
/// copy).
class AddBotModal extends StatefulWidget {
  final PublicBot bot;
  final VoidCallback onCancel;
  final VoidCallback onDone;

  const AddBotModal({
    super.key,
    required this.bot,
    required this.onCancel,
    required this.onDone,
  });

  @override
  State<AddBotModal> createState() => _AddBotModalState();
}

class _AddBotModalState extends State<AddBotModal> {
  /// The invite this server minted, once it has. Non-null means the second
  /// step.
  String? _inviteLink;
  Server? _server;
  bool _minting = false;
  String? _error;

  /// The servers this account may put a bot on.
  ///
  /// `manageBots` rather than admin: it is the bit that governs bots
  /// everywhere else, and minting a bot invite is refused by the invite
  /// policy for anybody without it — so offering a server here that the
  /// server itself would refuse is offering a dead end.
  List<Server> get _eligible => [
    for (final server in context.read<ServerCubit>().state.servers)
      if (server.user?.permissions.can(ServerPermission.manageBots) ?? false)
        server,
  ];

  Future<void> _mint(Server server) async {
    setState(() {
      _minting = true;
      _server = server;
      _error = null;
    });

    // Single-use and never-expiring: the link is for one program, and it is
    // spent the moment that program first runs. An unlimited one left in a
    // config file would mint a second bot on every fresh seed.
    final result = await context.read<ServerCubit>().createInvite(
      serverId: server.id,
      isBot: true,
      maxUses: 1,
    );
    if (!mounted) return;

    setState(() {
      _minting = false;
      _error = result.error;
      _inviteLink = result.inviteCode == null
          ? null
          : _linkFor(server, result.inviteCode!);
    });
  }

  /// The plain `<server-url>#<code>` form, not the clickable joinrift.app
  /// wrapper. Nobody is clicking this — it goes into a config file, and the
  /// SDK's `parseInvite` takes any of the three shapes, so the one without a
  /// domain the author does not run is the honest one.
  String _linkFor(Server server, String code) =>
      InviteLink.buildPlain(server.supabaseUrl, code);

  @override
  Widget build(BuildContext context) {
    final link = _inviteLink;
    final server = _server;

    return AppModal(
      pageOnPhone: true,
      onBack: widget.onCancel,
      title: link == null ? 'Add ${widget.bot.name}' : 'Run ${widget.bot.name}',
      subtitle: link == null
          ? 'Which server is it joining?'
          : 'On ${server?.name ?? 'your server'}',
      maxWidth: K.dialogWidth,
      content: link == null
          ? _pickServer()
          : BotSetupCard(bot: widget.bot, inviteLink: link),
      actions: [
        AppButton(
          label: link == null ? 'Back' : 'Done',
          variant: link == null
              ? AppButtonVariant.secondary
              : AppButtonVariant.primary,
          onPressed: link == null ? widget.onCancel : widget.onDone,
        ),
      ],
    );
  }

  Widget _pickServer() {
    final servers = _eligible;
    if (servers.isEmpty) {
      return const EmptyState(
        icon: Icons.dns_outlined,
        title: 'No server to add it to',
        message:
            'Adding a bot needs a server where you can manage bots. Join one '
            'as an admin, or create your own.',
      );
    }

    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (error != null) ...[
          HintCard(icon: Icons.error_outline_rounded, text: error),
          const SizedBox(height: 12),
        ],
        for (final server in servers)
          NavRow(
            label: server.name,
            icon: Icons.dns_outlined,
            isSelected: _minting && server.id == _server?.id,
            onTap: _minting ? null : () => _mint(server),
          ),
        const SizedBox(height: 12),
        const HintCard(
          icon: Icons.vpn_key_outlined,
          text:
              'Your server mints a single-use invite marked as a bot. It is '
              'spent the first time the program runs, and it is the only '
              'thing that ever leaves this dialog — the bot signs in with a '
              'key it makes itself, which Rift never sees.',
        ),
      ],
    );
  }
}
