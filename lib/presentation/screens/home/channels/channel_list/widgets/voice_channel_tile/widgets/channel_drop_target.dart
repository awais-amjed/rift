import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../../data/classes/voice_drag.dart';
import '../../../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../../../logic/helper_methods.dart';

/// A voice channel you can drop a member onto.
///
/// Two different things happen, and neither needs the menu:
///
/// * **Someone else** — the same `move_user` call the "Move to" submenu makes,
///   refused server-side if we aren't staff. The drag is only offered to staff
///   in the first place, so a refusal here means the permission changed under
///   us; it's reported rather than swallowed.
/// * **Ourselves** — no round trip at all. Dropping yourself on a channel is
///   joining it, so it goes through the selected channel like a click does.
///
/// A drop back on the channel they came from is rejected before it starts, so
/// the tile doesn't light up for a move that would do nothing.
class ChannelDropTarget extends StatelessWidget {
  final String channelId;

  /// Built with whether a member is currently hovering over this channel, so
  /// the tile can show it is the one that will catch the drop.
  final Widget Function(BuildContext context, bool isTargeted) builder;

  const ChannelDropTarget({
    super.key,
    required this.channelId,
    required this.builder,
  });

  Future<void> _drop(BuildContext context, VoiceDrag member) async {
    if (member.isLocal) {
      context.read<AppCubit>().setSelectedChannelId(channelId);
      return;
    }

    final response = await context.read<ServerCubit>().moveUser(
      userId: member.userId,
      channelId: channelId,
    );
    if (!response.success) {
      HelperMethods.showError(
        error: response.error ?? 'Could not move ${member.name}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<VoiceDrag>(
      onWillAcceptWithDetails: (details) =>
          details.data.fromChannelId != channelId,
      onAcceptWithDetails: (details) => _drop(context, details.data),
      builder: (context, candidate, _) =>
          builder(context, candidate.isNotEmpty),
    );
  }
}
