import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/channel.dart';
import '../../../../../data/enums/channel_type.dart';
import '../../../../../data/enums/server_permission.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/server_reach/server_reach_cubit.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/server_scope.dart';
import '../../../../responsive/shell_scope.dart';
import '../create_channel_dialog.dart';
import '../open_voice_channel.dart';
import 'widgets/channel_section.dart';
import 'widgets/empty_channels_view.dart';
import 'widgets/section_header.dart';
import 'widgets/text_channel_tile.dart';
import 'widgets/voice_channel_tile/voice_channel_tile.dart';

/// Lists all channels grouped by type. Voice channels show live participants.
class ChannelList extends StatelessWidget {
  final List<Channel> channels;
  final String? selectedChannelId;

  const ChannelList({
    super.key,
    required this.channels,
    this.selectedChannelId,
  });

  @override
  Widget build(BuildContext context) {
    final textChannels = channels
        .where((c) => c.channelType == ChannelType.text)
        .toList();
    final voiceChannels = channels
        .where((c) => c.channelType == ChannelType.voice)
        .toList();

    final me = context
        .watch<ServerCubit>()
        .state
        .serverOn(ServerScope.idOf(context))
        ?.user;
    // Selected, not watched: presence moves several times a second in a busy
    // call, and this list only needs to know when the first answer is in.
    final voiceKnown = context.select(
      (ChannelPresenceCubit c) => c.state.voiceKnown,
    );
    // Out of reach, no answer is coming, and dots would say one is.
    final reachable = context.select(
      (ServerReachCubit c) => c.state.unreachableName == null,
    );

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

    // Moving channels is managing them: the same permission as the "+" for a
    // public one. Not on a phone, where holding a row opens its menu.
    final canReorder =
        !banned &&
        permissions?.can(ServerPermission.manageChannels) == true &&
        !context.layoutMode.isCompact;

    // Rows are built only as they scroll in: a server can hold hundreds of
    // channels, and a voice tile watches its own participants. Each section
    // is its own reorderable list, so a channel can only be dragged among
    // its own kind.
    return Expanded(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            sliver: SliverMainAxisGroup(
              slivers: [
                if (textChannels.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: SectionHeader(
                      label: 'Text',
                      addTooltip: 'Create text channel',
                      onAdd: canCreate
                          ? () => openCreateChannel(ChannelType.text)
                          : null,
                    ),
                  ),
                  ChannelSection(
                    channels: textChannels,
                    canReorder: canReorder,
                    rowBuilder: (context, ch, grip) =>
                        grip(TextChannelTile(channel: ch)),
                  ),
                ],
                if (voiceChannels.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: SectionHeader(
                      label: 'Voice',
                      busy: !voiceKnown && reachable,
                      addTooltip: 'Create voice channel',
                      onAdd: canCreate
                          ? () => openCreateChannel(ChannelType.voice)
                          : null,
                    ),
                  ),
                  ChannelSection(
                    channels: voiceChannels,
                    canReorder: canReorder,
                    rowBuilder: (context, ch, grip) => VoiceChannelTile(
                      channel: ch,
                      isSelected: selectedChannelId == ch.id,
                      headerGrip: grip,
                      onTap: () => openVoiceChannel(context, ch),
                      onWatch: (userId) => watchStreamIn(context, ch, userId),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
