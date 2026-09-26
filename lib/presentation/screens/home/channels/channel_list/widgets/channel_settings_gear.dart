import 'package:flutter/material.dart';

import '../../../../../../data/classes/channel.dart';
import '../../../../../../data/constants.dart';
import '../../../../../theme/theme_context.dart';
import '../../settings/channel_settings_tab.dart';
import 'channel_menu_actions.dart';

/// The gear a channel row shows under the pointer, for whoever runs it.
///
/// Hover only: at rest the sidebar is names and counts, and a gear on every
/// row would be a column of the same icon. A touch screen has no hover and
/// keeps the long-press menu, which has the same way in.
class ChannelSettingsGear extends StatelessWidget {
  final Channel channel;

  const ChannelSettingsGear({super.key, required this.channel});

  /// [trailing] with the gear after it when [hovered] and the viewer runs
  /// the channel — what a row puts in its trailing slot.
  static Widget? beside(
    BuildContext context,
    Widget? trailing, {
    required Channel channel,
    required bool hovered,
  }) {
    if (!hovered || !canManageChannel(context, channel)) return trailing;
    final gear = ChannelSettingsGear(channel: channel);
    if (trailing == null) return gear;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [trailing, gear],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Channel settings',
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(K.radiusRow),
        onTap: () => openChannelSettings(context, channel),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            Icons.settings_outlined,
            size: K.iconInline,
            color: context.theme.textTertiary,
          ),
        ),
      ),
    );
  }
}
