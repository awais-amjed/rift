import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/channel.dart';
import '../../../../../../data/enums/home_surface.dart';
import '../../../../../../data/enums/channel_type.dart';
import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../common/app_modal.dart';
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

    // Only channel managers get the "+" on a section header.
    final canCreate = !banned && (me?.permissions.isChannelManager ?? false);
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

    // Computed before this branch, not after it: the empty state needs the
    // same button the headers carry, and a new server starts here.
    if (channels.isEmpty) {
      // Nothing at all when banned: the empty state talks about channels
      // arriving, and the pane beside it has already said why none will. Two
      // explanations, one of them wrong, is worse than one.
      if (banned) return const Expanded(child: SizedBox.shrink());
      return Expanded(
        child: EmptyChannelsView(
          onCreate: canCreate ? openCreateChannel : null,
        ),
      );
    }

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
                  context.read<AppCubit>().setSurface(HomeSurface.server);
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
