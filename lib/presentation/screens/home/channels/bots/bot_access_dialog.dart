import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../data/apis/bot_keys_api.dart';
import '../../../../../data/apis/voice_bots_api.dart';
import '../../../../../data/classes/channel.dart';
import '../../../../../data/classes/server_member.dart';
import '../../../../../data/constants.dart';
import '../../../../../data/enums/server_permission.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/confirm_dialog.dart';
import '../../../../common/hint_card.dart';
import '../../../../common/loading_block.dart';
import '../../../../common/server_scope.dart';
import '../../../settings/widgets/setting_toggle_row.dart';
import 'widgets/bot_access_list.dart';

/// Everything one bot can reach, in one place.
///
/// Before this it was discoverable a channel at a time — open each one, look at
/// the header. That is not an answer somebody can act on, and "what does this
/// thing see?" is the question the whole grant design is answerable for
/// (BOTS.md §6, rule 4).
///
/// About the server [ServerScope] names — the one the bot is on.
///
/// Reading and hearing are listed separately because they are separate grants
/// with separate consequences, and a single merged list would suggest one
/// switch turns both off. It does not: a channel key cannot be taken back, and
/// a call can.
class BotAccessDialog extends StatefulWidget {
  final ServerMember bot;

  const BotAccessDialog({super.key, required this.bot});

  @override
  State<BotAccessDialog> createState() => _BotAccessDialogState();
}

class _BotAccessDialogState extends State<BotAccessDialog> {
  Set<String> _channelIds = const {};
  Set<String> _voiceChannelIds = const {};
  bool _serverWide = false;
  bool _isLoading = true;
  bool _isBusy = false;

  /// The read of its access failed. Drawn as that, never as the empty lists,
  /// which say it reads and hears nothing.
  bool _loadFailed = false;
  String? _error;

  List<Channel> _channelsIn(Set<String> ids) {
    final all =
        context
            .read<ServerCubit>()
            .state
            .serverOn(ServerScope.read(context).serverId)
            ?.channels ??
        const <Channel>[];
    return [
      for (final channel in all)
        if (ids.contains(channel.id)) channel,
    ];
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final server = ServerScope.read(context);
    final access = await BotKeysApi(server).botChannels(widget.bot.id);
    final heard = await VoiceBotsApi(
      server,
    ).voiceChannelsHeardBy(widget.bot.id);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (access == null || heard == null) {
        _loadFailed = true;
        return;
      }
      _loadFailed = false;
      _channelIds = access.channelIds;
      _voiceChannelIds = heard;
      _serverWide = access.serverWide;
    });
  }

  Future<void> _toggleServerWide(bool next) async {
    if (next && !await _confirm()) return;
    if (!mounted) return;

    setState(() {
      _isBusy = true;
      _error = null;
    });
    final keys = BotKeysApi(ServerScope.read(context));
    final result = await keys.setBotServerKey(
      botId: widget.bot.id,
      granted: next,
    );
    if (!mounted) return;
    setState(() {
      _isBusy = false;
      if (!result.success) _error = result.error;
    });
    if (result.success) await _load();
  }

  /// Only granting asks. Taking access away is the safe direction, and a speed
  /// bump in front of it is a speed bump in front of the fix.
  Future<bool> _confirm() => showConfirmDialog(
    context: context,
    title: 'Let ${widget.bot.displayName} read every channel?',
    message:
        'It gets the key to every channel the whole server can see, including '
        'ones made later. Private channels are never included — those stay an '
        'individual decision. Everyone in each channel is told, and taking it '
        'back does not unread what it has already seen.',
    confirmLabel: 'Give it the keys',
    icon: Icons.hearing_rounded,
    isDestructive: true,
  );

  @override
  Widget build(BuildContext context) {
    final channels = _channelsIn(_channelIds);
    final heard = _channelsIn(_voiceChannelIds);
    final serverId = ServerScope.idOf(context);
    final mayManage = context.select<ServerCubit, bool>(
      (c) =>
          c.state.permissionsOn(serverId)?.can(ServerPermission.manageBots) ??
          false,
    );

    return AppModal(
      title: 'What it can reach',
      subtitle: widget.bot.displayName,
      maxWidth: K.dialogWidth,
      error: _error,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isLoading)
            const LoadingBlock(height: 140)
          else if (_loadFailed)
            HintCard(
              icon: Icons.cloud_off_outlined,
              text:
                  'Couldn\'t read what ${widget.bot.displayName} can reach. '
                  'Close this and try again.',
            )
          else ...[
            BotAccessList(
              label: 'Channels it can read',
              channels: channels,
              emptyIcon: Icons.visibility_off_outlined,
              emptyText:
                  'It reads nothing. It only sees messages sent to it — '
                  'commands, and presses on its own panels.',
              control: SettingToggleRow(
                title: 'Every public channel',
                description:
                    'Including channels made later. A private channel is '
                    'never covered — that stays one decision at a time.',
                value: _serverWide,
                onChanged: mayManage && !_isBusy ? _toggleServerWide : null,
              ),
            ),
            const SizedBox(height: 20),
            // Silence is the default and worth saying, because it is the
            // opposite of what somebody arriving from Discord expects. A bot in
            // a call there receives everything; here its token cannot subscribe
            // at all unless this list names the channel.
            BotAccessList(
              label: 'Calls it can hear',
              channels: heard,
              emptyIcon: Icons.volume_off_outlined,
              emptyText:
                  'It hears nothing. It can still speak in any call — '
                  'playing music never needed permission.',
            ),
          ],
        ],
      ),
      actions: [
        AppButton(
          label: 'Done',
          variant: AppButtonVariant.secondary,
          onPressed: _isBusy ? null : () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
