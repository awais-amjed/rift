import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../../data/apis/members_api.dart';
import '../../../../../../data/classes/server_member.dart';
import '../../../../../../data/enums/server_permission.dart';
import '../../../../../../data/repositories/server_session.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../common/hint_card.dart';
import '../../../../../common/loading_block.dart';
import '../../../../../common/server_scope.dart';
import '../../../servers/manage/widgets/manage_panel.dart';
import 'channel_bot_row.dart';

/// A channel's bots, each with a switch for one grant: the shell shared by
/// `ChannelBotsPanel` (a text channel's key) and `VoiceBotsPanel` (hearing a
/// call).
///
/// The loading, the failed read, the empty server, the read-only notice and
/// the one-at-a-time switches are the same for both, and were two copies.
/// What each grant *is* stays with its panel: how it is read, the confirm on
/// the way in, and what has to hear about the change.
class BotGrantPanel extends StatefulWidget {
  final String subtitle;

  /// Finishes "You can see which bots …": "hear this channel".
  final String watchedVerb;

  /// The bots holding the grant here, or null when the read failed.
  final Future<Set<String>?> Function(ServerSession session) loadGranted;

  /// Asked before granting only. Taking it back is the safe direction, and a
  /// speed bump in front of that would be a speed bump in front of the fix.
  final Future<bool> Function(ServerMember bot) confirmGrant;

  /// Grants or takes back, and tells whatever shows the grant elsewhere.
  final Future<({bool success, String? error})> Function(
    ServerSession session,
    ServerMember bot,
    bool granting,
  )
  setGranted;

  /// Above the list, when there are bots to list.
  final Widget? hint;
  final String? grantedNote;
  final String? ungrantedNote;

  const BotGrantPanel({
    super.key,
    required this.subtitle,
    required this.watchedVerb,
    required this.loadGranted,
    required this.confirmGrant,
    required this.setGranted,
    this.hint,
    this.grantedNote,
    this.ungrantedNote,
  });

  @override
  State<BotGrantPanel> createState() => _BotGrantPanelState();
}

class _BotGrantPanelState extends State<BotGrantPanel> {
  List<ServerMember> _bots = const [];
  Set<String> _granted = {};
  bool _isLoading = true;

  /// The read of who holds access failed: drawn as that, not as every bot
  /// switched off, which offered a revoke only after a "grant".
  bool _loadFailed = false;
  String? _busyId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = ServerScope.read(context);
    // Every bot, not a page of them: this is a picker, and one that silently
    // left a bot out would be the bug the paged roster exists to fix.
    final bots = await MembersApi(session).listBotsOrNull();
    final granted = await widget.loadGranted(session);
    if (!mounted) return;

    setState(() {
      _bots = [
        for (final bot in bots ?? const <ServerMember>[])
          if (!bot.isBanned) bot,
      ];
      _granted = granted ?? {};
      _loadFailed = bots == null || granted == null;
      _isLoading = false;
    });
  }

  Future<void> _toggle(ServerMember bot) async {
    final granting = !_granted.contains(bot.id);
    if (granting && !await widget.confirmGrant(bot)) return;
    if (!mounted) return;

    setState(() {
      _busyId = bot.id;
      _error = null;
    });
    final result = await widget.setGranted(
      ServerScope.read(context),
      bot,
      granting,
    );
    if (!mounted) return;

    setState(() {
      _busyId = null;
      if (result.success) {
        granting ? _granted.add(bot.id) : _granted.remove(bot.id);
      } else {
        _error = result.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final serverId = ServerScope.idOf(context);
    // Selected, so being given or losing the permission while the page is
    // open moves the switches; and `can`, which answers on a server from
    // before the bits.
    final mayManage = context.select<ServerCubit, bool>(
      (c) =>
          c.state.permissionsOn(serverId)?.can(ServerPermission.manageBots) ??
          false,
    );
    return ManagePanel(
      title: 'Bots',
      subtitle: widget.subtitle,
      error: _error,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isLoading)
            const LoadingBlock(height: 140)
          else if (_loadFailed)
            const HintCard(
              icon: Icons.cloud_off_outlined,
              text:
                  'Couldn\'t read which bots have access here. Close this '
                  'and try again.',
            )
          else if (_bots.isEmpty)
            const HintCard(
              icon: Icons.smart_toy_outlined,
              text:
                  'No bots on this server yet. A bot joins through an invite '
                  'created from “Invite people” with Bot chosen.',
            )
          else ...[
            if (widget.hint case final hint?) ...[
              hint,
              const SizedBox(height: 12),
            ],
            if (!mayManage) ...[
              HintCard(
                icon: Icons.visibility_outlined,
                text:
                    'You can see which bots ${widget.watchedVerb}. Changing '
                    'it needs the manage-bots permission.',
              ),
              const SizedBox(height: 12),
            ],
            for (final bot in _bots) _row(bot, mayManage),
          ],
        ],
      ),
    );
  }

  Widget _row(ServerMember bot, bool mayManage) => ChannelBotRow(
    bot: bot,
    granted: _granted.contains(bot.id),
    busy: _busyId == bot.id,
    grantedNote: widget.grantedNote,
    ungrantedNote: widget.ungrantedNote,
    onChanged: mayManage && _busyId == null ? () => _toggle(bot) : null,
  );
}
