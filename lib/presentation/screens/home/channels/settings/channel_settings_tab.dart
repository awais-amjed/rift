import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/channel.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';

/// The pages of a channel's settings, in nav order.
enum ChannelSettingsTab { overview, access, bots, webhooks, delete }

extension ChannelSettingsTabLabel on ChannelSettingsTab {
  String get label => switch (this) {
    ChannelSettingsTab.overview => 'Overview',
    ChannelSettingsTab.access => 'Access',
    ChannelSettingsTab.bots => 'Bots',
    ChannelSettingsTab.webhooks => 'Webhooks',
    ChannelSettingsTab.delete => 'Delete',
  };

  IconData get icon => switch (this) {
    ChannelSettingsTab.overview => Icons.tune_rounded,
    ChannelSettingsTab.access => Icons.lock_outline_rounded,
    ChannelSettingsTab.bots => Icons.smart_toy_outlined,
    ChannelSettingsTab.webhooks => Icons.webhook_rounded,
    ChannelSettingsTab.delete => Icons.delete_outline_rounded,
  };
}

/// Whether the viewer runs [channel].
///
/// A private channel is run from inside it: the seat its creator was given,
/// not the server-wide permission, which holds no key to the room and is
/// refused by the server for it. A public one is the permission. Watched, so
/// a role change takes the gear and the pages away while they are on screen.
bool canManageChannel(BuildContext context, Channel channel) {
  if (channel.isPrivate) return channel.canManage;
  return context.select<ServerCubit, bool>(
    (c) => c.state.selectedServer?.user?.permissions.isChannelManager ?? false,
  );
}

/// Which pages somebody gets.
///
/// A manager gets all of them that apply to the channel's kind — webhooks
/// post messages, so a voice channel has none. Anyone else inside a private
/// channel gets Access alone, read-only: knowing who else can read what you
/// are about to say is the point of the room being private, and not a thing
/// you should need a permission to find out. Everyone else gets nothing.
List<ChannelSettingsTab> visibleChannelSettingsTabs(
  Channel channel, {
  required bool canManage,
}) {
  if (!canManage) {
    return channel.isPrivate ? const [ChannelSettingsTab.access] : const [];
  }
  return [
    ChannelSettingsTab.overview,
    ChannelSettingsTab.access,
    ChannelSettingsTab.bots,
    if (channel.hasMessages) ChannelSettingsTab.webhooks,
    ChannelSettingsTab.delete,
  ];
}
