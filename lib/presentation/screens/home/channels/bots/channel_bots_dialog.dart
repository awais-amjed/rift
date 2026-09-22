import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/channel.dart';
import '../../../../../data/classes/server_member.dart';
import '../../../../../data/constants.dart';
import '../../../../../data/enums/server_permission.dart';
import '../../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/confirm_dialog.dart';
import '../../../../common/hint_card.dart';
import '../../../../common/loading_block.dart';
import 'widgets/channel_bot_row.dart';

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
class ChannelBotsDialog extends StatefulWidget {
  final Channel channel;

  const ChannelBotsDialog({super.key, required this.channel});

  @override
  State<ChannelBotsDialog> createState() => _ChannelBotsDialogState();
}

class _ChannelBotsDialogState extends State<ChannelBotsDialog> {
  List<ServerMember> _bots = const [];
  Set<String> _granted = {};
  bool _isLoading = true;
  String? _busyId;
  String? _error;

  bool get _mayManage => context.read<ServerCubit>().state.myPermissionBits.has(
    ServerPermission.manageBots,
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cubit = context.read<ServerCubit>();
    // Every bot, not a page of them: this is a picker, and one that silently
    // left a bot out would be the bug the paged roster exists to fix.
    final bots = await cubit.listBots();
    final listeners = await cubit.channelListenerIds(widget.channel.id);
    if (!mounted) return;

    setState(() {
      _bots = [
        for (final bot in bots)
          if (!bot.isBanned) bot,
      ];
      _granted = listeners;
      _isLoading = false;
    });
  }

  Future<void> _toggle(ServerMember bot) async {
    final granting = !_granted.contains(bot.id);
    if (granting && !await _confirmGrant(bot)) return;
    if (!mounted) return;

    setState(() {
      _busyId = bot.id;
      _error = null;
    });
    final result = await context.read<ServerCubit>().setBotChannelKey(
      channelId: widget.channel.id,
      botId: bot.id,
      granted: granting,
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

    // The header's chip is the standing marker every member in the room reads.
    // It is loaded when a channel opens, so without this it keeps saying a bot
    // is reading a channel it was just shut out of — for as long as the channel
    // stays open, which is exactly the case that matters.
    if (result.success && context.mounted) {
      unawaited(context.read<ChannelChatCubit>().refreshBotListeners());
    }
  }

  /// Only granting asks. Taking access away is the safe direction, and a speed
  /// bump in front of it would be a speed bump in front of the fix.
  Future<bool> _confirmGrant(ServerMember bot) => showConfirmDialog(
    context: context,
    title: 'Let ${bot.displayName} read #${widget.channel.name}?',
    message:
        'It gets this channel’s encryption key and can read every message '
        'sent here from now on — including yours. It cannot read anything '
        'said before. Everyone in the channel is told, and taking it back '
        'later does not unread what it has already seen.',
    confirmLabel: 'Give it the key',
    icon: Icons.hearing_rounded,
    isDestructive: true,
  );

  @override
  Widget build(BuildContext context) {
    return AppModal(
      title: 'Bots reading this',
      subtitle: '#${widget.channel.name}',
      maxWidth: K.dialogWidth,
      error: _error,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isLoading)
            const LoadingBlock(height: 140)
          else if (_bots.isEmpty)
            const HintCard(
              icon: Icons.smart_toy_outlined,
              text:
                  'No bots on this server yet. A bot joins through an invite '
                  'with “this invite is for a bot” ticked.',
            )
          else ...[
            if (!_mayManage) ...[
              const HintCard(
                icon: Icons.visibility_outlined,
                text:
                    'You can see which bots read this channel. Changing it '
                    'needs the manage-bots permission.',
              ),
              const SizedBox(height: 12),
            ],
            for (final bot in _bots)
              ChannelBotRow(
                bot: bot,
                granted: _granted.contains(bot.id),
                busy: _busyId == bot.id,
                onChanged: _mayManage && _busyId == null
                    ? () => _toggle(bot)
                    : null,
              ),
          ],
        ],
      ),
      actions: [
        AppButton(
          label: 'Done',
          variant: AppButtonVariant.secondary,
          onPressed: _busyId != null ? null : () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
