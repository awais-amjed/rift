import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/channel.dart';
import '../../../../../data/enums/channel_type.dart';
import '../../../../../data/enums/home_surface.dart';
import '../../../../../data/enums/server_permission.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../common/app_modal.dart';
import '../../mobile/mobile_shell_scope.dart';
import '../confirm_voice_switch.dart';
import '../create_channel_dialog.dart';
import 'widgets/empty_channels_view.dart';
import 'widgets/section_header.dart';
import 'widgets/text_channel_tile.dart';
import 'widgets/voice_channel_tile/voice_channel_tile.dart';

/// Lists all channels grouped by type. Voice channels show live participants.
class ChannelList extends StatelessWidget {
  final List<Channel> channels;
  final String? selectedChannelId;
  final ValueChanged<String?>? onChannelSelect;

  const ChannelList({
    super.key,
    required this.channels,
    this.selectedChannelId,
    this.onChannelSelect,
  });

  @override
  Widget build(BuildContext context) {
    final textChannels = channels
        .where((c) => c.channelType == ChannelType.text)
        .toList();
    final voiceChannels = channels
        .where((c) => c.channelType == ChannelType.voice)
        .toList();

    final me = context.watch<ServerCubit>().state.selectedServer?.user;

    // A ban leaves your permissions untouched — it only stops any of them
    // working — so a banned channel manager was still being offered the "+"
    // and a "Create the first one" button that could not succeed.
    final banned = me?.isBanned ?? false;

    // Channel managers get the "+", and so does anybody who may make a private
    // one — which on a default server is everybody. A private
    // channel is how a handful of people talk without asking permission, so
    // gating the button on `MANAGE_CHANNELS` would have meant asking.
    final permissions = me?.permissions;
    final canCreate =
        !banned &&
        (permissions?.can(ServerPermission.manageChannels) == true ||
            permissions?.can(ServerPermission.createPrivateChannel) == true);
    // The "+" opens the dialog on the kind of channel its own header is
    // for. It is the only way to make a voice channel, and it used to open
    // on Text whatever was pressed — so pressing the one under VOICE and
    // typing a name made a text channel, quietly, in the other section.
    void openCreateChannel(ChannelType type) => showCustomDialog(
      context: context,
      build: (_) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: context.read<ServerCubit>()),
          BlocProvider.value(value: context.read<AppCubit>()),
        ],
        child: CreateChannelDialog(initialType: type),
      ),
    );

    // Computed before this branch, not after it: the empty state needs the
    // same button the headers carry, and a new server starts here.
    if (channels.isEmpty) {
      // Nothing at all when banned: the empty state talks about channels
      // arriving, and the pane beside it has already said why none will. Two
      // explanations, one of them wrong, is worse than one.
      if (banned) return const Expanded(child: SizedBox.shrink());
      return Expanded(
        child: EmptyChannelsView(
          // A server's first channel is one people can talk in.
          onCreate: canCreate
              ? () => openCreateChannel(ChannelType.text)
              : null,
        ),
      );
    }

    // Rows are built only as they scroll in: a server can hold hundreds of
    // channels, and a voice tile watches its own participants.
    final rows = <Widget Function()>[
      if (textChannels.isNotEmpty) ...[
        () => SectionHeader(
          label: 'Text',
          addTooltip: 'Create text channel',
          onAdd: canCreate ? () => openCreateChannel(ChannelType.text) : null,
        ),
        for (final ch in textChannels)
          () => _spaced(TextChannelTile(key: ValueKey(ch.id), channel: ch)),
      ],
      if (voiceChannels.isNotEmpty) ...[
        () => SectionHeader(
          label: 'Voice',
          addTooltip: 'Create voice channel',
          onAdd: canCreate ? () => openCreateChannel(ChannelType.voice) : null,
        ),
        for (final ch in voiceChannels)
          () => _spaced(
            VoiceChannelTile(
              key: ValueKey(ch.id),
              channel: ch,
              isSelected: selectedChannelId == ch.id,
              onTap: () => _openVoice(context, ch),
            ),
          ),
      ],
    ];

    return Expanded(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: rows.length,
        itemBuilder: (context, i) => rows[i](),
      ),
    );
  }

  /// Half the gap between two channel rows, above and below each.
  ///
  /// The list's, not the rows': a voice channel is a plain row until someone
  /// joins and a card after, and a gap the card carried itself would move the
  /// channel's name the moment it turned into one. Here both shapes get the
  /// same, so two cards side by side don't touch, and neither do two lit
  /// text rows.
  static const double _rowGap = 2;

  static Widget _spaced(Widget row) => Padding(
    padding: const EdgeInsets.symmetric(vertical: _rowGap),
    child: row,
  );

  Future<void> _openVoice(BuildContext context, Channel ch) async {
    // On a phone the call is a page: tapping the one you are already in takes
    // you back into it.
    final shell = MobileShellScope.maybeOf(context);
    if (shell != null && selectedChannelId == ch.id) {
      shell.openCall();
      return;
    }
    // Asked before anything moves, so cancelling leaves the screen exactly as
    // it was — the chat you were reading included.
    if (!await confirmVoiceSwitch(context, ch)) return;
    if (!context.mounted) return;
    if (shell != null) {
      onChannelSelect?.call(ch.id);
      return;
    }
    // Joining voice brings the voice pane back to the front.
    context.read<AppCubit>().setSurface(HomeSurface.server);
    unawaited(context.read<ChannelChatCubit>().closeChannel());
    if (selectedChannelId != ch.id) onChannelSelect?.call(ch.id);
  }
}
