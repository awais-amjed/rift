import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/channel.dart';
import '../../../../../data/classes/server_member.dart';
import '../../../../../data/enums/channel_type.dart';
import '../../../../../data/enums/server_permission.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/confirm_dialog.dart';
import '../../../../common/hint_card.dart';
import '../../../../common/message_banner.dart';
import '../../../../theme/app_text.dart';
import '../../../settings/widgets/setting_toggle_row.dart';

/// Everything one bot can read, in one place.
///
/// Before this it was discoverable a channel at a time — open each one, look at
/// the header. That is not an answer somebody can act on, and "what does this
/// thing see?" is the question the whole grant design is answerable for
/// (BOTS.md §6, rule 4).
class BotAccessDialog extends StatefulWidget {
  final ServerMember bot;

  const BotAccessDialog({super.key, required this.bot});

  @override
  State<BotAccessDialog> createState() => _BotAccessDialogState();
}

class _BotAccessDialogState extends State<BotAccessDialog> {
  Set<String> _channelIds = const {};
  bool _serverWide = false;
  bool _isLoading = true;
  bool _isBusy = false;
  String? _error;

  bool get _mayManage =>
      (context
                  .read<ServerCubit>()
                  .state
                  .selectedServer
                  ?.user
                  ?.permissions
                  .bits ??
              0)
          .has(ServerPermission.manageBots);

  List<Channel> get _channels {
    final all =
        context.read<ServerCubit>().state.selectedServer?.channels ??
        const <Channel>[];
    return [
      for (final channel in all)
        if (_channelIds.contains(channel.id)) channel,
    ];
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final access = await context.read<ServerCubit>().botChannels(widget.bot.id);
    if (!mounted) return;
    setState(() {
      _channelIds = access.channelIds;
      _serverWide = access.serverWide;
      _isLoading = false;
    });
  }

  Future<void> _toggleServerWide(bool next) async {
    if (next && !await _confirm()) return;
    if (!mounted) return;

    setState(() {
      _isBusy = true;
      _error = null;
    });
    final result = await context.read<ServerCubit>().setBotServerKey(
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
    final themeState = context.watch<ThemeCubit>().state;
    final channels = _channels;

    return AppModal(
      title: 'What it can read',
      subtitle: widget.bot.displayName,
      maxWidth: 480,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null) ...[
            MessageBanner(message: _error!, kind: MessageBannerKind.error),
            const SizedBox(height: 12),
          ],
          if (_isLoading)
            const SizedBox(
              height: 140,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else ...[
            SettingToggleRow(
              themeState: themeState,
              title: 'Every public channel',
              description:
                  'Including channels made later. A private channel is never '
                  'covered — that stays one decision at a time.',
              value: _serverWide,
              onChanged: _mayManage && !_isBusy ? _toggleServerWide : null,
            ),
            const SizedBox(height: 16),
            if (channels.isEmpty)
              const HintCard(
                icon: Icons.visibility_off_outlined,
                text:
                    'It reads nothing. It only sees messages sent to it — '
                    'commands, and presses on its own panels.',
              )
            else
              for (final channel in channels)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    spacing: 8,
                    children: [
                      Icon(
                        channel.channelType == ChannelType.voice
                            ? Icons.volume_up_rounded
                            : Icons.tag_rounded,
                        size: 15,
                        color: themeState.textTertiary,
                      ),
                      Expanded(
                        child: Text(
                          channel.name,
                          style: AppText.row.copyWith(
                            color: themeState.textPrimary,
                          ),
                        ),
                      ),
                      if (channel.isPrivate)
                        Icon(
                          Icons.lock_rounded,
                          size: 13,
                          color: themeState.textTertiary,
                        ),
                    ],
                  ),
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
