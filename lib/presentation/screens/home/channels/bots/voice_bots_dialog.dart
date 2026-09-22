import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/channel.dart';
import '../../../../../data/classes/server_member.dart';
import '../../../../../data/constants.dart';
import '../../../../../data/enums/server_permission.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/voice_listeners/voice_listeners_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/confirm_dialog.dart';
import '../../../../common/hint_card.dart';
import '../../../../common/loading_block.dart';
import 'widgets/channel_bot_row.dart';

/// Which bots can hear this call.
///
/// The sibling of [ChannelBotsDialog], and the differences are the point. That
/// one hands over a channel *key*, which is arithmetic — revoking rotates
/// forward and cannot unread what has been read — so it warns on the way in and
/// says the damage is permanent.
///
/// This one hands over a *permission*. Voice is not end-to-end encrypted
/// (ARCHITECTURE.md §5): subscription is a flag on a LiveKit token, so revoking
/// pushes `canSubscribe: false` onto the live connection and the audio stops
/// mid-call. It is still a real decision — a machine hearing every word said in
/// a room is not a small thing — but it is one that can genuinely be undone,
/// and pretending otherwise would make the warning next door mean less.
///
/// Nothing here is needed to *play* audio. A music bot publishes, which was
/// never the half that had to be allowed.
class VoiceBotsDialog extends StatefulWidget {
  final Channel channel;

  const VoiceBotsDialog({super.key, required this.channel});

  @override
  State<VoiceBotsDialog> createState() => _VoiceBotsDialogState();
}

class _VoiceBotsDialogState extends State<VoiceBotsDialog> {
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
    final listening = await cubit.voiceListenerIds(widget.channel.id);
    if (!mounted) return;

    setState(() {
      _bots = [
        for (final bot in bots)
          if (!bot.isBanned) bot,
      ];
      _granted = listening;
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
    final serverCubit = context.read<ServerCubit>();
    final listeners = context.read<VoiceListenersCubit>();

    final result = await serverCubit.setBotVoiceListen(
      channelId: widget.channel.id,
      botId: bot.id,
      listen: granting,
    );
    // The badge on the sidebar tile is the standing marker everyone else reads.
    // It is loaded once per server, so without this it keeps saying a bot can
    // hear a channel it was just shut out of.
    if (result.success) await listeners.refresh();
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

  /// Only granting asks. Taking it back is the safe direction, and a speed bump
  /// in front of that would be a speed bump in front of the fix.
  Future<bool> _confirmGrant(ServerMember bot) => showConfirmDialog(
    context: context,
    title: 'Let ${bot.displayName} hear ${widget.channel.name}?',
    message:
        'It will receive everyone’s audio in this channel, including yours, '
        'for as long as it is in the call. Everyone in the channel is told '
        'while it lasts. Unlike a text channel’s key, this can be taken back '
        '— stopping it cuts the audio straight away.',
    confirmLabel: 'Let it listen',
    icon: Icons.hearing_rounded,
    isDestructive: true,
  );

  @override
  Widget build(BuildContext context) {
    return AppModal(
      title: 'Bots hearing this',
      subtitle: widget.channel.name,
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
            const HintCard(
              icon: Icons.music_note_rounded,
              // The first thing an admin opening this will be trying to do is
              // usually the thing that needs nothing from them.
              text:
                  'A bot does not need this to play music. Every bot can '
                  'already speak into a call; this is only about hearing one.',
            ),
            const SizedBox(height: 12),
            if (!_mayManage) ...[
              const HintCard(
                icon: Icons.visibility_outlined,
                text:
                    'You can see which bots hear this channel. Changing it '
                    'needs the manage-bots permission.',
              ),
              const SizedBox(height: 12),
            ],
            for (final bot in _bots)
              ChannelBotRow(
                bot: bot,
                granted: _granted.contains(bot.id),
                busy: _busyId == bot.id,
                grantedNote: 'Hears everyone in this call.',
                ungrantedNote: 'Can speak here, hears nothing.',
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
