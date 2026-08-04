import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/channel.dart';
import '../../../../../../data/enums/channel_type.dart';
import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../common/app_modal.dart';
import '../create_channel_dialog.dart';
import 'widgets/empty_channels_view.dart';
import 'widgets/section_header.dart';
import 'widgets/text_channel_tile.dart';
import 'widgets/voice_channel_tile.dart';

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

    if (channels.isEmpty) {
      return const Expanded(child: EmptyChannelsView());
    }

    // Only channel managers get the "+" on a section header.
    final canCreate =
        context
            .watch<ServerCubit>()
            .state
            .selectedServer
            ?.user
            ?.permissions
            .isChannelManager ??
        false;
    void openCreateChannel() => showCustomDialog(
      context: context,
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: context.read<ServerCubit>()),
          BlocProvider.value(value: context.read<AppCubit>()),
        ],
        child: const CreateChannelDialog(),
      ),
    );

    return Expanded(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: [
          if (textChannels.isNotEmpty) ...[
            SectionHeader(
              label: 'Text',
              addTooltip: 'Create channel',
              onAdd: canCreate ? openCreateChannel : null,
            ),
            ...textChannels.map((ch) => TextChannelTile(channel: ch)),
          ],
          if (voiceChannels.isNotEmpty) ...[
            SectionHeader(
              label: 'Voice',
              addTooltip: 'Create channel',
              onAdd: canCreate ? openCreateChannel : null,
            ),
            ...voiceChannels.map(
              (ch) => VoiceChannelTile(
                channel: ch,
                isSelected: selectedChannelId == ch.id,
                onTap: () {
                  // Joining voice brings the voice pane back to the front.
                  context.read<AppCubit>().setHomeViewOpen(false);
                  context.read<ChannelChatCubit>().closeChannel();
                  if (selectedChannelId != ch.id) {
                    onChannelSelect?.call(ch.id);
                  }
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
